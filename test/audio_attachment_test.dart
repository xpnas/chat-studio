import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/speech_playback.dart';
import 'package:chatstudio/ui/widgets/attachment_tile.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'support.dart';

class FileSpeaker implements SpeechOutput, FileSpeechOutput {
  String? path;
  int plays = 0;
  final completion = StreamController<void>.broadcast();
  @override
  Stream<void> get completed => completion.stream;
  @override
  Future<void> play(Uint8List data, String mime) async {
    plays++;
  }

  @override
  Future<void> playFile(String file, String mime) async {
    path = file;
    plays++;
    expect(await File(file).readAsBytes(), [1, 2, 3]);
    expect(mime, 'audio/mpeg');
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await completion.close();
  }
}

const audio = MessageAttachment(
  name: 'reply.mp3',
  path: '/tmp/reply.mp3',
  mimeType: 'application/octet-stream',
);
void main() {
  test(
    'recognizes file and audio blocks without losing audio-only message',
    () {
      expect(audio.isAudio, true);
      expect(audio.audioMime, 'audio/mpeg');
      final message = ChatMessage.fromJson({
        'id': 1,
        'role': 'assistant',
        'content': [
          {'type': 'audio', 'path': '/tmp/reply.wav', 'name': 'reply.wav'},
        ],
      });
      expect(message.visible, true);
      expect(message.attachments.single.isAudio, true);
      expect(message.attachments.single.audioMime, 'audio/x-wav');
    },
  );
  test(
    'existing audio uses download not TTS, file playback and stop cleanup',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'chatstudio-audio-test-',
      );
      final out = FileSpeaker();
      final speech = SpeechPlayback(
        outputFactory: () => out,
        tempDirectory: () async => root,
      );
      final h = TestHarness(speech: speech);
      await h.login();
      h.override = (r) async {
        expect(r.url.path, '/api/studio/files/download');
        expect(r.headers['Authorization'], 'Bearer device-token');
        expect(r.url.queryParameters['path'], audio.path);
        return http.Response.bytes([1, 2, 3], 200);
      };
      await speech.playAttachment(h.controller.api!, 'audio-test', audio);
      expect(out.plays, 1);
      expect(speech.activeId, 'audio-test');
      expect(await File(out.path!).exists(), true);
      await speech.stop();
      expect(await File(out.path!).exists(), false);
      expect(await root.list().toList(), isEmpty);
      h.dispose();
      await root.delete(recursive: true);
    },
  );
  testWidgets(
    'audio card has inline play and separate download; markdown click plays',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                AttachmentTile(file: audio, controller: h.controller),
                MessageBubble(
                  controller: h.controller,
                  message: const ChatMessage(
                    id: 'm',
                    role: 'assistant',
                    content: '[听语音](/tmp/reply.mp3)',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.byKey(ValueKey('play-audio:${audio.path}')),
        findsNWidgets(2),
      );
      expect(find.byKey(ValueKey('download:${audio.path}')), findsNWidgets(2));
      expect(
        find.byKey(ValueKey('transcribe-audio:${audio.path}')),
        findsNothing,
      );
      await tester.tap(find.byKey(ValueKey('play-audio:${audio.path}')).last);
      await tester.pump();
      // No forced save dialog for an audio link, even if native playback isn't available in the test VM.
      expect(find.byType(AttachmentViewer), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      h.dispose();
    },
  );
  test('cancel before audio download prevents late playback', () async {
    final out = FileSpeaker();
    final speech = SpeechPlayback(outputFactory: () => out);
    final h = TestHarness(speech: speech);
    await h.login();
    final playing = speech.playAttachment(h.controller.api!, 'a', audio);
    await speech.stop();
    await playing;
    expect(out.plays, 0);
    expect(speech.activeId, isNull);
    h.dispose();
  });
}
