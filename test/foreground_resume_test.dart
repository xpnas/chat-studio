import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/state/chat_timeline.dart';
import 'package:chatstudio/state/resume_text.dart';
import 'support.dart';

Map<String, dynamic> tailSnapshot(
  String suffix, {
  String? persisted,
  String? reasoning,
}) => {
  'isWorking': true,
  'messages': [
    {'id': 'u', 'role': 'user', 'content': 'work'},
    if (persisted != null)
      {
        'id': 'a',
        'role': 'assistant',
        'run_marker': 'r',
        'content': persisted,
        'finish_reason': 'tool_calls',
      },
    if (persisted != null)
      {'id': 't', 'role': 'tool', 'run_marker': 'r', 'content': 'result'},
  ],
  // No run.started: oldest event has been evicted from 200-event server log.
  'events': <Map<String, dynamic>>[
    if (reasoning != null)
      {
        'event': 'reasoning.delta',
        'data': {'run_id': 'r', 'delta': reasoning},
      },
    {
      'event': 'message.delta',
      'data': {'run_id': 'r', 'delta': suffix},
    },
  ],
};
void main() {
  test(
    'truncated replay overlapping a tool-step snapshot appends only unseen suffix',
    () {
      final t = ChatTimeline()
        ..resume(tailSnapshot('步骤二。步骤三。', persisted: '步骤一。步骤二。'));
      expect(t.displayMessages.last.content, '步骤一。步骤二。步骤三。');
      t.apply('message.delta', {'run_id': 'r', 'delta': '结束。'});
      expect(t.displayMessages.last.content, '步骤一。步骤二。步骤三。结束。');
    },
  );
  test(
    'foreground preserves local prefix when only tail events remain, body and reasoning',
    () {
      final t = ChatTimeline()..begin('work', 'local:u');
      t.apply('run.started', {'run_id': 'r'});
      t.apply('message.delta', {'run_id': 'r', 'delta': '前缀。中间。尾部。'});
      t.apply('reasoning.delta', {'run_id': 'r', 'delta': '思考一。思考二。'});
      final key = t.messages.last.renderKey;
      for (var i = 0; i < 6; i++) {
        t.resume(tailSnapshot('中间。尾部。新增。', reasoning: '思考二。思考三。'));
        expect(t.messages.last.content, '前缀。中间。尾部。新增。');
        expect(t.messages.last.reasoning, '思考一。思考二。思考三。');
        expect(t.messages.last.renderKey, key);
      }
    },
  );
  test(
    'authoritative full replay is not joined twice on whitespace differences',
    () {
      final data = tailSnapshot('一。\n二。', persisted: '一。\n\n二。');
      (data['events'] as List).insert(0, <String, dynamic>{
        'event': 'run.started',
        'data': {'run_id': 'r'},
      });
      final t = ChatTimeline()..resume(data);
      expect(t.messages.last.content, '一。\n二。');
    },
  );
  test('late working snapshot never resurrects completed run', () {
    final t = ChatTimeline()..begin('work', 'local:u');
    t.apply('run.started', {'run_id': 'r'});
    t.apply('message.delta', {'run_id': 'r', 'delta': '最终正文。'});
    t.apply('run.completed', {'run_id': 'r', 'output': '最终正文。'});
    final key = t.messages.last.renderKey;
    t.resume(tailSnapshot('正文。'));
    expect(t.working, false);
    expect(t.messages.last.content, '最终正文。');
    expect(t.messages.last.renderKey, key);
    t.apply('message.delta', {'run_id': 'r', 'delta': '正文。'});
    expect(t.messages.last.content, '最终正文。');
  });
  test('normal live repetitions and different runs are never deduplicated', () {
    final t = ChatTimeline()..begin('work', 'local:u');
    t.apply('run.started', {'run_id': 'r'});
    t.apply('message.delta', {'run_id': 'r', 'delta': '哈哈'});
    t.apply('message.delta', {'run_id': 'r', 'delta': '哈哈'});
    expect(t.messages.last.content, '哈哈哈哈');
    expect(
      reconcileResumeText('ABCXYZ', 'XYZ123', completeReplay: false),
      'ABCXYZ123',
    );
    expect(
      reconcileResumeText('ABAB', 'ABABX', completeReplay: false),
      'ABABX',
    );
  });
  test(
    'background foreground controller recovers tail without resending input',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.send('work');
      final sid = h.controller.sessionId!;
      h.transport.receive('run.started', {'session_id': sid, 'run_id': 'r'});
      h.transport.receive('message.delta', {
        'session_id': sid,
        'run_id': 'r',
        'delta': '开头。中段。',
      });
      h.controller.onBackground();
      h.controller.onForeground();
      expect(h.transport.emitted.last.$1, 'resume');
      h.transport.receive('message.delta', {
        'session_id': sid,
        'run_id': 'r',
        'delta': '末段。',
      });
      h.transport.receive('resumed', {
        ...tailSnapshot('中段。末段。'),
        'session_id': sid,
      });
      expect(h.controller.timeline.messages.last.content, '开头。中段。末段。');
      expect(h.transport.emitted.where((e) => e.$1 == 'run').length, 1);
    },
  );
  test(
    'foreground rebuilds a transport that was disconnected while backgrounded',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final initialConnections = h.transport.connections;

      h.transport.receive('disconnected', {});
      expect(h.controller.connected, false);
      h.controller.onForeground();

      expect(h.transport.connections, initialConnections + 1);
    },
  );
  test(
    'network reconnect buffered deltas are not replayed twice by resume',
    () {
      final t = ChatTimeline()..begin('work', 'local:u');
      t.apply('run.started', {'run_id': 'r'});
      t.apply('message.delta', {'run_id': 'r', 'delta': '前半。'});
      t.apply('message.delta', {'run_id': 'r', 'delta': '中段。'});
      t.resume({
        'isWorking': true,
        'messages': [
          {'id': 'u', 'role': 'user', 'content': 'work'},
          {
            'id': 'a',
            'role': 'assistant',
            'content': '前半。中段。',
            'run_marker': 'r',
            'finish_reason': null,
          },
        ],
        'events': [
          {
            'event': 'run.started',
            'data': {'run_id': 'r'},
          },
          {
            'event': 'message.delta',
            'data': {'run_id': 'r', 'delta': '前半。'},
          },
          {
            'event': 'message.delta',
            'data': {'run_id': 'r', 'delta': '中段。'},
          },
          {
            'event': 'message.delta',
            'data': {'run_id': 'r', 'delta': '后半。'},
          },
        ],
      });
      expect(t.displayMessages.last.content, '前半。中段。后半。');
      expect(t.messages.last.content.contains('前半。中段。前半。'), false);
      t.apply('message.delta', {'run_id': 'r', 'delta': '结束。'});
      expect(t.messages.last.content, '前半。中段。后半。结束。');
    },
  );
}
