import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ekko_app/data/mobile_media.dart';
import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/main.dart';
import 'package:ekko_app/ui/widgets/chat_composer.dart';
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
      EkkoApp(controller: h.controller, initialize: false),
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
      expect(find.text('继续编辑草稿'), findsOneWidget);
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
}
