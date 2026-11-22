import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/chat_transport.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/person_api.dart';
import 'package:chatstudio/data/person_models.dart';
import 'package:chatstudio/data/person_history_cache.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/state/app_controller.dart';
import 'package:chatstudio/state/person_controller.dart';
import 'package:chatstudio/state/person_task_controller.dart';
import 'support.dart';

String? personContractSetting(String name) {
  final value =
      Platform.environment[name] ??
      const {
        'CHATSTUDIO_TEST_SERVER': String.fromEnvironment(
          'CHATSTUDIO_TEST_SERVER',
        ),
        'CHATSTUDIO_TEST_PASSWORD': String.fromEnvironment(
          'CHATSTUDIO_TEST_PASSWORD',
        ),
        'CHATSTUDIO_TEST_BASELINE': String.fromEnvironment(
          'CHATSTUDIO_TEST_BASELINE',
        ),
      }[name];
  return value == null || value.isEmpty ? null : value;
}

class _CountingPersonTransport extends SocketChatTransport {
  final counts = <String, int>{};
  @override
  void emit(String event, Map<String, dynamic> data) {
    counts[event] = (counts[event] ?? 0) + 1;
    super.emit(event, data);
  }
}

void main() {
  final server = personContractSetting('CHATSTUDIO_TEST_SERVER');
  test(
    'real Studio creates an owned BOT and changes its model without changing another BOT',
    () async {
      final app = AppController(storage: MemoryStorage());
      PersonConversation? created;
      try {
        await app.initialize();
        expect(
          await app.login(
            server!,
            'admin',
            personContractSetting('CHATSTUDIO_TEST_PASSWORD')!,
            true,
          ),
          true,
        );
        final api = app.api!, owner = app.account!.id;
        final existing = (await api.personConversations(owner)).sessions.first;
        final before = await api.personSnapshot(existing.id, owner);
        final defaults = await api.personDefaults();
        final options = await api.personModels();
        expect(options, isNotEmpty);
        created = await api.createPersonConversation(
          owner,
          title:
              'Mobile model contract ${DateTime.now().microsecondsSinceEpoch}',
          revision: defaults.revision,
          model: options.first,
        );
        expect(created.ownedBy(owner), true);
        final current = await api.personSnapshot(created.id, owner);
        final selected = options.length > 1 ? options.last : options.first;
        final saved = await api.changePersonModel(
          created.id,
          current.settingsRevision,
          selected,
        );
        expect(asMap(asMap(saved['settings'])['model'])['model'], selected.id);
        final reloaded = await api.personSnapshot(created.id, owner);
        final actual = asMap(reloaded.settings['model']);
        expect(actual['profile'], selected.profile);
        expect(actual['provider'], selected.provider);
        expect(actual['model'], selected.id);
        expect(
          reloaded.settingsRevision,
          greaterThan(current.settingsRevision),
        );
        expect(
          (await api.personSnapshot(existing.id, owner)).settings['model'],
          before.settings['model'],
        );
        await expectLater(
          api.changePersonModel(
            created.id,
            current.settingsRevision,
            options.first,
          ),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
      } finally {
        if (created != null && app.api != null && app.account != null) {
          final current = await app.api!.personSnapshot(
            created.id,
            app.account!.id,
          );
          await app.api!.request(
            '/api/studio/person/conversations/${Uri.encodeComponent(created.id)}',
            method: 'DELETE',
            body: {'expected_history_revision': current.historyRevision},
          );
        }
        app.dispose();
      }
    },
    skip:
        server == null ||
        personContractSetting('CHATSTUDIO_TEST_BASELINE') == 'legacy',
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'stable durable worker question, answer conflict, task follow-up and main stop preserve background work',
    () async {
      final app = AppController(storage: MemoryStorage());
      final root = await Directory.systemTemp.createTemp('person-worker-live-');
      PersonController? person;
      PersonTaskController? detail;
      Future<void> until(
        Future<bool> Function() condition,
        String stage,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 65));
        while (!await condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              '$stage: ${person?.error}; ${person?.live.messages.map((m) => m.failure).join()}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }

      try {
        await app.initialize();
        expect(
          await app.login(
            server!,
            'admin',
            personContractSetting('CHATSTUDIO_TEST_PASSWORD')!,
            true,
          ),
          true,
        );
        final api = app.api!, owner = app.account!.id;
        final bot = (await api.personConversations(
          owner,
        )).sessions.firstWhere((b) => b.title == 'Mobile Bot A');
        final transport = _CountingPersonTransport();
        person = PersonController(
          api: StudioApi(api.address)
            ..token = api.token
            ..profile = api.profile,
          account: owner,
          sessionId: bot.id,
          cache: PersonHistoryCache(root, server, '$owner', bot.id),
          identityValid: () => app.authenticated,
          transport: transport,
        );
        await person.initialize();
        await until(() async => person!.canSend, 'resume');
        final created = await api.request(
          '/api/studio/person/tasks/apply',
          method: 'POST',
          body: {
            'action': 'create',
            'session_id': bot.id,
            'title': 'Durable fixture question',
            'goal': 'BOT_DURABLE_QUESTION BOT_RESULT_ATTACHMENT',
            'agent_id': 'mobile-fixture-worker',
            'idempotency_key':
                'question-${DateTime.now().microsecondsSinceEpoch}',
          },
        );
        final taskId = text(asMap(created['task'])['id']);
        expect(taskId, isNotEmpty);
        await until(() async {
          await person!.refreshSnapshot();
          return person.interactions.isNotEmpty;
        }, 'durable worker question');
        final question = person.interactions.firstWhere(
          (q) => q.taskId == taskId,
        );
        expect(question.pending, true);
        expect(question.event['durable'], true);
        expect(question.event['allow_permanent'], false);
        await person.answer(question, 'A');
        await expectLater(
          api.answerPersonInteraction(question, 'B'),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
        detail = PersonTaskController(person, taskId);
        await until(() async {
          await detail!.refresh();
          return detail.task?.executionState == 'finished';
        }, 'worker answer completion');
        final artifact = RegExp(
          r'path=([^\)]+)',
        ).firstMatch(detail.execution!.output);
        expect(artifact, isNotNull);
        expect(
          String.fromCharCodes(
            await api.attachmentBytes(
              MessageAttachment(
                name: 'mobile-result.txt',
                path: Uri.decodeComponent(artifact![1]!),
                mimeType: 'text/plain',
              ),
            ),
          ),
          'BOT_RESULT_ATTACHMENT verified fixture artifact.',
        );
        final firstExecution = detail.task!.executionId;
        await detail.followUp('Continue this same result');
        await until(() async {
          await detail!.refresh();
          return detail.task?.executionState == 'finished' &&
              detail.task!.executionId != firstExecution;
        }, 'task follow-up');
        expect(detail.executions.length, 2);
        await detail.refresh(executionId: firstExecution);
        expect(detail.current, false);
        expect(detail.canFollowUp, false);
        final slow = await api.request(
          '/api/studio/person/tasks/apply',
          method: 'POST',
          body: {
            'action': 'create',
            'session_id': bot.id,
            'title': 'Slow worker fixture',
            'goal': 'SLOW background keeps running',
            'agent_id': 'mobile-fixture-worker',
            'idempotency_key': 'slow-${DateTime.now().microsecondsSinceEpoch}',
          },
        );
        final slowId = text(asMap(slow['task'])['id']);
        await until(() async {
          await person!.refreshSnapshot();
          return person.snapshot!.tasks.any(
                (t) => t.id == slowId && t.running,
              ) &&
              person.canSend;
        }, 'background admission');
        expect(person.send('SLOW main run to stop'), true);
        await until(
          () async => person!.live.messages.any(
            (m) => m.pending && m.role == 'assistant' && m.content.length > 2,
          ),
          'main live stream',
        );
        person.onBackground();
        person.onForeground();
        await until(
          () async => person!.connected && !person.syncing && person.working,
          'active BOT resume',
        );
        person.stop();
        await until(() async => !person!.working, 'main stop');
        await person.refreshSnapshot();
        expect(
          person.snapshot!.tasks.any(
            (task) => task.id == slowId && task.running,
          ),
          true,
        );
        expect(transport.counts['run'], 1);
        final slowDetail = PersonTaskController(person, slowId);
        await slowDetail.refresh();
        await slowDetail.stop();
        await until(() async {
          await slowDetail.refresh();
          return slowDetail.task?.running == false;
        }, 'background explicit stop');
        slowDetail.dispose();
      } finally {
        detail?.dispose();
        person?.dispose();
        app.dispose();
        await root.delete(recursive: true);
      }
    },
    skip:
        server == null ||
        personContractSetting('CHATSTUDIO_TEST_BASELINE') == 'legacy',
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'stable real BOT ownership, projected resume, native configuration, flow control and cache hit',
    () async {
      final app = AppController(storage: MemoryStorage());
      final root = await Directory.systemTemp.createTemp('person-live-');
      PersonController? first, second;
      Future<void> until(bool Function() condition, String stage) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              '$stage: ${first?.error}, ${second?.error}; working=${first?.working}; live=${first?.live.messages.map((m) => '${m.content}:${m.failure}').join('|')}; page=${first?.timeline.latest?.messages.values.map((m) => m.content).join('|')}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      try {
        await app.initialize();
        expect(
          await app.login(
            server!,
            'admin',
            personContractSetting('CHATSTUDIO_TEST_PASSWORD')!,
            true,
          ),
          true,
        );
        final api = app.api!, owner = app.account!.id;
        final bots = await api.personConversations(owner);
        expect(bots.sessions.length, greaterThanOrEqualTo(2));
        final a = bots.sessions.firstWhere((b) => b.title == 'Mobile Bot A'),
            b = bots.sessions.firstWhere((b) => b.title == 'Mobile Bot B');
        final t1 = _CountingPersonTransport(), t2 = _CountingPersonTransport();
        PersonController make(_CountingPersonTransport transport) {
          final client = StudioApi(api.address)
            ..token = api.token
            ..profile = api.profile;
          return PersonController(
            api: client,
            account: owner,
            sessionId: a.id,
            cache: PersonHistoryCache(root, server, '$owner', a.id),
            identityValid: () => app.authenticated,
            transport: transport,
          );
        }

        first = make(t1);
        await first.initialize();
        await until(() => first!.canSend, 'first resume');
        final originalSettings = first.snapshot!.settings;
        expect(first.send('BOT real server fixture conversation'), true);
        await until(
          () =>
              !first!.working &&
              first.timeline.latest!.messages.values.any(
                (m) => m.role == 'assistant' && m.content.contains('本地协议自测'),
              ),
          'first completion',
        );
        second = make(t2);
        await second.initialize();
        await until(() => second!.canSend, 'second cache resume');
        expect(second.snapshot!.settings, originalSettings);
        expect(second.timeline.latest!.projection, personProjection);
        expect(second.send('Continue the same configured BOT'), true);
        await until(
          () =>
              !second!.working &&
              second.timeline.latest!.messages.values
                      .where((m) => m.role == 'assistant')
                      .length >=
                  2,
          'second completion',
        );
        expect(t1.counts['run'], 1);
        expect(t2.counts['run'], 1);
        final created = await api.applyPersonFlow({
          'action': 'create',
          'session_id': a.id,
          'title': 'Mobile route fixture',
          'goal': 'Verify flow lifecycle',
          'rounds': 1,
          'stages': [
            {
              'session_id': b.id,
              'goal': 'Return a fixture result',
              'return_expectation': 'A visible reply',
              'group': 0,
            },
          ],
          'idempotency_key':
              'mobile-flow-${DateTime.now().microsecondsSinceEpoch}',
        });
        expect(created.state, 'active');
        final stopped = await api.applyPersonFlow({
          'action': 'stop',
          'flow_id': created.id,
          'expected_revision': created.revision,
          'idempotency_key': 'stop-${created.id}',
        });
        expect(stopped.state, 'stopped');
        final page = await api.personTimeline(a.id);
        expect(
          page.items.any(
            (item) => item.kind == 'flow' && item.id == created.id,
          ),
          true,
        );
        final detail = await api.personFlowMessages(created.id);
        expect(detail.historyKey, isNotEmpty);
        expect(detail.flow.id, created.id);
        await first.refreshSnapshot();
        first.requestResume();
        await until(
          () =>
              !first!.syncing &&
              first.timeline.items.any(
                (i) => i.kind == 'flow' && i.id == created.id,
              ),
          'card resume',
        );
        final oldItems = first.timeline.items.map((i) => i.key).toList();
        first.timeline.beginReading();
        first.draft.text = 'BOT draft retained';
        first.onBackground();
        first.onForeground();
        await until(
          () => first!.connected && !first.syncing,
          'offline restore',
        );
        expect(first.draft.text, 'BOT draft retained');
        expect(first.timeline.items.map((i) => i.key), oldItems);
        expect(t1.counts['run'], 1);
        final current = (await api.personFlows(flowId: created.id)).single;
        await expectLater(
          api.applyPersonFlow({
            'action': 'resume',
            'flow_id': created.id,
            'expected_revision': current.revision - 1,
            'idempotency_key': 'stale-${created.id}',
          }),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
        final freshFlow = (await api.personFlows(flowId: created.id)).single;
        final resumedFlow = await api.applyPersonFlow({
          'action': 'resume',
          'flow_id': created.id,
          'expected_revision': freshFlow.revision,
          'idempotency_key': 'resume-${created.id}',
        });
        expect(resumedFlow.state, 'active');
        final runningFlow = (await api.personFlows(flowId: created.id)).single;
        await api.applyPersonFlow({
          'action': 'stop',
          'flow_id': created.id,
          'expected_revision': runningFlow.revision,
          'idempotency_key': 'restop-${created.id}',
        });
        await until(
          () => !first!.working && !second!.working,
          'idle before remote clear',
        );
        final clearSnapshot = await api.request(
          '/api/studio/person',
          query: {'session_id': a.id},
        );
        expect(clearSnapshot['can_clear'], true);
        final oldPage = first.timeline.latest!.raw;
        await api.request(
          '/api/studio/person/clear',
          method: 'POST',
          body: {
            'session_id': a.id,
            'expected_history_revision': clearSnapshot['history_revision'],
          },
        );
        await first.refreshSnapshot();
        first.requestResume(full: true);
        second.requestResume(full: true);
        await until(
          () =>
              !first!.syncing &&
              !second!.syncing &&
              first.timeline.items.isEmpty &&
              second.timeline.items.isEmpty,
          'cross-client history clear',
        );
        expect(first.draft.text, 'BOT draft retained');
        first.onEvent('app.resumed', {
          'session_id': a.id,
          ...oldPage,
          'isWorking': false,
          'messagesCached': false,
        });
        expect(first.timeline.items, isEmpty);
      } finally {
        first?.dispose();
        second?.dispose();
        app.dispose();
        await root.delete(recursive: true);
      }
    },
    skip:
        server == null ||
        personContractSetting('CHATSTUDIO_TEST_BASELINE') == 'legacy',
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'real sequential and parallel BOT stages finish two rounds with persisted results on both clients',
    () async {
      final app = AppController(storage: MemoryStorage());
      final root = await Directory.systemTemp.createTemp('person-flow-live-');
      final clients = <PersonController>[];
      Future<void> until(Future<bool> Function() ready, String stage) async {
        final deadline = DateTime.now().add(const Duration(seconds: 100));
        while (!await ready()) {
          if (DateTime.now().isAfter(deadline)) fail(stage);
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }

      try {
        await app.initialize();
        expect(
          await app.login(
            server!,
            'admin',
            personContractSetting('CHATSTUDIO_TEST_PASSWORD')!,
            true,
          ),
          true,
        );
        final api = app.api!, owner = app.account!.id;
        final bots = (await api.personConversations(owner)).sessions;
        final a = bots.firstWhere((b) => b.title == 'Mobile Flow A');
        final b = bots.firstWhere((b) => b.title == 'Mobile Flow B');
        final c = bots.firstWhere((b) => b.title == 'Mobile Flow C');
        for (var i = 0; i < 2; i++) {
          final client = PersonController(
            api: StudioApi(api.address)
              ..token = api.token
              ..profile = api.profile,
            account: owner,
            sessionId: a.id,
            cache: PersonHistoryCache(root, server, '$owner', '${a.id}-$i'),
            identityValid: () => app.authenticated,
            transport: _CountingPersonTransport(),
          );
          clients.add(client);
          await client.initialize();
        }
        await until(
          () async => clients.every((p) => p.canSend),
          'two clients restore',
        );
        for (final parallel in [false, true]) {
          final stages = [
            {
              'session_id': b.id,
              'goal': 'BOT_FLOW_CLOSED_LOOP return fixture result',
              'return_expectation':
                  'BOT_FLOW_CLOSED_LOOP fixture result delivered.',
              'group': 0,
            },
            if (parallel)
              {
                'session_id': c.id,
                'goal': 'BOT_FLOW_CLOSED_LOOP return fixture result',
                'return_expectation':
                    'BOT_FLOW_CLOSED_LOOP fixture result delivered.',
                'group': 0,
              },
            {
              'session_id': a.id,
              'goal': 'BOT_FLOW_CLOSED_LOOP return fixture result',
              'return_expectation':
                  'BOT_FLOW_CLOSED_LOOP fixture result delivered.',
              'group': 1,
            },
          ];
          final key = 'closed-loop-${DateTime.now().microsecondsSinceEpoch}';
          final input = <String, dynamic>{
            'action': 'create',
            'session_id': a.id,
            'title': parallel
                ? 'Parallel closed loop'
                : 'Sequential closed loop',
            'goal': 'BOT_FLOW_CLOSED_LOOP',
            'rounds': 2,
            'stages': stages,
            'idempotency_key': key,
          };
          final created = await api.applyPersonFlow(input);
          expect((await api.applyPersonFlow(input)).id, created.id);
          PersonFlow? completed;
          await until(() async {
            completed = (await api.personFlows(flowId: created.id)).single;
            if (completed!.state == 'failed') {
              fail(
                'Real flow failed: ${completed!.error}; ${completed!.stages.map((s) => s.confirmation)}',
              );
            }
            return completed!.state == 'completed';
          }, 'real flow completion');
          expect(completed!.roundNumber, 2);
          expect(completed!.stages.every((stage) => stage.confirmed), true);
          final detail = await api.personFlowMessages(created.id);
          expect(
            detail.messages
                .where(
                  (m) => text(
                    m['content'],
                  ).contains('BOT_FLOW_CLOSED_LOOP fixture result delivered.'),
                )
                .length,
            stages.length * 2,
          );
          expect(detail.messages.every((m) => m['role'] == 'assistant'), true);
          for (final client in clients) {
            client.requestResume(full: true);
          }
          await until(
            () async => clients.every(
              (p) =>
                  !p.syncing &&
                  p.timeline.flows[created.id]?.state == 'completed',
            ),
            'both clients completed history',
          );
          expect(
            clients
                .map((p) => p.timeline.flows[created.id]!.revision)
                .toSet()
                .length,
            1,
          );
          await expectLater(
            api.applyPersonFlow({
              'action': 'resume',
              'flow_id': created.id,
              'expected_revision': completed!.revision,
              'idempotency_key': 'resume-completed-$key',
            }),
            throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
          );
        }
        expect(
          clients.every(
            (p) =>
                (p.transport as _CountingPersonTransport).counts['run'] == null,
          ),
          true,
        );
      } finally {
        for (final client in clients) {
          client.dispose();
        }
        app.dispose();
        await root.delete(recursive: true);
      }
    },
    skip:
        server == null ||
        personContractSetting('CHATSTUDIO_TEST_BASELINE') == 'legacy',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
