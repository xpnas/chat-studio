import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/data/mobile_media.dart';
import 'package:ekko_app/main.dart';
import 'package:ekko_app/state/conversation_state.dart';
import 'package:ekko_app/ui/widgets/conversation_activity_mark.dart';
import 'support.dart';

void main() {
  void started(TestHarness h, String sid, String run) =>
      h.transport.receive('run.started', {'session_id': sid, 'run_id': run});
  void delta(TestHarness h, String sid, String run, String text) =>
      h.transport.receive('message.delta', {
        'session_id': sid,
        'run_id': run,
        'delta': text,
      });
  void resumed(
    TestHarness h,
    String sid, {
    bool working = false,
    String effort = '',
    List<Map<String, dynamic>>? messages,
  }) => h.transport.receive('resumed', {
    'session_id': sid,
    'isWorking': working,
    'reasoning_effort': effort,
    'messages':
        messages ??
        [
          {'id': 'user-$sid', 'role': 'user', 'content': 'history question'},
          {'id': 'ai-$sid', 'role': 'assistant', 'content': 'history answer'},
        ],
    'messageLoadedCount': 2,
    'hasMoreBefore': false,
    'events': [],
  });
  Future<Conversation> startA(TestHarness h) async {
    await h.login();
    expect(h.controller.send('task A'), true);
    final sid = h.controller.sessionId!;
    started(h, sid, 'run-A');
    delta(h, sid, 'run-A', 'A: first');
    return h.controller.current!;
  }

  const b = Conversation(
    id: 'B',
    title: 'conversation B',
    profile: 'default',
    agent: 'ekko-agent',
    model: 'model-a',
    provider: 'test',
  );

  test(
    'running A can switch to B, keep streaming, and B can start independently',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      final aTimeline = h.controller.timeline;
      await h.controller.openConversation(b);
      resumed(h, 'B');
      expect(h.controller.sessionId, 'B');
      expect(h.controller.working, false);
      expect(h.controller.taskStatus(a), ConversationTaskStatus.running);
      delta(h, a.id, 'run-A', ' + background');
      expect(aTimeline.messages.last.content, 'A: first + background');
      expect(h.controller.timeline.messages.last.content, 'history answer');
      expect(h.controller.send('task B'), true);
      started(h, 'B', 'run-B');
      delta(h, 'B', 'run-B', 'B: second');
      expect(
        h.transport.emitted
            .where((e) => e.$1 == 'run')
            .map((e) => e.$2['session_id']),
        [a.id, 'B'],
      );
      h.controller.stop();
      expect(h.transport.emitted.last.$1, 'abort');
      expect(h.transport.emitted.last.$2, {'session_id': 'B'});
      expect(aTimeline.working, true);
      await h.controller.openConversation(a);
      expect(h.controller.timeline, same(aTimeline));
      expect(
        h.controller.timeline.messages.last.content,
        'A: first + background',
      );
      expect(h.transport.emitted.where((e) => e.$1 == 'abort').length, 1);
    },
  );
  test(
    'background completion and failure affect only their own session',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      final original = h.controller.timeline;
      await h.controller.openConversation(b);
      resumed(h, 'B');
      final current = h.controller.timeline;
      h.transport.receive('run.completed', {
        'session_id': a.id,
        'run_id': 'run-A',
        'output': 'A complete',
      });
      expect(original.working, false);
      expect(original.messages.last.content, 'A complete');
      expect(h.controller.timeline, same(current));
      expect(h.controller.taskStatus(a), ConversationTaskStatus.completed);
      expect(h.controller.error, isNull);
      h.controller.send('B fails');
      started(h, 'B', 'run-B');
      h.transport.receive('run.failed', {
        'session_id': 'B',
        'run_id': 'run-B',
        'error': 'failure B',
      });
      expect(h.controller.timeline.messages.last.delivery, 'failed');
      expect(original.messages.last.content, 'A complete');
    },
  );
  test(
    'background approval marks A and is actionable only when A is selected',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      await h.controller.openConversation(b);
      resumed(h, 'B');
      h.transport.receive('approval.requested', {
        'session_id': a.id,
        'run_id': 'run-A',
        'approval_id': 'approval-A',
        'remaining_timeout_ms': 60000,
        'choices': ['once', 'deny'],
      });
      expect(h.controller.timeline.interaction, isNull);
      expect(h.controller.taskStatus(a), ConversationTaskStatus.waiting);
      final emitted = h.transport.emitted.length;
      h.controller.respondToInteraction('once');
      expect(h.transport.emitted.length, emitted);
      await h.controller.openConversation(a);
      expect(h.controller.timeline.interaction?['approval_id'], 'approval-A');
      final beforeSync = h.transport.emitted.length;
      h.controller.respondToInteraction('deny');
      expect(h.transport.emitted.length, beforeSync);
      h.transport.receive('resumed', {
        'session_id': a.id,
        'isWorking': true,
        'messages': [
          {'id': 'u', 'role': 'user', 'content': 'task A'},
        ],
        'events': [
          {
            'event': 'run.started',
            'data': {'run_id': 'run-A'},
          },
          {
            'event': 'approval.requested',
            'data': {
              'run_id': 'run-A',
              'approval_id': 'approval-A',
              'remaining_timeout_ms': 60000,
              'choices': ['once', 'deny'],
            },
          },
        ],
      });
      h.controller.respondToInteraction('deny');
      expect(h.transport.emitted.last.$1, 'approval.respond');
      expect(h.transport.emitted.last.$2, {
        'session_id': a.id,
        'approval_id': 'approval-A',
        'choice': 'deny',
      });
    },
  );
  test(
    'reconnect resumes all locally tracked runs without re-emitting inputs',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      h.controller.newChat();
      h.controller.send('task second');
      final second = h.controller.sessionId!;
      started(h, second, 'run-second');
      h.transport.receive('disconnected', {});
      expect(h.controller.taskStatus(a), ConversationTaskStatus.checking);
      final before = h.transport.emitted.length;
      h.transport.receive('connected', {});
      final recovery = h.transport.emitted.skip(before).toList();
      expect(recovery.where((e) => e.$1 == 'run'), isEmpty);
      expect(
        recovery
            .where((e) => e.$1 == 'resume')
            .map((e) => e.$2['session_id'])
            .toSet(),
        {a.id, second},
      );
      resumed(h, a.id, working: true);
      expect(h.controller.sessionId, second);
      expect(h.controller.syncing, true);
      resumed(h, second, working: true);
      expect(h.controller.syncing, false);
    },
  );
  test(
    'Profile switching keeps tasks cached but rejects old socket callbacks',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      final oldListener = h.transport.listener!;
      final aTimeline = h.controller.timeline;
      await h.controller.switchProfile('work');
      expect(h.controller.profile, 'work');
      expect(h.controller.sessionId, isNull);
      oldListener('message.delta', {
        'session_id': a.id,
        'run_id': 'run-A',
        'delta': 'must ignore',
      });
      expect(aTimeline.messages.last.content, 'A: first');
      expect(h.controller.taskStatus(a), ConversationTaskStatus.checking);
      await h.controller.switchProfile('default');
      h.transport.receive('connected', {});
      await h.controller.openConversation(a);
      expect(h.controller.timeline, same(aTimeline));
      expect(h.transport.emitted.where((e) => e.$1 == 'abort'), isEmpty);
    },
  );
  test(
    'rapid navigation and late history response cannot replace the visible conversation',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final pending = Completer<http.Response>();
      h.override = (r) => r.url.path.contains('/B/messages')
          ? pending.future
          : Future.value(h.response(r));
      final opening = h.controller.openConversation(b);
      await Future<void>.delayed(Duration.zero);
      const c = Conversation(id: 'C', title: 'C');
      await h.controller.openConversation(c);
      resumed(h, 'C');
      final visible = h.controller.timeline;
      pending.complete(
        http.Response(
          '{"messages":[{"id":10,"role":"assistant","content":"late B"}],"hasMore":false}',
          200,
        ),
      );
      await opening;
      expect(h.controller.sessionId, 'C');
      expect(h.controller.timeline, same(visible));
      expect(h.controller.timeline.messages.last.content, 'history answer');
    },
  );
  test(
    'activity snapshot and timestamped changes mark unopened conversations accurately',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final row = h.controller.conversations.single;
      h.transport.receive('session.activity.snapshot', {
        'profile': 'default',
        'timestamp': 10,
        'sessions': [
          {'session_id': row.id, 'status': 'running'},
        ],
      });
      expect(h.controller.taskStatus(row), ConversationTaskStatus.running);
      h.transport.receive('session.activity', {
        'session_id': row.id,
        'status': 'completed',
        'timestamp': 20,
      });
      expect(h.controller.taskStatus(row), ConversationTaskStatus.completed);
      h.transport.receive('session.activity', {
        'session_id': row.id,
        'status': 'running',
        'timestamp': 15,
      });
      expect(h.controller.taskStatus(row), ConversationTaskStatus.completed);
      h.transport.receive('session.activity.snapshot', {
        'profile': 'other',
        'timestamp': 30,
        'sessions': [
          {'session_id': row.id, 'status': 'running'},
        ],
      });
      expect(h.controller.taskStatus(row), ConversationTaskStatus.completed);
    },
  );
  test(
    'missing active run in snapshot is checked, not silently marked completed',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      h.transport.receive('session.activity.snapshot', {
        'profile': 'default',
        'sessions': [],
        'timestamp': 10,
      });
      expect(h.controller.taskStatus(a), ConversationTaskStatus.checking);
      expect(h.transport.emitted.last.$1, 'resume');
      expect(h.transport.emitted.last.$2, {'session_id': a.id});
      resumed(h, a.id);
      expect(h.controller.taskStatus(a), ConversationTaskStatus.idle);
    },
  );
  test('cannot delete a running background conversation', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    final a = await startA(h);
    h.controller.newChat();
    final before = h.requests.length;
    await h.controller.deleteConversation(a);
    expect(h.requests.length, before);
  });
  test(
    'reasoning choices reach run payload, session REST, and persisted preferences',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.chooseReasoningEffort('high');
      expect(h.controller.reasoningEffort, 'high');
      expect(h.storage.choices.values.single['reasoning_effort'], 'high');
      expect(h.controller.send('deep task'), true);
      expect(h.transport.emitted.last.$2['reasoning_effort'], 'high');
      final sid = h.controller.sessionId!;
      started(h, sid, 'r');
      await h.controller.chooseReasoningEffort('low');
      expect(h.controller.reasoningEffort, 'high');
      h.transport.receive('run.failed', {
        'session_id': sid,
        'run_id': 'r',
        'error': 'finished for fixture',
      });
      await h.controller.chooseReasoningEffort('max');
      final request = h.requests.lastWhere(
        (r) => r.url.path.endsWith('/reasoning-effort'),
      );
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {'reasoningEffort': 'max'});
      expect(h.controller.reasoningEffort, 'max');
      await h.controller.chooseModel(h.controller.models.last);
      expect(h.controller.reasoningEffort, '');
    },
  );
  test(
    'reasoning REST errors do not optimistically change the selection',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.openConversation(b);
      resumed(h, 'B', effort: 'medium');
      h.override = (r) async => r.url.path.endsWith('/reasoning-effort')
          ? http.Response('{"error":"not permitted"}', 403)
          : h.response(r);
      await h.controller.chooseReasoningEffort('high');
      expect(h.controller.reasoningEffort, 'medium');
      expect(h.controller.error, 'not permitted');
    },
  );
  test(
    'resumed reasoning settings apply to their session, not another chat',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      await h.controller.openConversation(b);
      resumed(h, 'B', effort: 'low');
      resumed(h, a.id, working: true, effort: 'xhigh');
      expect(h.controller.reasoningEffort, 'low');
      await h.controller.openConversation(a);
      expect(h.controller.reasoningEffort, 'xhigh');
    },
  );
  test(
    'same identifiers in different Profiles do not share task status or draft',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.openConversation(b);
      resumed(h, 'B');
      h.controller.draft.text = 'default text';
      await h.controller.switchProfile('work');
      h.transport.receive('connected', {});
      await h.controller.openConversation(
        const Conversation(id: 'B', title: 'work B', profile: 'work'),
      );
      resumed(h, 'B');
      expect(h.controller.draft.text, isEmpty);
      h.controller.draft.text = 'work text';
      await h.controller.switchProfile('default');
      h.transport.receive('connected', {});
      await h.controller.openConversation(b);
      expect(h.controller.draft.text, 'default text');
    },
  );
  testWidgets(
    'drawer remains navigable during a run and shows compact animated task rows',
    (tester) async {
      final h = TestHarness();
      final a = await startA(h);
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('对话记录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final tile = find.byKey(ValueKey('history:${a.id}'));
      expect(tile, findsOneWidget);
      expect(
        find.descendant(
          of: tile,
          matching: find.byKey(const Key('task-running-animation')),
        ),
        findsOneWidget,
      );
      expect(tester.widget<ListTile>(tile).onTap, isNotNull);
      expect(tester.widget<ListTile>(tile).minTileHeight, 54);
      final label = tester.widget<Text>(
        find.descendant(of: tile, matching: find.text('task A')),
      );
      expect(label.style!.fontSize, 13);
      await tester.tap(find.byKey(const ValueKey('history:history-1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(h.controller.sessionId, 'history-1');
      expect(h.transport.emitted.where((e) => e.$1 == 'abort'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'composer offers all supported depth options and prioritizes current depth',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reasoning-button')));
      await tester.pumpAndSettle();
      expect(find.text('思考深度'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('reasoning:high')));
      await tester.tap(find.byKey(const ValueKey('reasoning:high')));
      await tester.pumpAndSettle();
      expect(h.controller.reasoningEffort, 'high');
      expect(find.text('思考 · 高'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'per-chat text drafts survive switching without overwriting each other',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await tester.pump();
      await h.controller.openConversation(b);
      resumed(h, 'B');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('message-input')), 'draft B');
      h.controller.newChat();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        isEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('message-input')),
        'new text',
      );
      await h.controller.openConversation(b);
      resumed(h, 'B');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        'draft B',
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'reduce-motion mode uses a static task mark and meaningful semantics',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const Scaffold(
              body: ConversationActivityMark(
                status: ConversationTaskStatus.running,
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .value,
        .7,
      );
      expect(find.bySemanticsLabel('任务执行中'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('background send timer checks A even while idle B is selected', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    h.controller.send('unacknowledged A');
    final a = h.controller.current!;
    await h.controller.openConversation(b);
    resumed(h, 'B');
    final before = h.transport.emitted.length;
    await tester.pump(const Duration(seconds: 26));
    expect(
      h.transport.emitted
          .skip(before)
          .where((e) => e.$1 == 'resume')
          .map((e) => e.$2['session_id']),
      [a.id],
    );
    expect(h.controller.sessionId, 'B');
    expect(h.controller.error, isNull);
    h.dispose();
  });
  test(
    'logout clears per-session private state and prevents old events from restoring it',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      final listener = h.transport.listener!;
      h.controller.newChat();
      await h.controller.logout();
      listener('message.delta', {
        'session_id': a.id,
        'run_id': 'run-A',
        'delta': 'late private',
      });
      expect(h.controller.timeline.messages, isEmpty);
      expect(h.controller.draft.text, isEmpty);
      expect(h.controller.taskStatus(a), ConversationTaskStatus.idle);
    },
  );
  test('unsent Profile drafts survive leaving and returning', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    h.controller.draft.text = 'default draft';
    await h.controller.switchProfile('work');
    h.controller.draft.text = 'work draft';
    await h.controller.switchProfile('default');
    expect(h.controller.draft.text, 'default draft');
    await h.controller.switchProfile('work');
    expect(h.controller.draft.text, 'work draft');
  });
  test(
    'resuming failed cached conversation preserves error and manual retry state',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      h.transport.receive('run.failed', {
        'session_id': a.id,
        'run_id': 'run-A',
        'error': 'A failed',
      });
      h.controller.newChat();
      await h.controller.openConversation(a);
      resumed(
        h,
        a.id,
        messages: [
          {'id': 'persisted-user', 'role': 'user', 'content': 'task A'},
        ],
      );
      expect(h.controller.timeline.messages.single.delivery, 'failed');
      expect(h.controller.taskStatus(a), ConversationTaskStatus.failed);
      h.controller.prepareRetry();
      expect(h.controller.retryInput, 'task A');
    },
  );
  testWidgets(
    'returning to a cached long conversation restores reading offset',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      h.controller.sessionId = 'long';
      h.controller.current = const Conversation(
        id: 'long',
        title: 'long',
        agent: 'ekko-agent',
      );
      h.controller.timeline.replace(
        List.generate(
          60,
          (i) => ChatMessage(
            id: 'long-$i',
            role: i.isEven ? 'user' : 'assistant',
            content: 'history $i\nlong content for reading',
          ),
        ),
      );
      h.controller.dismissError();
      await tester.pumpAndSettle();
      var scroll = tester
          .widget<ListView>(find.byKey(const Key('message-list')))
          .controller!;
      scroll.jumpTo(1400);
      await tester.pumpAndSettle();
      final before = scroll.offset;
      h.controller.newChat();
      await tester.pumpAndSettle();
      await h.controller.openConversation(
        const Conversation(id: 'long', title: 'long', agent: 'ekko-agent'),
      );
      await tester.pumpAndSettle();
      scroll = tester
          .widget<ListView>(find.byKey(const Key('message-list')))
          .controller!;
      expect(scroll.offset, closeTo(before, 1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'selected local files and uploaded references remain with their chat draft',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await h.controller.openConversation(b);
      resumed(h, 'B');
      await tester.pumpAndSettle();
      h.controller.draft.files.add(
        const LocalAttachment(
          path: '/local.txt',
          name: 'local-draft.txt',
          size: 12,
          mimeType: 'text/plain',
        ),
      );
      h.controller.draft.uploaded.add(
        const MessageAttachment(
          name: 'remote-draft.txt',
          path: '/uploads/file.txt',
          mimeType: 'text/plain',
          size: 20,
        ),
      );
      h.controller.dismissError();
      await tester.pumpAndSettle();
      expect(find.text('local-draft.txt'), findsOneWidget);
      h.controller.newChat();
      await tester.pumpAndSettle();
      expect(find.text('local-draft.txt'), findsNothing);
      expect(h.controller.draft.uploaded, isEmpty);
      await h.controller.openConversation(b);
      resumed(h, 'B');
      await tester.pumpAndSettle();
      expect(find.text('local-draft.txt'), findsOneWidget);
      expect(find.text('remote-draft.txt'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'a delayed history response cannot replace a newly started external stream',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final history = Completer<http.Response>();
      h.override = (request) => request.url.path.contains('/B/messages')
          ? history.future
          : Future.value(h.response(request));
      final opening = h.controller.openConversation(b);
      await Future<void>.delayed(Duration.zero);
      started(h, 'B', 'external');
      delta(h, 'B', 'external', 'live tokens');
      history.complete(
        http.Response(
          '{"messages":[{"id":"old","role":"assistant","content":"stale snapshot"}]}',
          200,
        ),
      );
      await opening;
      expect(h.controller.timeline.messages.last.content, 'live tokens');
    },
  );
  test(
    'stale UI actions from A cannot stop or authorize B after switching',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final a = await startA(h);
      await h.controller.openConversation(b);
      resumed(h, 'B');
      h.controller.send('B task');
      started(h, 'B', 'run-B');
      h.transport.receive('approval.requested', {
        'session_id': 'B',
        'run_id': 'run-B',
        'approval_id': 'approval-B',
        'choices': ['once', 'deny'],
      });
      final before = h.transport.emitted.length;
      h.controller.stop(expectedSession: a.id);
      h.controller.respondToInteraction(
        'once',
        expectedSession: a.id,
        expectedInteraction: 'approval-A',
      );
      h.controller.respondToInteraction(
        'once',
        expectedSession: 'B',
        expectedInteraction: 'approval-A',
      );
      expect(h.transport.emitted.length, before);
      h.controller.respondToInteraction(
        'deny',
        expectedSession: 'B',
        expectedInteraction: 'approval-B',
      );
      expect(h.transport.emitted.last.$2['approval_id'], 'approval-B');
    },
  );
}
