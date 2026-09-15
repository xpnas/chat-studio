import 'package:chatstudio/state/chat_timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support.dart';

// Mirrors Studio v1.0.3 handle-bridge-run.ts: runMarker is cli_run_*,
// run_id is the bridge runtime ID, and output is the cumulative run text.
Map<String, dynamic> bridgeResume({bool complete = true}) => {
  'isWorking': true,
  'messages': <Map<String, dynamic>>[
    {'id': 'u', 'role': 'user', 'content': 'work'},
    {
      'id': 'a',
      'role': 'assistant',
      'runMarker': 'cli_run_fixture',
      'content': '已读取文件。正在分析。',
    },
  ],
  'events': [
    if (complete)
      {
        'event': 'run.started',
        'data': {'run_id': 'runtime-id'},
      },
    {
      'event': 'message.delta',
      'data': {
        'run_id': 'runtime-id',
        'delta': '正在分析。',
        'output': '已读取文件。正在分析。',
      },
    },
  ],
};

void main() {
  test('tool-only retained log reuses the verified local bridge prefix', () {
    final t = ChatTimeline()..apply('run.started', {'run_id': 'runtime-id'});
    t.apply('message.delta', {'run_id': 'runtime-id', 'delta': '已读取文件。'});
    final key = t.messages.last.renderKey;
    final data = bridgeResume(complete: false);
    data['events'] = [
      {
        'event': 'tool.started',
        'data': {
          'run_id': 'runtime-id',
          'tool_call_id': 'call',
          'tool_name': 'read_file',
        },
      },
    ];
    for (var i = 0; i < 3; i++) {
      t.resume(data);
      expect(t.messages.where((m) => m.role == 'assistant').length, 1);
      expect(t.displayMessages.last.content, '已读取文件。正在分析。');
      expect(t.messages.last.renderKey, key);
    }
  });

  test(
    'cold bridge tool-only replay resolves alias by user marker and tool ID',
    () {
      final data = bridgeResume(complete: false);
      (data['messages'] as List).first['runMarker'] = 'cli_run_fixture';
      (data['messages'] as List).last['tool_calls'] = [
        {
          'id': 'exact-call',
          'function': {'name': 'read_file'},
        },
      ];
      data['events'] = [
        {
          'event': 'tool.started',
          'data': {
            'run_id': 'runtime-id',
            'tool_call_id': 'exact-call',
            'tool_name': 'read_file',
          },
        },
      ];
      final t = ChatTimeline()..resume(data);
      t.apply('message.delta', {
        'run_id': 'runtime-id',
        'delta': '完成。',
        'output': '已读取文件。正在分析。完成。',
      });
      expect(t.messages.where((m) => m.role == 'assistant').length, 1);
      expect(t.displayMessages.last.content, '已读取文件。正在分析。完成。');
    },
  );

  for (final marker in ['cli_run_fixture', 'cli_resume_fixture']) {
    test('cold bridge recovery groups persisted tool steps ($marker)', () {
      final data = bridgeResume(complete: false);
      data['messages'] = [
        {'id': 'u', 'role': 'user', 'content': 'work', 'runMarker': marker},
        {
          'id': 'a1',
          'role': 'assistant',
          'runMarker': marker,
          'content': '已读取文件。',
          'finish_reason': 'stop',
        },
        {
          'id': 'a2',
          'role': 'assistant',
          'runMarker': marker,
          'content': '',
          'finish_reason': 'tool_calls',
          'tool_calls': [
            {
              'id': 'tool',
              'function': {'name': 'read_file'},
            },
          ],
        },
        {'id': 't', 'role': 'tool', 'content': 'done', 'runMarker': marker},
        {
          'id': 'a3',
          'role': 'assistant',
          'runMarker': marker,
          'content': '正在分析。',
          'finish_reason': 'stop',
        },
      ];
      final t = ChatTimeline();
      for (var i = 0; i < 3; i++) {
        t.resume(data);
        expect(t.messages.where((m) => m.role == 'assistant').length, 1);
        expect(t.displayMessages.last.content, '已读取文件。正在分析。');
        expect(
          t.messages.where((m) => m.role == 'assistant').single.tools.single.id,
          'tool',
        );
      }
    });
  }

  for (final beforeUser in [true, false]) {
    test(
      'finished bridge from another run is not consumed (beforeUser=$beforeUser)',
      () {
        final data = bridgeResume();
        final old = {
          'id': 'old',
          'role': 'assistant',
          'content': '已读取文件。正在分析。',
          'runMarker': 'cli_run_old',
          'finish_reason': 'stop',
        };
        final user = {
          'id': 'u',
          'role': 'user',
          'content': 'work',
          'runMarker': 'cli_run_new',
        };
        data['messages'] = beforeUser ? [old, user] : [user, old];
        final t = ChatTimeline()..resume(data);
        expect(t.messages.where((m) => m.role == 'assistant').length, 2);
        expect(
          t.messages.where((m) => m.id == 'old').single.runMarker,
          'cli_run_old',
        );
        expect(t.messages.last.runMarker, 'runtime-id');
      },
    );
  }

  test(
    'bridge interim output replaces streamed prefix, including on resume',
    () {
      final t = ChatTimeline()..apply('run.started', {'run_id': 'runtime-id'});
      t.apply('message.delta', {
        'run_id': 'runtime-id',
        'delta': 'draft',
        'output': 'draft',
      });
      t.apply('message.interim', {
        'run_id': 'runtime-id',
        'text': 'corrected',
        'output': 'corrected',
      });
      expect(t.messages.last.content, 'corrected');
      final data = bridgeResume(complete: false);
      (data['messages'] as List).last['content'] = 'corrected';
      data['events'] = [
        {
          'event': 'message.interim',
          'data': {
            'run_id': 'runtime-id',
            'text': 'corrected',
            'output': 'corrected',
          },
        },
      ];
      t.resume(data);
      expect(t.displayMessages.last.content, 'corrected');
      expect(t.messages.where((m) => m.role == 'assistant').length, 1);
    },
  );

  test('bridge text-based reasoning events are retained', () {
    final t = ChatTimeline()..apply('run.started', {'run_id': 'runtime-id'});
    t.apply('reasoning.delta', {'run_id': 'runtime-id', 'text': 'first'});
    t.apply('thinking.delta', {'run_id': 'runtime-id', 'text': 'second'});
    expect(t.messages.last.reasoning, 'firstsecond');
  });

  test(
    'multiple persisted prefixes merge with longer local cache before replay tail',
    () {
      final t = ChatTimeline()..apply('run.started', {'run_id': 'r'});
      t.apply('message.delta', {'run_id': 'r', 'delta': 'one.two.three.'});
      final data = {
        'isWorking': true,
        'messages': [
          {'id': 'u', 'role': 'user', 'content': 'work'},
          {
            'id': 'a1',
            'role': 'assistant',
            'run_marker': 'r',
            'content': 'one.',
            'finish_reason': 'tool_calls',
          },
          {
            'id': 'a2',
            'role': 'assistant',
            'run_marker': 'r',
            'content': 'two.',
            'finish_reason': 'tool_calls',
          },
        ],
        'events': [
          {
            'event': 'message.delta',
            'data': {'run_id': 'r', 'delta': 'three.four.'},
          },
        ],
      };
      for (var i = 0; i < 3; i++) {
        t.resume(data);
        expect(t.displayMessages.last.content, 'one.two.three.four.');
      }
    },
  );

  for (final complete in [true, false]) {
    test('bridge snapshot after socket loss does not duplicate its replay '
        '(complete=$complete)', () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      expect(h.controller.send('work'), true);
      final sid = h.controller.sessionId!;
      h.transport.receive('run.started', {
        'session_id': sid,
        'run_id': 'runtime-id',
      });
      h.transport.receive('message.delta', {
        'session_id': sid,
        'run_id': 'runtime-id',
        'delta': '已读取文件。',
        'output': '已读取文件。',
      });
      final key = h.controller.timeline.messages.last.renderKey;
      for (var i = 0; i < 3; i++) {
        h.controller.onBackground();
        h.transport.receive('disconnected', {});
        expect(h.controller.connected, false);
        h.controller.onForeground();
        h.transport.receive('connected', {});
        expect(h.controller.syncing, true);
        h.transport.receive('resumed', {
          ...bridgeResume(complete: complete),
          'session_id': sid,
        });
        expect(h.controller.syncing, false);
        final assistants = h.controller.timeline.messages.where(
          (m) => m.role == 'assistant',
        );
        expect(assistants.length, 1);
        expect(assistants.single.content, '已读取文件。正在分析。');
        expect(assistants.single.renderKey, key);
      }
      h.transport.receive('message.delta', {
        'session_id': sid,
        'run_id': 'runtime-id',
        'delta': '完成。',
        'output': '已读取文件。正在分析。完成。',
      });
      expect(
        h.controller.timeline.displayMessages.last.content,
        '已读取文件。正在分析。完成。',
      );
      expect(h.transport.emitted.where((e) => e.$1 == 'run').length, 1);
    });
  }

  test('merge known prefixes before a truncated tail, not after it', () {
    final t = ChatTimeline()..apply('run.started', {'run_id': 'r'});
    t.apply('message.delta', {'run_id': 'r', 'delta': '步骤一。步骤二。步骤三。'});
    t.apply('reasoning.delta', {'run_id': 'r', 'delta': '想一。想二。想三。'});
    final data = {
      'isWorking': true,
      'messages': [
        {'id': 'u', 'role': 'user', 'content': 'work'},
        {
          'id': 'a',
          'role': 'assistant',
          'run_marker': 'r',
          'content': '步骤一。',
          'reasoning': '想一。',
          'finish_reason': 'tool_calls',
        },
        {'id': 'tool', 'role': 'tool', 'content': 'done', 'run_marker': 'r'},
      ],
      'events': [
        {
          'event': 'message.delta',
          'data': {'run_id': 'r', 'delta': '步骤三。步骤四。'},
        },
        {
          'event': 'reasoning.delta',
          'data': {'run_id': 'r', 'delta': '想三。想四。'},
        },
      ],
    };
    for (var i = 0; i < 4; i++) {
      t.resume(data);
      expect(t.messages.last.content, '步骤一。步骤二。步骤三。步骤四。');
      expect(t.messages.last.reasoning, '想一。想二。想三。想四。');
    }
  });

  test(
    'bridge cumulative output is authoritative even when a delta repeats',
    () {
      final t = ChatTimeline()..apply('run.started', {'run_id': 'runtime-id'});
      final payload = {'run_id': 'runtime-id', 'delta': '哈哈', 'output': '哈哈'};
      t.apply('message.delta', payload);
      t.resume(bridgeResume());
      final next = {
        'run_id': 'runtime-id',
        'delta': '哈哈',
        'output': '已读取文件。正在分析。哈哈',
      };
      t.apply('message.delta', next);
      t.apply('message.delta', next);
      expect(t.displayMessages.last.content, '已读取文件。正在分析。哈哈');
      t.apply('message.delta', {...next, 'output': '已读取文件。正在分析。哈哈哈哈'});
      expect(t.displayMessages.last.content, '已读取文件。正在分析。哈哈哈哈');
    },
  );
}
