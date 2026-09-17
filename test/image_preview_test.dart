import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:chatstudio/ui/widgets/attachment_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
);
const _file = MessageAttachment(
  name: 'private-image.png',
  path: '/tmp/image.png',
  mimeType: 'image/png',
);

Future<TestHarness> _open(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  bool downloadOnOpen = false,
  Future<String?> Function(String, Uint8List, String)? save,
}) async {
  final h = TestHarness();
  addTearDown(h.dispose);
  await h.login();
  h.override = (r) async => r.url.path == '/api/studio/files/download'
      ? http.Response.bytes(_png, 200)
      : h.response(r);
  await tester.pumpWidget(
    MaterialApp(
      theme: chatstudioTheme(brightness),
      home: Scaffold(
        body: Center(
          child: AttachmentTile(
            file: _file,
            controller: h.controller,
            saveFile: save ?? (_, _, _) async => null,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    downloadOnOpen
        ? find.byKey(const ValueKey('download:/tmp/image.png'))
        : find.byType(AttachmentTile),
  );
  await tester.pumpAndSettle();
  return h;
}

void main() {
  for (final brightness in Brightness.values) {
    for (final landscape in [false, true]) {
      testWidgets(
        'fullscreen canvas and safe icon controls $brightness landscape=$landscape',
        (tester) async {
          final size = landscape ? const Size(844, 390) : const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.padding = landscape
              ? const FakeViewPadding(left: 44, right: 44, bottom: 21)
              : const FakeViewPadding(top: 47, bottom: 34);
          addTearDown(tester.view.reset);
          await _open(tester, brightness: brightness);
          expect(
            tester.getRect(find.byKey(const Key('dismiss-image-preview'))),
            Offset.zero & size,
          );
          final actions = tester.getRect(
            find.byKey(const Key('image-preview-actions')),
          );
          expect(
            actions.right,
            lessThanOrEqualTo(size.width - (landscape ? 44 : 16)),
          );
          expect(
            actions.bottom,
            lessThanOrEqualTo(size.height - (landscape ? 21 : 34)),
          );
          final viewer = find.byType(AttachmentViewer);
          expect(
            find.descendant(of: viewer, matching: find.text(_file.name)),
            findsNothing,
          );
          for (final name in ['download', 'close']) {
            expect(
              tester.getSize(find.byKey(Key('image-preview-$name'))),
              const Size.square(52),
            );
          }
          expect(find.byTooltip('下载图片'), findsOneWidget);
          expect(find.byTooltip('关闭预览'), findsOneWidget);
          await tester.tap(find.byKey(const Key('image-preview-close')));
          await tester.pumpAndSettle();
          expect(viewer, findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets(
    'pinch zoom keeps controls fixed and does not dismiss; back closes',
    (tester) async {
      await _open(tester);
      final before = tester.getRect(
        find.byKey(const Key('image-preview-actions')),
      );
      final one = await tester.startGesture(const Offset(350, 300), pointer: 1);
      final two = await tester.startGesture(const Offset(450, 300), pointer: 2);
      await tester.pump();
      await one.moveTo(const Offset(300, 300));
      await two.moveTo(const Offset(500, 300));
      await tester.pump();
      await one.moveTo(const Offset(250, 300));
      await two.moveTo(const Offset(550, 300));
      await tester.pump();
      final transforms = tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(InteractiveViewer),
          matching: find.byType(Transform),
        ),
      );
      expect(
        transforms.any((t) => t.transform.getMaxScaleOnAxis() > 1),
        isTrue,
      );
      await one.up();
      await two.up();
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentViewer), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('image-preview-actions'))),
        before,
      );
      await tester.tap(find.byKey(const Key('image-preview-close')));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentViewer), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('save failure leaves preview open and icon can retry export', (
    tester,
  ) async {
    var saves = 0;
    await _open(
      tester,
      save: (_, bytes, mime) async {
        expect(bytes, _png);
        expect(mime, 'image/png');
        if (++saves == 1) throw StateError('export failed');
        return null;
      },
    );
    await tester.tap(find.byKey(const Key('image-preview-download')));
    await tester.pumpAndSettle();
    expect(find.textContaining('export failed'), findsOneWidget);
    expect(find.byType(AttachmentViewer), findsOneWidget);
    await tester.tap(find.byKey(const Key('image-preview-download')));
    await tester.pumpAndSettle();
    expect(saves, 2);
    expect(find.textContaining('export failed'), findsNothing);
    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.byType(AttachmentViewer), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('download shortcut also opens edge-to-edge image preview', (
    tester,
  ) async {
    tester.view.padding = const FakeViewPadding(top: 40, bottom: 30);
    addTearDown(tester.view.reset);
    var saves = 0;
    await _open(
      tester,
      downloadOnOpen: true,
      save: (_, _, _) async {
        saves++;
        return null;
      },
    );
    expect(saves, 1);
    expect(
      tester.getSize(find.byKey(const Key('dismiss-image-preview'))),
      const Size(800, 600),
    );
    await tester.tap(find.byKey(const Key('image-preview-close')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'closing during save ignores completion safely without duplicate export',
    (tester) async {
      final result = Completer<String?>();
      var saves = 0;
      await _open(
        tester,
        save: (_, _, _) {
          saves++;
          return result.future;
        },
      );
      await tester.tap(find.byKey(const Key('image-preview-download')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const Key('image-preview-download')));
      await tester.pump();
      expect(saves, 1);
      await tester.tap(find.byKey(const Key('image-preview-close')));
      await tester.pumpAndSettle();
      result.complete(null);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AttachmentViewer), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
