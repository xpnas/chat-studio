import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/audio_transcription.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/ui/widgets/attachment_tile.dart';
import 'support.dart';

const audio = MessageAttachment(
  name: '回答.mp3',
  path: '/tmp/reply.mp3',
  mimeType: 'audio/mpeg',
);
void main() {
  testWidgets('normal AI text has no TTS button or auto speech switch', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    h.controller.timeline.messages = [
      const ChatMessage(id: 'm', role: 'assistant', content: '这是普通文字回复。'),
    ];
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('语音回复'), findsNothing);
    expect(find.byTooltip('开启 AI 语音回复'), findsNothing);
    expect(find.text('转文字'), findsNothing);
    expect(h.requests.any((r) => r.url.path.contains('/tts/')), false);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'existing audio sends correct MIME/name to STT, no TTS, caches result and cleans temporary file',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'chatstudio-transcription-test-',
      );
      final service = AudioTranscription(tempDirectory: () async => dir);
      final h = TestHarness(transcription: service);
      await h.login();
      var stt = 0;
      h.override = (r) async {
        switch (r.url.path) {
          case '/api/studio/stt/profile-status':
            return http.Response(
              '{"configured":true,"activeProvider":"custom"}',
              200,
            );
          case '/api/studio/files/download':
            return http.Response.bytes([1, 2, 3], 200);
          case '/api/studio/stt/transcribe':
            stt++;
            expect(r.headers['Authorization'], 'Bearer device-token');
            expect(r.headers['X-Hermes-Profile'], 'default');
            expect(r.body, contains('audio/mpeg'));
            expect(r.body, contains('filename="回答.mp3"'));
            expect(r.body, contains('custom'));
            return http.Response(
              '{"text":"这是识别出的语音文字。"}',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          default:
            throw StateError('unexpected request ${r.url.path}');
        }
      };
      final id = h.controller.audioAttachmentId(audio);
      await service.transcribe(h.controller.api!, id, audio);
      expect(service.resultFor(id), '这是识别出的语音文字。');
      expect(service.errorFor(id), isNull);
      expect(await dir.list().toList(), isEmpty);
      await service.transcribe(h.controller.api!, id, audio);
      expect(stt, 1);
      expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
      h.dispose();
      await dir.delete(recursive: true);
    },
  );
  test(
    'STT unconfigured fails before downloading, cancel drops delayed result',
    () async {
      final h = TestHarness();
      await h.login();
      h.override = (r) async => http.Response('{"configured":false}', 200);
      final id = h.controller.audioAttachmentId(audio);
      await h.controller.transcription.transcribe(h.controller.api!, id, audio);
      expect(h.controller.transcription.errorFor(id), contains('STT'));
      final pending = Completer<http.Response>();
      h.override = (r) => pending.future;
      final work = h.controller.transcription.transcribe(
        h.controller.api!,
        id,
        audio,
      );
      h.controller.newChat();
      pending.complete(
        http.Response('{"configured":true,"activeProvider":"custom"}', 200),
      );
      await work;
      expect(h.controller.transcription.activeId, isNull);
      expect(h.controller.transcription.resultFor(id), isNull);
      h.dispose();
    },
  );
  testWidgets('audio card offers clean playback without transcription', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    h.override = (r) async => http.Response('{"configured":false}', 200);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachmentTile(file: audio, controller: h.controller),
        ),
      ),
    );
    expect(find.text('播放语音'), findsOneWidget);
    expect(find.text('转文字'), findsNothing);
    expect(find.byType(SelectableText), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    h.dispose();
  });
}
