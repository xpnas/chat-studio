import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:chatstudio/data/mobile_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/chat_transport.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/state/app_controller.dart';
import 'package:chatstudio/state/conversation_state.dart';
import 'support.dart';
import 'package:chatstudio/data/audio_transcription.dart';

// Opt-in destructive contract test: only use an isolated disposable Studio.
// Never point this at your production workspace.
void main() {
  final server = Platform.environment['CHATSTUDIO_TEST_SERVER'];
  test(
    'real remote workspace selection persists absolute path and lists files',
    () async {
      final c = AppController(
        storage: _MultiDeviceStorage('workspace-contract'),
      );
      final sid = 'workspace-contract-${DateTime.now().microsecondsSinceEpoch}';
      var created = false;
      try {
        await c.initialize();
        expect(
          await c.login(
            server!,
            'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        final api = c.api!;
        // Runner scripts restrict browsing/creation to a disposable workspace.
        final root = await api.workspaceFolders();
        expect(text(root['base']), isNotEmpty);
        final name = 'mobile-${DateTime.now().microsecondsSinceEpoch}';
        await api.request(
          '/api/studio/workspace/folders',
          method: 'POST',
          body: {'parentPath': '', 'name': name},
        );
        final folders = asList(
          (await api.workspaceFolders())['folders'],
        ).map(asMap);
        final chosen = folders.singleWhere((f) => f['name'] == name);
        final fullPath = text(chosen['fullPath']);
        expect(fullPath, isNotEmpty);
        expect(
          text(chosen['path']),
          name,
        ); // WORKSPACE_BASE uses relative navigation even on Windows.
        await api.setWorkspace(sid, fullPath);
        created = true;
        final detail = asMap(
          (await api.request('/api/studio/sessions/$sid'))['session'],
        );
        expect(detail['workspace'], fullPath);
        await api.request(
          '/api/studio/sessions/$sid/workspace-file/write',
          method: 'PUT',
          body: {'path': 'note.txt', 'content': 'server workspace contract'},
        );
        c.sessionId = sid;
        await c.refreshWorkspaceFiles();
        expect(c.workspaceError, isNull);
        expect(c.workspacePath, fullPath);
        expect(c.workspaceFiles.any((f) => f['name'] == 'note.txt'), true);
        // Persistence is observable through another REST read, not a local UI echo.
        expect(
          asList(
            (await api.workspaceFiles(sid))['entries'],
          ).map(asMap).any((f) => f['name'] == 'note.txt'),
          true,
        );
      } finally {
        if (created) await c.api?.delete(sid);
        c.dispose();
      }
    },
    skip: server == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'real authenticated availability matches mobile selectable Agent catalog',
    () async {
      final c = AppController(
        storage: _MultiDeviceStorage('agent-catalog-contract'),
      );
      try {
        await c.initialize();
        expect(
          await c.login(
            server!,
            'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        final snapshot = await c.api!.request('/api/agents/availability');
        final expected = asList(snapshot['agents'])
            .map(asMap)
            .where(
              (a) => a['installed'] == true && a['source'] != 'not-installed',
            )
            .map((a) => a['id'])
            .toSet();
        expect(c.availableAgents.map((a) => a.id).toSet(), expected);
        expect(c.agentsLoaded, true);
        expect(c.agentsError, isNull);
        expect(c.availableAgents, isNotEmpty);
        await c.refreshAgents();
        expect(c.availableAgents.map((a) => a.id).toSet(), expected);
      } finally {
        c.dispose();
      }
    },
    skip: server == null,
    timeout: const Timeout(Duration(minutes: 1)),
  );
  test(
    'real task plan survives network loss, completion and fresh history',
    () async {
      final transport = _DisconnectableTransport();
      final c = AppController(
        storage: _MultiDeviceStorage('task-plan-contract'),
        transport: transport,
      );
      AppController? reader;
      String? sid;
      Future<void> until(bool Function() condition) async {
        final end = DateTime.now().add(const Duration(seconds: 40));
        while (!condition()) {
          if (DateTime.now().isAfter(end)) {
            throw StateError(
              'task plan timeout: ${c.error}, plans=${c.timeline.taskPlans.length}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      try {
        await c.initialize();
        expect(
          await c.login(
            server!,
            'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        await until(() => c.canSend);
        expect(c.send('TASK_PLAN_CONTRACT'), true);
        sid = c.sessionId;
        await until(() => c.timeline.taskPlans.isNotEmpty);
        final first = c.timeline.taskPlans.single;
        expect(first.completed, 1);
        expect(first.currentStep, isNotNull);
        c.onBackground();
        final resumes = transport.resumes;
        transport.cutNetwork();
        await Future<void>.delayed(const Duration(seconds: 4));
        expect(c.timeline.taskPlans.single.revision, first.revision);
        c.onForeground();
        await until(
          () =>
              transport.resumes > resumes &&
              !c.syncing &&
              !c.working &&
              !c.loadingMessages,
        );
        final done = c.timeline.taskPlans.single;
        expect(done.revision, greaterThan(first.revision));
        expect(done.executionState, 'ended');
        expect(done.isComplete, true);
        expect(
          c.timeline.displayMessages.where((m) => m.taskPlan != null).length,
          1,
        );
        final body = c.timeline.messages
            .where((m) => m.role == 'assistant')
            .map((m) => m.content)
            .join();
        expect(body, '你好！这是本地协议自测回复。流式连接正常。');
        final page = await c.api!.messages(sid!);
        expect(page.taskPlans.single.revision, done.revision);
        expect(page.taskPlans.single.isComplete, true);
        reader = AppController(
          storage: _MultiDeviceStorage('task-plan-history'),
        );
        await reader.initialize();
        expect(
          await reader.login(
            server,
            'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        await reader.openConversation(
          Conversation(id: sid, title: 'Plan history'),
        );
        await until(
          () =>
              !reader!.syncing &&
              !reader.loadingMessages &&
              reader.timeline.taskPlans.isNotEmpty,
        );
        expect(reader.timeline.taskPlans.single.revision, done.revision);
        expect(reader.timeline.taskPlans.single.isComplete, true);
        for (var i = 0; i < 2; i++) {
          final n = transport.resumes;
          c.onBackground();
          transport.cutNetwork();
          c.onForeground();
          await until(() => transport.resumes > n && !c.syncing);
          expect(c.timeline.taskPlans.length, 1);
          expect(
            c.timeline.messages
                .where((m) => m.role == 'assistant')
                .map((m) => m.content)
                .join(),
            body,
          );
        }
        expect(transport.runs, 1);
      } finally {
        reader?.dispose();
        if (sid != null) await c.api?.delete(sid);
        c.dispose();
      }
    },
    skip: server == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'real foreground resume after server 200-event buffer truncation keeps full text',
    () async {
      final transport = _DisconnectableTransport();
      final c = AppController(
        storage: _MultiDeviceStorage('foreground-long'),
        transport: transport,
      );
      String? sid;
      final expected = List.generate(
        100,
        (i) => '[${i.toString().padLeft(3, '0')}]',
      ).join();
      String body() => c.timeline.messages
          .where((m) => m.role == 'assistant')
          .map((m) => m.content)
          .join();
      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('foreground resume timeout: ${c.error}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      }

      final invalidBodies = <String>[];
      transport.afterEvent = (event, _) {
        if (['resumed', 'message.delta'].contains(event) &&
            !expected.startsWith(body())) {
          invalidBodies.add(body());
        }
      };
      try {
        await c.initialize();
        expect(
          await c.login(
            server!,
            'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        await until(() => c.canSend);
        expect(c.send('LONG_FOREGROUND'), true);
        sid = c.sessionId;
        await until(() => body().length > 250);
        final key = c.timeline.messages.last.renderKey;
        for (var i = 0; i < 3; i++) {
          c.onBackground();
          final before = body();
          final connections = transport.connections;
          final resumes = transport.resumes;
          transport.cutNetwork();
          expect(c.connected, false);
          await Future<void>.delayed(const Duration(milliseconds: 250));
          expect(body(), before, reason: 'no events while socket is disposed');
          c.onForeground();
          await until(
            () =>
                transport.connections > connections &&
                transport.resumes > resumes &&
                !c.syncing,
          );
          expect(body().length, greaterThanOrEqualTo(before.length));
          expect(
            expected.startsWith(body()),
            true,
            reason:
                'restored body must be one exact prefix, not a repeated tail',
          );
          expect(c.timeline.messages.last.renderKey, key);
        }
        await until(() => !c.working && !c.loadingMessages);
        expect(body(), expected);
        c.onBackground();
        c.onForeground();
        await until(() => !c.syncing);
        expect(body(), expected);
        expect(transport.runs, 1, reason: 'reconnect must never resend input');
        expect(invalidBodies, isEmpty, reason: 'check every live/sync update');
      } finally {
        if (sid != null) {
          c.stop();
          await c.api?.delete(sid);
        }
        c.dispose();
      }
    },
    skip: server == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'real queue cancellation, sequential start and server TTS audio',
    () async {
      final c = AppController(
        storage: _MultiDeviceStorage('queue-tts-contract'),
      );
      String? sid;
      bool tts = false;
      Future<void> until(bool Function() condition) async {
        final end = DateTime.now().add(const Duration(seconds: 45));
        while (!condition()) {
          if (DateTime.now().isAfter(end)) {
            throw StateError('queue/tts timeout: ${c.error}');
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
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        await until(() => c.canSend);
        c.send('SLOW queue first');
        sid = c.sessionId;
        await until(() => c.canQueue);
        expect(c.send('cancel this queue'), true);
        await until(() => c.timeline.queue.any((q) => q.status == 'queued'));
        final qid = c.timeline.queue.single.id;
        c.cancelQueued(qid, expectedSession: sid!);
        await until(() => c.timeline.queue.isEmpty);
        expect(c.send('queue second'), true);
        await until(() => c.timeline.queue.any((q) => q.status == 'queued'));
        c.stop();
        await until(
          () => c.timeline.messages.any(
            (m) => m.role == 'user' && m.content == 'queue second',
          ),
        );
        await until(() => !c.working && !c.loadingMessages);
        expect(c.timeline.queue, isEmpty);
        final history = await c.api!.messages(sid);
        expect(
          history.messages
              .where((m) => m.role == 'user' && m.content == 'queue second')
              .length,
          1,
        );
        expect(
          history.messages.where((m) => m.content == 'cancel this queue'),
          isEmpty,
        );
        await c.api!.request(
          '/api/studio/tts/settings/custom',
          method: 'PUT',
          body: {
            'settings': {
              'baseUrl': 'http://127.0.0.1:18648/v1',
              'model': 'fixture-tts',
              'voice': 'alloy',
            },
            'secrets': {'apiKey': 'local-fixture-not-a-real-key'},
          },
        );
        tts = true;
        await c.api!.request(
          '/api/studio/tts/settings/active',
          method: 'PUT',
          body: {'provider': 'custom'},
        );
        final audio = await c.api!.synthesizeSpeech('测试语音回复');
        expect(audio.$2, 'audio/wav');
        expect(ascii.decode(audio.$1.take(4).toList()), 'RIFF');
      } finally {
        if (tts) {
          await c.api?.request(
            '/api/studio/tts/settings/active',
            method: 'PUT',
            body: {'provider': 'edge'},
          );
          await c.api?.request(
            '/api/studio/tts/settings/custom',
            method: 'DELETE',
          );
        }
        if (sid != null) {
          c.stop();
          await c.api?.delete(sid);
        }
        c.dispose();
      }
    },
    skip: server == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'real Hermes command receipts, title, display clear and history clear',
    () async {
      final c = AppController(
        storage: _MultiDeviceStorage('chatstudio-command-contract'),
      );
      String? sid;
      Future<void> until(bool Function() condition) async {
        final end = DateTime.now().add(const Duration(seconds: 40));
        while (!condition()) {
          if (DateTime.now().isAfter(end)) {
            throw StateError('Command receipt timeout: ${c.error ?? ""}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }

      try {
        await c.initialize();
        expect(
          await c.login(
            server!,
            Platform.environment['CHATSTUDIO_TEST_USERNAME'] ?? 'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
            true,
          ),
          isTrue,
        );
        await until(() => c.canSend);
        // The isolated server deliberately has no Hermes runtime installed.
        // Seed an existing Hermes session via the real REST API: server-side
        // slash commands still work, but the new-chat picker must NOT offer it.
        final commandSession =
            'command-contract-${DateTime.now().microsecondsSinceEpoch}';
        await c.api!.request(
          '/api/studio/sessions/$commandSession/workspace',
          method: 'POST',
          body: {'workspace': ''},
        );
        sid = commandSession;
        await c.openConversation(
          Conversation(
            id: commandSession,
            title: '',
            profile: c.profile,
            agent: 'hermes',
          ),
        );
        await until(() => c.canSend);
        expect(c.engine, 'hermes');
        expect(c.send('/usage'), isTrue);
        await until(
          () => c.timeline.messages.any(
            (m) => m.role == 'command' && m.content.startsWith('Usage:'),
          ),
        );
        expect(c.working, isFalse);
        expect(c.send('/context'), isTrue);
        await until(
          () =>
              c.timeline.messages.any((m) => m.content.startsWith('Context:')),
        );
        expect(c.send('/title mobile-command-contract'), isTrue);
        await until(() => c.title == 'mobile-command-contract');
        final listed = await c.api!.sessions(search: 'mobile-command-contract');
        expect(
          asList(listed['results']).map(asMap).any((r) => r['id'] == sid),
          isTrue,
        );
        final before = await c.api!.messages(commandSession);
        expect(before.messages.where((m) => m.role == 'command'), isNotEmpty);
        expect(c.send('/clear'), isTrue);
        await until(() => c.timeline.messages.isEmpty);
        final after = await c.api!.messages(commandSession);
        expect(after.total, greaterThanOrEqualTo(before.total));
        expect(c.send('/clear --history'), isTrue);
        await until(
          () => c.timeline.messages.any(
            (m) => m.content.contains('history messages from the database'),
          ),
        );
        final cleared = await c.api!.messages(commandSession);
        expect(
          cleared.messages.any((m) => m.content.startsWith('Usage:')),
          isFalse,
        );
        expect(c.canSend, isTrue);
        // Catalog endpoints are real, not widget fixtures.
        await c.api!.commandSkills();
        await c.api!.commandBundles();
      } finally {
        if (sid != null) await c.api?.delete(sid);
        c.dispose();
      }
    },
    skip: server == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'real simultaneous sessions, activity snapshot and reasoning persistence',
    () async {
      final c = AppController(
        storage: _MultiDeviceStorage('chatstudio-multi-main'),
      );
      final observer = AppController(
        storage: _MultiDeviceStorage('chatstudio-multi-observer'),
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
            Platform.environment['CHATSTUDIO_TEST_USERNAME'] ?? 'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
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
            Platform.environment['CHATSTUDIO_TEST_USERNAME'] ?? 'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
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
      final dir = await Directory.systemTemp.createTemp(
        'chatstudio-live-media-',
      );
      String? sid;
      var configured = false;
      try {
        await c.initialize();
        expect(
          await c.login(
            server!,
            Platform.environment['CHATSTUDIO_TEST_USERNAME'] ?? 'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
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
        final audioBlocks = await api.uploadAttachments([
          LocalAttachment(
            path: audio.path,
            name: 'voice.wav',
            size: 32044,
            mimeType: 'audio/wav',
          ),
        ]);
        final transcriber = AudioTranscription(tempDirectory: () async => dir);
        try {
          await transcriber.transcribe(
            api,
            'remote-audio',
            MessageAttachment.parse(audioBlocks).single,
          );
          expect(transcriber.resultFor('remote-audio'), '这是本地语音识别协议自测。');
          expect(transcriber.errorFor('remote-audio'), isNull);
        } finally {
          transcriber.dispose();
        }

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
    skip:
        server == null || Platform.environment['CHATSTUDIO_TEST_MEDIA'] != '1',
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
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
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
          Platform.environment['CHATSTUDIO_TEST_USERNAME'] ?? 'admin',
          Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
          'chatstudio-dart-contract-test',
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
        ? 'Set CHATSTUDIO_TEST_SERVER and CHATSTUDIO_TEST_PASSWORD for isolated live test'
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

// A real Socket.IO transport with a deterministic network-loss boundary.
// Closing the socket stops delivery; reconnect uses a new physical connection.
class _DisconnectableTransport implements ChatTransport {
  final _inner = SocketChatTransport();
  SocketEvent? _listener;
  SocketEvent? afterEvent;
  int connections = 0;
  int resumes = 0;
  int runs = 0;

  @override
  bool get isStarted => _listener != null;

  @override
  void connect(StudioApi api, SocketEvent onEvent) {
    _listener = onEvent;
    _inner.connect(api, (event, data) {
      if (event == 'connected') connections++;
      if (event == 'resumed') resumes++;
      onEvent(event, data);
      afterEvent?.call(event, data);
    });
  }

  void cutNetwork() {
    _inner.dispose();
    _listener?.call('disconnected', {});
  }

  @override
  void emit(String event, Map<String, dynamic> data) {
    if (event == 'run') runs++;
    _inner.emit(event, data);
  }

  @override
  void dispose() => _inner.dispose();
}
