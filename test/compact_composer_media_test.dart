import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/data/message_file_reference.dart';
import 'package:ekko_app/main.dart';
import 'package:ekko_app/ui/widgets/attachment_tile.dart';
import 'package:ekko_app/ui/widgets/message_bubble.dart';
import 'support.dart';

void main() {
  testWidgets(
    'single toolbar, slash popup above composer without layout shift at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      final controls = [
        'attachment-button',
        'model-button',
        'reasoning-button',
        'voice-button',
        'send-button',
      ];
      final ys = controls
          .map((k) => tester.getCenter(find.byKey(Key(k))).dy)
          .toList();
      for (final y in ys) {
        expect(y, closeTo(ys.first, 1));
      }
      expect(find.byKey(const Key('slash-button')), findsNothing);
      await tester.tap(find.byKey(const Key('message-input')));
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byKey(const Key('composer-surface')));
      await tester.enterText(find.byKey(const Key('message-input')), '/');
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byKey(const Key('composer-surface')));
      final popup = tester.getRect(find.byKey(const Key('slash-commands')));
      expect(after, before);
      expect(popup.bottom, lessThan(after.top));
      expect(popup.left, closeTo(after.left, 1));
      expect(popup.width, closeTo(after.width, 1));
      await tester.tap(find.byKey(const ValueKey('command:context')));
      await tester.pumpAndSettle();
      expect(h.controller.draft.text, '/context ');
      expect(find.byKey(const Key('slash-commands')), findsNothing);
      for (final text in ['a/', ' /', 'hello /context']) {
        await tester.enterText(find.byKey(const Key('message-input')), text);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('slash-commands')), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'only local and same origin download paths become authenticated references',
    () {
      final server = Uri.parse('https://studio.example');
      expect(
        messageFileReference('/tmp/image%20one.png')!.mimeType,
        'image/png',
      );
      expect(
        messageFileReference('<C:/Users/Test/report.pdf>')!.path,
        'C:/Users/Test/report.pdf',
      );
      expect(
        messageFileReference(
          'https://studio.example/api/studio/files/download?path=%2Ftmp%2Fa.png',
          server: server,
        )!.path,
        '/tmp/a.png',
      );
      for (final input in [
        'https://other.example/api/studio/files/download?path=/secret',
        '//other.example/a.png',
        'file:///tmp/a.png',
        'javascript:alert(1)',
        '/tmp/bad%XX.png',
        '/tmp/%00.png',
      ]) {
        expect(messageFileReference(input, server: server), isNull);
      }
    },
  );

  testWidgets(
    'assistant markdown image loads authenticated preview and file link opens download',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      h.override = (r) async => r.url.path == '/api/studio/files/download'
          ? http.Response.bytes(png, 200)
          : h.response(r);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              controller: h.controller,
              message: const ChatMessage(
                id: 'image',
                role: 'assistant',
                content: '![结果](/tmp/result.png)\n\n[下载报告](/tmp/report.pdf)',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final request = h.requests.lastWhere(
        (r) => r.url.path == '/api/studio/files/download',
      );
      expect(request.url.queryParameters['path'], '/tmp/result.png');
      expect(request.url.queryParameters['variant'], 'app-image');
      expect(request.headers['Authorization'], 'Bearer device-token');
      await tester.tap(find.text('下载报告', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentViewer), findsOneWidget);
      expect(find.text('下载 / 保存附件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('explicit file download saves exact bytes only once', (
    tester,
  ) async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    h.override = (r) async => r.url.path == '/api/studio/files/download'
        ? http.Response.bytes([1, 2, 3, 4], 200)
        : h.response(r);
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentTile(
            controller: h.controller,
            file: const MessageAttachment(
              name: 'report.pdf',
              path: '/tmp/report.pdf',
              mimeType: 'application/pdf',
            ),
            saveFile: (String name, Uint8List bytes, String mime) async {
              saves++;
              expect(name, 'report.pdf');
              expect(bytes, [1, 2, 3, 4]);
              expect(mime, 'application/pdf');
              return '/saved/report.pdf';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      h.requests.where((r) => r.url.path == '/api/studio/files/download'),
      isEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('download:/tmp/report.pdf')));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('附件已保存至你选择的位置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
