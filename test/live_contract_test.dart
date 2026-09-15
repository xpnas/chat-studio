import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:ekko_app/data/mobile_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:ekko_app/core/server_address.dart';
import 'package:ekko_app/data/chat_transport.dart';
import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/data/studio_api.dart';
import 'package:ekko_app/state/app_controller.dart';
import 'package:ekko_app/state/conversation_state.dart';
import 'support.dart';

// Opt-in destructive contract test: only use an isolated disposable Studio.
// Never point this at your production workspace.
void main() {
  final server = Platform.environment['EKKO_TEST_SERVER'];
  test(
    'real simultaneous sessions, activity snapshot and reasoning persistence',
    () async {
      final c = AppController(storage: _MultiDeviceStorage('ekko-multi-main'));
      final observer = AppController(
        storage: _MultiDeviceStorage('ekko-multi-observer'),
      );
      final ids = <String>[];
      Future<void> until(bool Function() condition) async {
        final end = DateTime.now().add(const Duration(seconds: 40));
        while (!condition()) {
          if (DateTime.now().isAfter(end)) {
            throw StateError(
              'Multi-session condition timed out: ${c.error ?? ''}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }

      try {
        await c.initialize();
        expect(
          await c.login(
            server!,
            Platform.environment['EKKO_TEST_USERNAME'] ?? 'admin',
            Platform.environment['EKKO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        await until(() => c.canConfigure);
        await c.chooseReasoningEffort('high');
        await until(() => c.canSend);
        expect(c.send('SLOW multi-session A'), true);
        final a = c.current!;
        ids.add(a.id);
        final aTimeline = c.timeline;
        await until(
          () => aTimeline.messages.any(
            (m) => m.role == 'assistant' && m.content.isNotEmpty,
          ),
        );
        await observer.initialize();
        expect(
          await observer.login(
            server,
            Platform.environment['EKKO_TEST_USERNAME'] ?? 'admin',
            Platform.environment['EKKO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        await until(
          () =>
              observer.conversations.any((row) => row.id == a.id) &&
              observer.taskStatus(a) == ConversationTaskStatus.running,
        );
        c.newChat();
        await c.chooseReasoningEffort('low');
        expect(c.send('multi-session B'), true);
        final b = c.current!;
        ids.add(b.id);
        final bTimeline = c.timeline;
        expect(aTimeline.working, true);
        expect(bTimeline.working, true);
        await c.openConversation(a);
        await until(() => !c.syncing && c.timeline.working);
        expect(c.timeline, same(aTimeline));
        expect(c.reasoningEffort, 'high');
        await until(() => !bTimeline.working);
        expect(c.sessionId, a.id);
        expect(aTimeline.working, true);
        expect(
          bTimeline.messages.where((m) => m.role == 'assistant').last.content,
          '你好！这是本地协议自测回复。流式连接正常。',
        );
        c.stop();
        await until(() => !aTimeline.working && c.canConfigure);
        await c.chooseReasoningEffort('xhigh');
        c.reconnect();
        await until(() => c.connected && !c.syncing);
        expect(c.reasoningEffort, 'xhigh');
        await until(
          () => observer.taskStatus(a) == ConversationTaskStatus.completed,
        );
        final bHistory = await c.api!.messages(b.id);
        expect(bHistory.messages.where((m) => m.role == 'user').length, 1);
        expect(
          bHistory.messages.where((m) => m.role == 'assistant').last.content,
          '你好！这是本地协议自测回复。流式连接正常。',
        );
      } finally {
        for (final id in ids) {
          if (c.connected) c.transport.emit('abort', {'session_id': id});
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        for (final id in ids) {
          await c.api?.delete(id);
        }
        observer.dispose();
        c.dispose();
      }
    },
    skip: server == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'real upload references round-trip and server STT transcription',
    () async {
      final c = AppController(storage: MemoryStorage());
      final dir = await Directory.systemTemp.createTemp('ekko-live-media-');
      String? sid;
      var configured = false;
      try {
        await c.initialize();
        expect(
          await c.login(
            server!,
            Platform.environment['EKKO_TEST_USERNAME'] ?? 'admin',
            Platform.environment['EKKO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        final api = c.api!;
        final settings = await api.request('/api/studio/stt/settings');
        if (asList(settings['settings']).isNotEmpty ||
            settings['activeProvider'] != null) {
          throw StateError(
            'Media fixture requires disposable Studio without existing STT settings',
          );
        }
        await api.request(
          '/api/studio/stt/settings/custom',
          method: 'PUT',
          body: {
            'settings': {
              'baseUrl': 'http://127.0.0.1:18648/v1',
              'model': 'fixture-whisper',
            },
            'secrets': {'apiKey': 'local-fixture-not-a-real-key'},
          },
        );
        configured = true;
        await c.refreshCapabilities();
        expect(c.sttProvider, 'custom');
        final wav = ByteData(32044);
        void ascii(int at, String value) {
          for (var i = 0; i < value.length; i++) {
            wav.setUint8(at + i, value.codeUnitAt(i));
          }
        }

        ascii(0, 'RIFF');
        wav.setUint32(4, 32036, Endian.little);
        ascii(8, 'WAVEfmt ');
        wav.setUint32(16, 16, Endian.little);
        wav.setUint16(20, 1, Endian.little);
        wav.setUint16(22, 1, Endian.little);
        wav.setUint32(24, 16000, Endian.little);
        wav.setUint32(28, 32000, Endian.little);
        wav.setUint16(32, 2, Endian.little);
        wav.setUint16(34, 16, Endian.little);
        ascii(36, 'data');
        wav.setUint32(40, 32000, Endian.little);
        final audio = File('${dir.path}/voice.wav');
        await audio.writeAsBytes(wav.buffer.asUint8List());
        expect(await api.transcribe(audio.path, 'custom'), '这是本地语音识别协议自测。');
        final document = File('${dir.path}/fixture.txt');
        await document.writeAsString('A test attachment, not private data.');
        final image = File('${dir.path}/fixture.png');
        await image.writeAsBytes(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7e0AAAAASUVORK5CYII=',
          ),
        );
        final blocks = await api.uploadAttachments([
          await LocalAttachment.fromPath(document.path, '需求.txt'),
          await LocalAttachment.fromPath(image.path, '示例.png'),
        ]);
        expect(blocks.map((b) => b['type']), ['file', 'image']);
        final uploaded = MessageAttachment.parse(blocks);
        expect(
          utf8.decode(await api.attachmentBytes(uploaded.first)),
          'A test attachment, not private data.',
        );
        expect(
          await api.attachmentBytes(uploaded.last, thumbnail: true),
          isNotEmpty,
        );

        final deadline = DateTime.now().add(const Duration(seconds: 50));
        while (!c.canSend && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(c.send('请检查附件', attachments: blocks), true);
        sid = c.sessionId;
        while (c.working && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(c.working, false);
        expect(c.error, isNull);
        final page = await api.messages(sid!);
        final user = page.messages.firstWhere((m) => m.role == 'user');
        expect(user.content, contains('需求.txt'));
        expect(user.content, contains('示例.png'));
      } finally {
        if (configured) {
          await c.api?.request(
            '/api/studio/stt/settings/custom',
            method: 'DELETE',
          );
        }
        if (sid != null) await c.api?.delete(sid);
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
    skip: server == null || Platform.environment['EKKO_TEST_MEDIA'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'real controller restores an active stream without duplicate bubbles',
    () async {
      final c = AppController(storage: MemoryStorage());
      String? sid;
      Future<void> until(bool Function() predicate) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!predicate()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Controller timeout: ${c.error ?? 'none'}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      try {
        await c.initialize();
        expect(
          await c.login(
            server!,
            'admin',
            Platform.environment['EKKO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        await until(() => c.canSend);
        await c.chooseModel(
          c.models.firstWhere((m) => m.provider == 'custom:mobile-test'),
        );
        expect(c.send('SLOW controller reconnect test'), true);
        sid = c.sessionId!;
        await until(
          () => c.timeline.messages.any(
            (m) => m.role == 'assistant' && m.content.isNotEmpty,
          ),
        );
        c.reconnect();
        await until(() => c.connected && !c.syncing);
        expect(c.timeline.messages.where((m) => m.role == 'user').length, 1);
        expect(
          c.timeline.messages.where((m) => m.role == 'assistant').length,
          1,
        );
        c.stop();
        await until(() => !c.working && !c.loadingMessages);
        expect(c.timeline.messages.where((m) => m.role == 'user').length, 1);
      } finally {
        if (sid != null) await c.api?.delete(sid);
        await c.logout();
        c.dispose();
      }
    },
    skip: server == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'real v1.0.3 REST and Dart Socket.IO lifecycle',
    () async {
      final api = StudioApi(ServerAddress.parse(server!, allowLocalHttp: true));
      final transport = SocketChatTransport();
      final events =
          StreamController<(String, Map<String, dynamic>)>.broadcast();
      final sessions = <String>[];
      Future<Map<String, dynamic>> wait(String name) => events.stream
          .firstWhere(
            (e) =>
                e.$1 == name ||
                e.$1 == 'run.failed' ||
                e.$1 == 'connection.error',
          )
          .timeout(const Duration(seconds: 45))
          .then((e) {
            if (e.$1 != name) {
              throw StateError(
                'Expected $name; received ${e.$1}: ${e.$2['error']}',
              );
            }
            return e.$2;
          });
      try {
        final login = await api.login(
          Platform.environment['EKKO_TEST_USERNAME'] ?? 'admin',
          Platform.environment['EKKO_TEST_PASSWORD']!,
          'ekko-dart-contract-test',
        );
        api.token = text(login['token']);
        expect(api.token, isNotEmpty);
        expect((await api.me()).username, isNotEmpty);
        expect(await api.profiles(), contains('default'));
        final catalog = ModelChoice.parseGroups((await api.models())['groups']);
        final model = catalog.firstWhere(
          (m) => m.provider == 'custom:mobile-test',
        );
        final ready = wait('connected');
        transport.connect(api, (name, data) => events.add((name, data)));
        await ready;
        final sid = const Uuid().v4();
        sessions.add(sid);
        final delta = wait('message.delta');
        final completed = wait('run.completed');
        transport.emit('run', {
          'session_id': sid,
          'queue_id': const Uuid().v4(),
          'profile': 'default',
          'input': '你好，请回复本地自测。',
          'agent_id': 'ekko-agent',
          'source': 'coding_agent',
          'model': model.id,
          'provider': model.provider,
          'api_mode': model.apiMode,
        });
        expect(text((await delta)['delta']), isNotEmpty);
        expect(text((await completed)['output']), contains('本地协议自测'));
        final page = await api.messages(sid);
        expect(page.messages.where((m) => m.role == 'user'), isNotEmpty);
        expect(
          page.messages.where((m) => m.role == 'assistant').last.content,
          contains('本地协议自测'),
        );
        await api.rename(sid, 'Mobile contract smoke');
        await api.setModel(sid, model);
        expect(
          asList(
            (await api.sessions(search: 'Mobile contract smoke'))['results'],
          ),
          isNotEmpty,
        );
        final resumed = wait('resumed');
        transport.emit('resume', {'session_id': sid});
        expect(flag((await resumed)['isWorking']), false);
        // Active stream reconnect must restore without sending a second run.
        final secondDelta = wait('message.delta');
        transport.emit('run', {
          'session_id': sid,
          'queue_id': const Uuid().v4(),
          'profile': 'default',
          'input': 'SLOW reconnect and abort test',
          'agent_id': 'ekko-agent',
          'source': 'coding_agent',
          'model': model.id,
          'provider': model.provider,
          'api_mode': model.apiMode,
        });
        await secondDelta;
        transport.dispose();
        final reconnected = wait('connected');
        transport.connect(api, (name, data) => events.add((name, data)));
        await reconnected;
        final activeResume = wait('resumed');
        transport.emit('resume', {'session_id': sid});
        expect(flag((await activeResume)['isWorking']), true);
        final aborted = wait('abort.completed');
        transport.emit('abort', {'session_id': sid});
        await aborted;
      } finally {
        transport.dispose();
        for (final id in sessions) {
          await api.delete(id);
        }
        api.close();
        await events.close();
      }
    },
    skip: server == null
        ? 'Set EKKO_TEST_SERVER and EKKO_TEST_PASSWORD for isolated live test'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _MultiDeviceStorage extends MemoryStorage {
  _MultiDeviceStorage(this.id);
  final String id;
  @override
  Future<String> deviceId() async => id;
}
