import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:chatstudio/ui/widgets/chat_text_style.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'package:chatstudio/ui/widgets/model_sheet.dart';

List<ModelChoice> catalog() => List.generate(
  100,
  (i) => ModelChoice(
    id: 'model-${i.toString().padLeft(3, '0')}',
    provider: i < 80 ? 'provider-a' : 'provider-b',
    providerLabel: i < 80 ? 'Provider A' : 'Provider B',
    label: 'Model ${i.toString().padLeft(3, '0')}',
  ),
);

Future<List<int>> pixels(WidgetTester tester, GlobalKey key, Rect area) async {
  late List<int> result;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = (await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    result = [
      for (var y = area.top.ceil(); y < area.bottom.floor(); y++)
        ...data.sublist(
          (y * image.width + area.left.ceil()) * 4,
          (y * image.width + area.right.floor()) * 4,
        ),
    ];
    image.dispose();
  });
  return result;
}

Future<GlobalKey> openSheet(WidgetTester tester, Brightness brightness) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey(), models = catalog();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: chatstudioTheme(brightness),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showModalBottomSheet<ModelChoice>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) =>
                    ModelSheet(models: models, selected: models[79]),
              ),
              child: const Text('open models'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open models'));
  await tester.pumpAndSettle();
  return key;
}

Finder list() => find.descendant(
  of: find.byType(ModelSheet),
  matching: find.byType(ListView),
);
ScrollableState scroll(WidgetTester tester) => tester.state<ScrollableState>(
  find.descendant(of: list(), matching: find.byType(Scrollable)).first,
);
Rect fixedHeader(WidgetTester tester) {
  final title = tester.getRect(find.text('选择模型'));
  final viewport = tester.getRect(list());
  return Rect.fromLTRB(10, title.top - 2, 380, viewport.top - 2);
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'selected model paint never leaks into header while scrolling: $brightness',
      (tester) async {
        final key = await openSheet(tester, brightness);
        final area = fixedHeader(tester);
        final before = await pixels(tester, key, area);
        final position = scroll(tester).position;
        // Keep the selected row inside the lazy cache but above the viewport.
        // The old shared Material paints its highlight into title/search here.
        for (final offset in [120.0, 160.0, 220.0, 350.0, 1800.0, 160.0, 0.0]) {
          position.jumpTo(offset);
          await tester.pumpAndSettle();
          expect(
            await pixels(tester, key, area),
            orderedEquals(before),
            reason: 'fixed title/search pixels changed at scroll=$offset',
          );
        }
        expect(
          find
              .byKey(const ValueKey('model:provider-a::model-079'))
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'selected row has clipped local material, semantics, and no ghost after search/collapse',
    (tester) async {
      await openSheet(tester, Brightness.light);
      final selected = find.byKey(
        const ValueKey('model:provider-a::model-079'),
      );
      expect(tester.widget<ListTile>(selected).selected, true);
      final material = tester.widget<Material>(
        find.byKey(const ValueKey('model-surface:provider-a::model-079')),
      );
      expect(material.clipBehavior, Clip.antiAlias);
      expect(
        tester.widget<ListTile>(selected).selectedTileColor,
        Colors.transparent,
      );
      await tester.tap(find.byKey(const ValueKey('provider:provider-a')));
      await tester.pumpAndSettle();
      expect(selected, findsNothing);
      await tester.tap(find.byKey(const ValueKey('provider:provider-a')));
      await tester.pumpAndSettle();
      expect(selected, findsOneWidget);
      await tester.enterText(find.byType(TextField), 'model-095');
      await tester.pumpAndSettle();
      expect(selected, findsNothing);
      expect(find.textContaining('当前使用'), findsNothing);
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('model:provider-b::model-095')),
            )
            .selected,
        false,
      );
      await tester.enterText(find.byType(TextField), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(selected.hitTestable(), findsOneWidget);
      expect(tester.widget<ListTile>(selected).selected, true);
    },
  );
  testWidgets('held row ink is bounded during a scroll', (tester) async {
    final key = await openSheet(tester, Brightness.light);
    final area = fixedHeader(tester),
        before = await pixels(tester, key, fixedHeader(tester));
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('model:provider-a::model-079')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 160));
    scroll(tester).position.jumpTo(160);
    await tester.pump(const Duration(milliseconds: 120));
    expect(await pixels(tester, key, area), orderedEquals(before));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'chat content has 15px outer gutter and shared larger font: scale=$scale',
      (tester) async {
        final width = scale == 1 ? 390.0 : 320.0;
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final content = List.filled(
          6,
          'A shared body with a readable line.',
        ).join(' ');
        await tester.pumpWidget(
          MaterialApp(
            theme: chatstudioTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    MessageBubble(
                      message: ChatMessage(
                        id: 'u',
                        role: 'user',
                        content: content,
                      ),
                    ),
                    MessageBubble(
                      message: ChatMessage(
                        id: 'a',
                        role: 'assistant',
                        content: content,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final id in ['u', 'a']) {
          final surface = find.byKey(ValueKey('message-surface:$id'));
          final rect = tester.getRect(surface);
          expect(rect.left, 15);
          expect(rect.right, width - 15);
          expect(
            tester.widget<Container>(surface).padding,
            const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          );
        }
        final user = tester.widget<SelectableText>(
          find
              .byWidgetPredicate(
                (w) => w is SelectableText && w.data == content,
              )
              .first,
        );
        final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
        expect(chatBodyStyle.fontSize, 15.5);
        expect(user.style!.fontSize, 15.5);
        expect(markdown.styleSheet!.p!.fontSize, 15.5);
        expect(markdown.styleSheet!.p!.height, user.style!.height);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
