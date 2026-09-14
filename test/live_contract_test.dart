import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:ekko_app/core/server_address.dart';
import 'package:ekko_app/data/chat_transport.dart';
import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/data/studio_api.dart';
import 'package:ekko_app/state/app_controller.dart';
import 'support.dart';

// Opt-in destructive contract test: only use an isolated disposable Studio.
// Never point this at your production workspace.
void main() {
  final server = Platform.environment['EKKO_TEST_SERVER'];
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
