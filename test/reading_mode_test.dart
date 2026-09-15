import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/mobile_media.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/ui/widgets/chat_composer.dart';
import 'package:chatstudio/ui/widgets/reading_handle.dart';
import 'support.dart';

class ReadingMedia implements MediaAccess {
  int disposed = 0;
  @override
  Future<List<LocalAttachment>> pick({required bool images}) async => [
    const LocalAttachment(
      path: '/fixture.txt',
      name: '草稿附件.txt',
      size: 12,
      mimeType: 'text/plain',
    ),
  ];
  @override
  Future<void> startRecording() async {}
  @override
  Future<String?> stopRecording() async => null;
  @override
  Future<void> cancelRecording() async {}
  @override
  Future<void> dispose() async {
    disposed++;
  }
}

void main() {
  Future<TestHarness> chat(WidgetTester tester) async {
    final h = TestHarness();
    await h.login();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    h.controller.sessionId = 'reading';
    h.controller.timeline.replace(
      List.generate(
        60,
        (i) => ChatMessage(
          id: '$i',
          role: i.isEven ? 'user' : 'assistant',
          content: '第 $i 条消息\n阅读历史内容，保留草稿和滚动位置。',
        ),
      ),
    );
    h.controller.dismissError();
    await tester.pumpAndSettle();
    return h;
  }

  Finder getList() => find.byKey(const Key('message-list'));
  ScrollPosition position(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: getList(), matching: find.byType(Scrollable)).first,
      )
      .position;

  testWidgets(
    'browsing history folds editor; manual restore retains state and draft',
    (tester) async {
      await chat(tester);
      final editor = tester.state(find.byKey(const Key('message-input')));
      await tester.enterText(find.byKey(const Key('message-input')), '保留我的草稿');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final height = tester.getSize(getList()).height;
      await tester.drag(getList(), const Offset(0, 420));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsOneWidget);
      expect(find.byKey(const Key('message-input')), findsNothing);
      expect(tester.getSize(getList()).height, greaterThan(height + 30));
      expect(find.text('继续编辑草稿'), findsNothing);
      expect(find.bySemanticsLabel('继续编辑草稿'), findsOneWidget);
      // The line overlays the bottom of the list; no footer row is reserved.
      final stage = tester.getRect(find.byKey(const Key('reading-stage')));
      expect(tester.getRect(getList()).bottom, closeTo(stage.bottom, 1));
      expect(
        tester.getRect(find.byKey(const Key('expand-composer'))).bottom,
        lessThan(stage.bottom),
      );
      expect(stage.bottom, closeTo(tester.view.physicalSize.height, 1));
      final offset = position(tester).pixels;
      await tester.tap(find.byKey(const Key('expand-composer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsNothing);
      expect(
        tester.state(find.byKey(const Key('message-input'))),
        same(editor),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        '保留我的草稿',
      );
      expect(position(tester).pixels, closeTo(offset, 1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'small scroll and programmatic history movement do not fold; latest restores',
    (tester) async {
      await chat(tester);
      position(tester).jumpTo(500);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsNothing);
      position(tester).jumpTo(0);
      await tester.pumpAndSettle();
      await tester.drag(getList(), const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsNothing);
      await tester.drag(getList(), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsOneWidget);
      await tester.tap(find.byTooltip('回到最新消息'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsNothing);
      expect(position(tester).pixels, closeTo(0, 1));
    },
  );
  testWidgets('new conversation restores editor from reading mode', (
    tester,
  ) async {
    final h = await chat(tester);
    await tester.drag(getList(), const Offset(0, 420));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collapsed-composer')), findsOneWidget);
    h.controller.newChat();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collapsed-composer')), findsNothing);
    expect(find.byKey(const Key('message-input')), findsOneWidget);
  });
  testWidgets('folded composer retains stop action during streaming', (
    tester,
  ) async {
    final h = await chat(tester);
    h.controller.timeline.working = true;
    h.controller.timeline.activity = '';
    h.controller.dismissError();
    await tester.pump();
    await tester.drag(getList(), const Offset(0, 420));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collapsed-stop-button')), findsOneWidget);
    await tester.tap(find.byKey(const Key('collapsed-stop-button')));
    await tester.pump();
    expect(h.transport.emitted.last.$1, 'abort');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'focused input and selected attachment stay expanded; folding never disposes media',
    (tester) async {
      final h = TestHarness();
      await h.login();
      final media = ReadingMedia(), input = TextEditingController();
      var collapsed = false;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Scaffold(
                body: ChatComposer(
                  controller: h.controller,
                  input: input,
                  media: media,
                  collapsed: collapsed,
                  onExpand: () => update(() => collapsed = false),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('message-input')));
      await tester.pump();
      update(() => collapsed = true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsOneWidget);
      expect(media.disposed, 0);
      await tester.tap(find.byKey(const Key('expand-composer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('attachment-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      update(() => collapsed = true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsNothing);
      expect(find.text('草稿附件.txt'), findsOneWidget);
      expect(media.disposed, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(media.disposed, 1);
      h.dispose();
      input.dispose();
    },
  );
  testWidgets('active recording cannot be folded', (tester) async {
    final h = TestHarness();
    h.override = (r) async => r.url.path.endsWith('profile-status')
        ? http.Response('{"configured":true,"activeProvider":"custom"}', 200)
        : h.response(r);
    await h.login();
    final media = ReadingMedia(), input = TextEditingController();
    var collapsed = false;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Scaffold(
              body: ChatComposer(
                controller: h.controller,
                input: input,
                media: media,
                collapsed: collapsed,
                onExpand: () {},
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('voice-button')));
    await tester.pump();
    await tester.pump();
    update(() => collapsed = true);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('collapsed-composer')), findsNothing);
    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.byTooltip('取消当前操作'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('collapsed-composer')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    h.dispose();
    input.dispose();
  });
  testWidgets(
    'floating line tracks loaded scroll range including new page metrics',
    (tester) async {
      final h = await chat(tester);
      await tester.drag(getList(), const Offset(0, 420));
      await tester.pumpAndSettle();
      double painted() =>
          (tester
                      .widget<CustomPaint>(
                        find.byKey(const Key('reading-progress-lines')),
                      )
                      .painter!
                  as ReadingHandlePainter)
              .progress;
      final initial = painted();
      expect(initial, greaterThan(0));
      position(tester).jumpTo(1800);
      await tester.pumpAndSettle();
      expect(painted(), greaterThan(initial));
      expect(painted(), closeTo(historyReadProgress(position(tester)), .001));
      h.controller.timeline.prepend(
        List.generate(
          40,
          (i) => ChatMessage(
            id: 'older-$i',
            role: 'assistant',
            content: '更早的历史内容\n继续回看。',
          ),
        ),
      );
      h.controller.dismissError();
      await tester.pumpAndSettle();
      expect(painted(), closeTo(historyReadProgress(position(tester)), .001));
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'floating line has accessible hit area without visible footer text $brightness',
      (tester) async {
        final progress = ValueNotifier<double>(.5);
        final semantics = tester.ensureSemantics();

        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Center(
                child: ReadingHandle(
                  progress: progress,
                  onExpand: () => taps++,
                ),
              ),
            ),
          ),
        );
        expect(find.text('展开输入框'), findsNothing);
        expect(find.bySemanticsLabel('展开输入框'), findsOneWidget);
        final target = tester.getRect(find.byKey(const Key('expand-composer')));
        expect(target.height, greaterThanOrEqualTo(48));
        expect(target.width, 128);
        await tester.tapAt(target.topLeft + const Offset(4, 4));
        await tester.pump();
        expect(taps, 1);
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const Key('reading-progress-lines')),
                    )
                    .painter!
                as ReadingHandlePainter;
        expect(painter.progress, .5);
        progress.value = 1;
        await tester.pumpAndSettle();
        final updated =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const Key('reading-progress-lines')),
                    )
                    .painter!
                as ReadingHandlePainter;
        expect(updated.progress, 1);
        expect(updated.shouldRepaint(painter), true);
        await tester.pumpWidget(const SizedBox.shrink());
        progress.dispose();
        semantics.dispose();
      },
    );
  }
  test('read progress handles overscroll, empty and unbounded ranges', () {
    double value(double pixels, double max) => historyReadProgress(
      FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: max,
        pixels: pixels,
        viewportDimension: 800,
        axisDirection: AxisDirection.up,
        devicePixelRatio: 1,
      ),
    );
    expect(value(500, 1000), .5);
    expect(value(-20, 1000), 0);
    expect(value(1100, 1000), 1);
    expect(value(0, 0), 0);
    expect(value(500, double.infinity), 0);
  });
  testWidgets(
    'floating controls clear gesture inset and each other on a small screen',
    (tester) async {
      final h = await chat(tester);
      tester.view.physicalSize = const Size(320, 700);
      tester.view.padding = const FakeViewPadding(bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      h.controller.timeline.working = true;
      h.controller.timeline.activity = '';
      h.controller.dismissError();
      await tester.pumpAndSettle();
      await tester.drag(getList(), const Offset(0, 420));
      await tester.pumpAndSettle();
      final handle = tester.getRect(find.byKey(const Key('expand-composer')));
      final stop = tester.getRect(
        find.byKey(const Key('collapsed-stop-button')),
      );
      final latest = tester.getRect(find.byTooltip('回到最新消息'));
      expect(handle.bottom, lessThanOrEqualTo(700 - 34));
      expect(handle.overlaps(stop), false);
      expect(handle.overlaps(latest), false);
      expect(stop.overlaps(latest), false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
