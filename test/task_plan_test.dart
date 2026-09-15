import 'dart:convert';
import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/data/task_plan.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/state/chat_timeline.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'package:chatstudio/ui/widgets/task_plan_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'support.dart';

Map<String, dynamic> planJson({
  int revision = 1,
  String session = 's1',
  String run = 'r1',
  String id = 'p1',
  String state = 'running',
  bool complete = false,
}) => {
  'session_id': session,
  'run_id': run,
  'plan_id': id,
  'revision': revision,
  'execution_state': state,
  'created_at': 2000,
  'updated_at': 2000 + revision,
  'explanation': '按步骤验证后再交付',
  'plan': [
    {'id': 'inspect', 'step': '分析接口', 'status': 'completed'},
    {
      'id': 'build',
      'step': '实现并验证移动端',
      'status': complete ? 'completed' : 'in_progress',
    },
    {
      'id': 'test',
      'step': '执行回归测试',
      'status': complete ? 'completed' : 'pending',
    },
  ],
};

void main() {
  test('strict snapshot parsing rejects malformed or ambiguous progress', () {
    final valid = planJson();
    expect(TaskPlan.parse(valid)!.completed, 1);
    expect(TaskPlan.parse(valid)!.currentStep!.title, '实现并验证移动端');
    for (final raw in [
      null,
      [],
      {},
      {...valid, 'revision': 0},
      {...valid, 'revision': 1.5},
      {...valid, 'revision': double.infinity},
      {...valid, 'created_at': '2000'},
      {...valid, 'updated_at': double.nan},
      {...valid, 'session_id': ' '},
      {...valid, 'execution_state': 'success'},
      {...valid, 'explanation': 42},
      {...valid, 'explanation': 'x' * 1001},
      {...valid, 'plan': []},
      {...valid, 'plan': List.filled(31, (valid['plan'] as List).first)},
      {
        ...valid,
        'plan': [
          {'id': 'x', 'step': 'task', 'status': 'done'},
        ],
      },
      {
        ...valid,
        'plan': [
          {'id': 'x', 'step': 'x' * 201, 'status': 'pending'},
        ],
      },
      {...valid, 'plan': List.filled(2, (valid['plan'] as List).first)},
    ]) {
      expect(TaskPlan.parse(raw), isNull, reason: '$raw');
    }
  });

  test(
    'revision merging deduplicates replay and rejects wrong session/run',
    () {
      final t = ChatTimeline()..sessionId = 's1';
      expect(t.apply('plan.updated', planJson(revision: 3)), true);
      expect(t.apply('plan.updated', planJson(revision: 2)), false);
      expect(t.apply('plan.updated', planJson(revision: 3)), false);
      expect(
        t.apply('plan.updated', planJson(revision: 4, session: 's2')),
        false,
      );
      expect(
        t.apply('plan.updated', planJson(revision: 4, run: 'other')),
        false,
      );
      expect(t.messages, isEmpty);
      expect(t.displayMessages.single.taskPlan!.revision, 3);
      expect(
        t.working,
        false,
        reason: 'plans must not fabricate a running chat',
      );
    },
  );

  test('rebinding a timeline cannot leak plan state across sessions', () {
    final t = ChatTimeline()..sessionId = 's1';
    t.apply('plan.updated', planJson());
    t.sessionId = 's2';
    expect(t.taskPlans, isEmpty);
    expect(t.apply('plan.updated', planJson()), false);
    expect(t.apply('plan.updated', planJson(session: 's2')), true);
    t.sessionId = null;
    expect(t.taskPlans, isEmpty);
  });

  test(
    'multiple plans for one run keep deterministic order on every render',
    () {
      final t = ChatTimeline()..sessionId = 's1';
      t.replace(const [
        ChatMessage(
          id: 'a',
          role: 'assistant',
          content: 'body',
          runMarker: 'r1',
        ),
      ]);
      t.apply('plan.updated', planJson(id: 'p2'));
      t.apply('plan.updated', planJson());
      for (var i = 0; i < 3; i++) {
        expect(t.displayMessages.map((m) => m.id), [
          'task-plan:s1:p1',
          'task-plan:s1:p2',
          'a',
        ]);
      }
    },
  );

  test(
    'display card sits before its run without polluting message pagination',
    () {
      final t = ChatTimeline()..sessionId = 's1';
      t.replace([
        const ChatMessage(id: 'u', role: 'user', content: 'request'),
        const ChatMessage(
          id: 'a',
          role: 'assistant',
          content: 'part one',
          runMarker: 'r1',
        ),
        const ChatMessage(
          id: 'b',
          role: 'assistant',
          content: 'part two',
          runMarker: 'r1',
        ),
      ]);
      t.apply('plan.updated', planJson());
      expect(t.messages.length, 3);
      expect(t.displayMessages.map((m) => m.id), ['u', 'task-plan:s1:p1', 'a']);
      expect(t.displayMessages.last.content, 'part one\n\npart two');
      t.prepend([const ChatMessage(id: 'old', role: 'user', content: 'old')]);
      t.mergeTaskPlans([TaskPlan.parse(planJson(revision: 2))!]);
      expect(t.displayMessages.where((m) => m.taskPlan != null).length, 1);
    },
  );

  test(
    'timestamps place plans even without a matching persisted run marker',
    () {
      final t = ChatTimeline()..sessionId = 's1';
      t.replace([
        ChatMessage.fromJson({
          'id': 'u',
          'role': 'user',
          'content': 'q',
          'timestamp': 1,
        }),
        ChatMessage.fromJson({
          'id': 'a',
          'role': 'assistant',
          'content': 'a',
          'timestamp': 3,
        }),
      ]);
      t.apply('plan.updated', planJson());
      expect(t.displayMessages.map((m) => m.id), ['u', 'task-plan:s1:p1', 'a']);
    },
  );

  test('terminal receipt stops activity but never checks unfinished steps', () {
    for (final pair in [
      ('run.completed', 'ended'),
      ('run.failed', 'failed'),
      ('abort.completed', 'interrupted'),
    ]) {
      final t = ChatTimeline()..sessionId = 's1';
      t.apply('run.started', {'run_id': 'r1'});
      t.apply('plan.updated', planJson());
      t.apply(pair.$1, {'run_id': 'r1'});
      expect(t.taskPlans.single.executionState, pair.$2);
      expect(t.taskPlans.single.completed, 1);
      expect(t.taskPlans.single.currentStep, isNull);
      expect(t.taskPlans.single.revision, 1);
      // The final snapshot is allowed AFTER the run has entered finishedRuns.
      expect(
        t.apply('plan.updated', planJson(revision: 2, state: pair.$2)),
        true,
      );
      expect(t.taskPlans.single.revision, 2);
      expect(t.taskPlans.single.stateLabel, contains('剩余步骤未完成'));
    }
  });

  test('delayed previous-run plan does not mutate current stream or text', () {
    final t = ChatTimeline()..sessionId = 's1';
    t.apply('run.started', {'run_id': 'r2'});
    t.apply('message.delta', {'run_id': 'r2', 'delta': '当前正文'});
    t.apply('plan.updated', planJson(revision: 3, state: 'ended'));
    expect(t.runId, 'r2');
    expect(t.messages.single.content, '当前正文');
    expect(t.taskPlans.single.runId, 'r1');
  });

  test(
    'resume merges authoritative snapshots and all retained plan events once',
    () {
      final t = ChatTimeline()..sessionId = 's1';
      t.apply('plan.updated', planJson(revision: 5));
      final response = {
        'isWorking': false,
        'messages': [
          {
            'id': 'a',
            'role': 'assistant',
            'content': '最终正文',
            'run_marker': 'r1',
          },
        ],
        'taskPlans': [planJson(revision: 3), planJson(session: 'other')],
        'events': [
          {
            'event': 'plan.updated',
            'data': planJson(revision: 6, state: 'ended', complete: true),
          },
          {
            'event': 'run.started',
            'data': {'run_id': 'r2'},
          },
          {'event': 'plan.updated', 'data': planJson(id: 'p2', run: 'r2')},
          {
            'event': 'run.failed',
            'data': {'run_id': 'r2'},
          },
        ],
      };
      for (var i = 0; i < 3; i++) {
        t.resume(response);
      }
      expect(t.taskPlans.length, 2);
      expect(t.taskPlans.first.revision, 6);
      expect(t.taskPlans.first.isComplete, true);
      expect(t.taskPlans.last.executionState, 'failed');
      expect(t.messages.single.content, '最终正文');
      expect(t.displayMessages.where((m) => m.taskPlan != null).length, 2);
    },
  );

  test('snapshot restores a plan when all plan events were truncated', () {
    final t = ChatTimeline()..sessionId = 's1';
    t.resume({
      'isWorking': true,
      'taskPlans': [planJson(revision: 10)],
      'events': [
        {
          'event': 'message.delta',
          'data': {'run_id': 'r1', 'delta': '正文'},
        },
      ],
      'messages': [],
    });
    expect(t.taskPlans.single.revision, 10);
    expect(t.displayMessages.first.taskPlan, isNotNull);
    expect(t.messages.last.content, '正文');
  });

  test('display clear and session reset remove plans', () {
    final t = ChatTimeline()..sessionId = 's1';
    t.apply('plan.updated', planJson());
    t.apply('session.command', {
      'action': 'clear',
      'command': 'clear',
      'ok': true,
    });
    expect(t.taskPlans, isEmpty);
    t.apply('plan.updated', planJson());
    t.clear();
    expect(t.displayMessages, isEmpty);
  });

  test(
    'REST plan metadata does not change raw offsets and rejects other sessions',
    () async {
      final api = StudioApi(
        ServerAddress.parse('https://example.com'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'messages': [
                {'id': 'tool', 'role': 'tool', 'content': 'hidden'},
              ],
              'taskPlans': [
                planJson(),
                planJson(session: 'other'),
                {'broken': true},
              ],
              'offset': 60,
              'total': 100,
              'hasMore': true,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(api.close);
      final page = await api.messages('s1', offset: 60);
      expect(page.offset, 61);
      expect(page.messages.length, 1);
      expect(page.taskPlans.single.sessionId, 's1');
    },
  );

  test('controller routes background plan to its own conversation', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    await h.controller.openConversation(
      const Conversation(id: 's1', title: 'one'),
    );
    h.transport.receive('resumed', {
      'session_id': 's1',
      'isWorking': false,
      'messages': [],
    });
    h.transport.receive('plan.updated', planJson());
    await h.controller.openConversation(
      const Conversation(id: 's2', title: 'two'),
    );
    h.transport.receive('resumed', {
      'session_id': 's2',
      'isWorking': false,
      'messages': [],
    });
    h.transport.receive(
      'plan.updated',
      planJson(revision: 2, complete: true, state: 'ended'),
    );
    expect(h.controller.timeline.taskPlans, isEmpty);
    await h.controller.openConversation(
      const Conversation(id: 's1', title: 'one'),
    );
    expect(h.controller.timeline.taskPlans.single.revision, 2);
    h.transport.receive('plan.updated', {
      ...planJson(revision: 3),
      'profile': 'other-profile',
    });
    expect(h.controller.timeline.taskPlans.single.revision, 2);
    await h.controller.addServer();
    expect(h.controller.timeline.taskPlans, isEmpty);
  });

  Future<void> pumpCard(
    WidgetTester tester,
    TaskPlan plan, {
    double width = 390,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: MessageBubble(
                message: ChatMessage(
                  id: plan.key,
                  role: 'system',
                  content: '',
                  taskPlan: plan,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('compact card shows count and current step without an avatar', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpCard(tester, TaskPlan.parse(planJson())!);
    expect(find.text('任务计划'), findsOneWidget);
    expect(find.text('1/3 已完成'), findsOneWidget);
    expect(find.text('进行中 · 实现并验证移动端'), findsOneWidget);
    expect(find.text('执行回归测试'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('任务计划'));
    await tester.pumpAndSettle();
    expect(find.text('执行回归测试'), findsOneWidget);
    await pumpCard(
      tester,
      TaskPlan.parse(planJson(revision: 2, complete: true, state: 'ended'))!,
    );
    expect(find.text('3/3 已完成'), findsOneWidget);
    expect(
      find.text('执行回归测试'),
      findsOneWidget,
      reason: 'expansion survives progress updates',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen and large text keep plan controls usable', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpCard(
      tester,
      TaskPlan.parse(planJson(state: 'interrupted'))!,
      width: 320,
      scale: 1.8,
    );
    expect(find.text('已中断，剩余步骤未完成'), findsOneWidget);
    await tester.tap(find.text('任务计划'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('未完成'), findsNWidgets(2));
  });

  testWidgets('plan-only history renders the card instead of welcome screen', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    h.controller.sessionId = 's1';
    h.controller.timeline.apply('plan.updated', planJson());
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TaskPlanCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
