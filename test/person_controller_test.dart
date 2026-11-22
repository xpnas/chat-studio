import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/person_history_cache.dart';
import 'package:chatstudio/data/person_models.dart';
import 'package:chatstudio/state/person_controller.dart';
import 'package:chatstudio/state/session_sync_state.dart';
import 'session_tasks_test.dart' show taskApi, jsonResponse;
import 'person_protocol_test.dart' show personPage, flow;
import 'support.dart' show FakeTransport, FakeSessionSyncTransport;

void main() {
  Future<(PersonController, FakeTransport, FakeSessionSyncTransport)> harness({
    Map<String, dynamic>? cached,
    bool Function()? valid,
  }) async {
    final root = await Directory.systemTemp.createTemp('person-controller-');
    addTearDown(() => root.delete(recursive: true));
    final api = taskApi(
      (r) => jsonResponse({
        'session': {'id': 'person-main-a', 'studio_user_id': 7, 'title': 'A'},
        'settings': {
          'agents': [
            {'id': 'worker'},
          ],
          'model': {'profile': 'other', 'model': 'configured'},
        },
        'tasks': [],
        'interactions': [],
        'history_revision': 0,
        'profiles': ['work', 'other', 'default'],
      }),
    );
    final cache = PersonHistoryCache(root, 'server', '7', 'person-main-a');
    // Dispose the controller first, then drain atomic writes before removing
    // its temporary directory (Windows can otherwise race a pending publish).
    addTearDown(cache.clear);
    if (cached != null) {
      await cache.write({
        'latest': cached,
        'window': [cached],
      });
    }
    final transport = FakeTransport(), observer = FakeSessionSyncTransport();
    final c = PersonController(
      api: api,
      account: 7,
      sessionId: 'person-main-a',
      cache: cache,
      identityValid: valid ?? () => true,
      transport: transport,
      observer: observer,
    );
    addTearDown(c.dispose);
    await c.initialize();
    return (c, transport, observer);
  }

  test(
    'cache hit restores mixed history and live state; miss asks empty id without a run',
    () async {
      final page = personPage(
        refs: [
          {'kind': 'flow', 'id': 'f'},
        ],
        cards: [flow('f')],
      );
      final (c, t, _) = await harness(cached: page);
      t.receive('connected', {});
      expect(t.emitted.last.$1, 'app.resume');
      expect(t.emitted.last.$2, {
        'session_id': 'person-main-a',
        'id': 'cache',
        'timeline': true,
      });
      t.receive('app.resumed', {
        'session_id': 'person-main-a',
        'projection': personProjection,
        'id': 'cache',
        'messagesCached': true,
        'isWorking': true,
        'queueMessages': [
          {'id': 'q', 'content': 'queued'},
        ],
        'events': [],
      });
      expect(c.timeline.items.single.kind, 'flow');
      expect(c.live.working, true);
      expect(c.syncing, false);
      t.receive('app.resumed', {
        'session_id': 'person-main-a',
        'projection': personProjection,
        'id': 'unknown',
        'messagesCached': true,
        'isWorking': false,
      });
      expect(t.emitted.last.$2['id'], '');
      expect(t.emitted.where((e) => e.$1 == 'run'), isEmpty);
    },
  );
  test(
    'first uncached recovery, projection upgrade and clearing reject old responses while preserving draft',
    () async {
      final (c, t, _) = await harness();
      t.receive('connected', {});
      expect(t.emitted.last.$2['id'], '');
      t.receive('app.resumed', {
        'session_id': c.sessionId,
        ...personPage(
          messages: [
            {'id': 1, 'role': 'assistant', 'content': 'old'},
          ],
        ),
        'isWorking': false,
      });
      c.draft.text = 'draft';
      t.receive('app.resumed', {
        'session_id': c.sessionId,
        ...personPage(id: 'clear', revision: 1),
        'isWorking': false,
      });
      expect(c.timeline.items, isEmpty);
      t.receive('app.resumed', {
        'session_id': c.sessionId,
        ...personPage(
          id: 'late',
          revision: 0,
          messages: [
            {'id': 1, 'role': 'assistant', 'content': 'old'},
          ],
        ),
        'isWorking': false,
      });
      expect(c.timeline.items, isEmpty);
      expect(c.draft.text, 'draft');
      t.receive('app.resumed', {
        'session_id': c.sessionId,
        ...personPage(),
        'projection': 'future',
        'isWorking': false,
      });
      expect(c.timeline.latest, isNull);
      expect(c.error, isNotNull);
    },
  );
  test(
    'BOT sends no ordinary model preferences and foreground recovery never replays writes',
    () async {
      final (c, t, _) = await harness();
      t.receive('connected', {});
      t.receive('app.resumed', {
        'session_id': c.sessionId,
        ...personPage(),
        'isWorking': false,
      });
      expect(c.canSend, true);
      expect(c.send('continue original BOT'), true);
      final run = t.emitted.singleWhere((e) => e.$1 == 'run').$2;
      expect(run.keys.toSet(), {'session_id', 'queue_id', 'input'});
      c.onBackground();
      c.onForeground();
      t.receive('connected', {});
      expect(t.emitted.where((e) => e.$1 == 'run').length, 1);
      expect(t.emitted.last.$1, 'app.resume');
    },
  );
  test(
    'durable events remove local deadlines, reject permanent permissions and keep one answer in flight',
    () async {
      final (c, t, _) = await harness();
      t.receive('connected', {});
      t.receive('app.resumed', {
        'session_id': c.sessionId,
        ...personPage(),
        'isWorking': false,
      });
      t.receive('approval.requested', {
        'session_id': c.sessionId,
        'approval_id': 'local-q',
        'durable': true,
        'remaining_timeout_ms': 0,
        'allow_permanent': false,
        'choices': ['once', 'deny'],
      });
      expect(c.live.interaction, isNotNull);
      expect(c.live.interactionDeadline, isNull);
      await c.answerLive('always');
      expect(t.emitted.where((e) => e.$1 == 'approval.respond'), isEmpty);
      await c.answerLive('once');
      await c.answerLive('once');
      expect(t.emitted.where((e) => e.$1 == 'approval.respond').length, 1);
    },
  );
  test(
    'only owned BOT main sessions enter observer across Profile; workers stay excluded',
    () {
      final state = SessionSyncState()
        ..allowedPersonSessions.add('person-main-owned');
      final generation = state.reset('ordinary');
      state.snapshot(generation, [
        {
          'sessionId': 'person-main-owned',
          'profile': 'resource',
          'working': false,
        },
        {
          'sessionId': 'person-main-other',
          'profile': 'ordinary',
          'working': false,
        },
        {
          'sessionId': 'person-task-worker',
          'profile': 'ordinary',
          'working': false,
        },
      ]);
      expect(state.sessions.keys, ['person-main-owned']);
    },
  );
  test(
    'read receipts require actual visible numeric assistant cursor, never cards or raw totals',
    () async {
      final (c, t, observer) = await harness();
      observer.sessions = [
        {
          'sessionId': c.sessionId,
          'profile': 'other',
          'working': false,
          'unread': true,
          'lastMessageId': 99,
          'readMessageId': 0,
          'lastAttentionId': 0,
          'readAttentionId': 0,
        },
      ];
      observer.requestState();
      t.receive('connected', {});
      t.receive('app.resumed', {
        'session_id': c.sessionId,
        ...personPage(
          refs: [
            {'kind': 'flow', 'id': '900'},
          ],
          cards: [flow('900')],
        ),
        'isWorking': false,
        'messageTotal': 99,
      });
      expect(
        await c.confirmVisibleRead(latest: true, routeVisible: true),
        false,
      );
      expect(observer.reads, isEmpty);
      t.receive('app.resumed', {
        'session_id': c.sessionId,
        ...personPage(
          id: 'visible',
          messages: [
            {'id': 7, 'role': 'assistant', 'content': 'actual'},
          ],
        ),
        'isWorking': false,
      });
      expect(
        await c.confirmVisibleRead(
          latest: true,
          routeVisible: true,
          visibleMessageId: 7,
        ),
        true,
      );
      expect(observer.reads.single['messageId'], 7);
      c.timeline.beginReading();
      expect(
        await c.confirmVisibleRead(latest: true, routeVisible: true),
        false,
      );
    },
  );
  test(
    'identity invalidation rejects late socket content and writes',
    () async {
      var valid = true;
      final (c, t, _) = await harness(valid: () => valid);
      t.receive('connected', {});
      valid = false;
      t.receive('app.resumed', {
        'session_id': c.sessionId,
        ...personPage(
          messages: [
            {'id': 1, 'role': 'assistant', 'content': 'private'},
          ],
        ),
        'isWorking': false,
      });
      expect(c.timeline.items, isEmpty);
      expect(c.send('invalid'), false);
      expect(t.emitted.where((e) => e.$1 == 'run'), isEmpty);
    },
  );
}
