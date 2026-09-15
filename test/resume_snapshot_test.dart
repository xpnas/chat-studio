import 'package:flutter_test/flutter_test.dart';
import 'package:ekko_app/state/chat_timeline.dart';
import 'package:ekko_app/data/models.dart';

Map<String, dynamic> snapshot({
  String text = '明白，我会修复。',
  String replay = '明白，我会修复。',
  bool tool = true,
}) => {
  'isWorking': true,
  'messages': <Map<String, dynamic>>[
    {'id': 'u', 'role': 'user', 'content': 'fix'},
    {
      'id': 'a',
      'role': 'assistant',
      'content': text,
      'run_marker': 'r',
      'finish_reason': 'tool_calls',
      'tool_calls': [
        {
          'id': 't',
          'function': {'name': 'test'},
        },
      ],
    },
    if (tool) {'id': 't', 'role': 'tool', 'content': 'done', 'run_marker': 'r'},
  ],
  'events': [
    {
      'event': 'run.started',
      'data': {'run_id': 'r'},
    },
    {
      'event': 'message.delta',
      'data': {'run_id': 'r', 'delta': replay},
    },
    {
      'event': 'tool.started',
      'data': {'run_id': 'r', 'tool_call_id': 't', 'tool_name': 'test'},
    },
    {
      'event': 'tool.completed',
      'data': {'run_id': 'r', 'tool_call_id': 't', 'tool_name': 'test'},
    },
  ],
};
void main() {
  test(
    'screenshot case: persisted assistant before tool row plus replay is rendered once',
    () {
      final t = ChatTimeline()..resume(snapshot());
      expect(t.displayMessages.last.content, '明白，我会修复。');
      expect(t.messages.where((m) => m.role == 'assistant').length, 1);
      expect(t.messages.last.tools.single.status, 'done');
      t.apply('message.delta', {'run_id': 'r', 'delta': '继续。'});
      expect(t.displayMessages.last.content, '明白，我会修复。继续。');
    },
  );
  test(
    'cached stream retains key through repeated full snapshots and longer replay',
    () {
      final t = ChatTimeline()..begin('fix', 'local:u');
      t.apply('run.started', {'run_id': 'r'});
      t.apply('message.delta', {'run_id': 'r', 'delta': '明白，我会修复。'});
      final key = t.messages.last.renderKey;
      for (var i = 0; i < 5; i++) {
        t.resume(snapshot(replay: '明白，我会修复。继续。'));
        expect(t.displayMessages.last.content, '明白，我会修复。继续。');
        expect(t.messages.last.renderKey, key);
      }
      t.apply('run.completed', {'run_id': 'r', 'output': '明白，我会修复。继续。'});
      t.replace([
        const ChatMessage(id: 'u', role: 'user', content: 'fix'),
        ChatMessage.fromJson({
          'id': 'db',
          'role': 'assistant',
          'content': '明白，我会修复。继续。',
          'run_marker': 'r',
        }),
      ]);
      expect(t.messages.last.renderKey, key);
    },
  );
  test(
    'snapshot without marker does not duplicate exact prefix from replay',
    () {
      final data = snapshot(tool: false);
      (data['messages'] as List).last.remove('run_marker');
      (data['messages'] as List).last.remove('finish_reason');
      final t = ChatTimeline()..resume(data);
      expect(t.displayMessages.last.content, '明白，我会修复。');
    },
  );
  test(
    'repeated words in real delta and same text in different turns are preserved',
    () {
      final t = ChatTimeline()..resume(snapshot(text: '哈哈', replay: '哈哈哈哈'));
      expect(t.displayMessages.last.content, '哈哈哈哈');
      t.apply('message.delta', {'run_id': 'r', 'delta': '哈哈'});
      expect(t.displayMessages.last.content, '哈哈哈哈哈哈');
      final data = snapshot();
      (data['messages'] as List).insertAll(0, <Map<String, dynamic>>[
        {'id': 'old-u', 'role': 'user', 'content': 'old'},
        {
          'id': 'old-a',
          'role': 'assistant',
          'content': '明白，我会修复。',
          'run_marker': 'old',
          'finish_reason': 'stop',
        },
      ]);
      t.resume(data);
      expect(t.messages.where((m) => m.content == '明白，我会修复。').length, 2);
    },
  );
  test(
    'no replay delta still reuses current run snapshot for subsequent live delta',
    () {
      final data = snapshot();
      (data['events'] as List).removeAt(1);
      final t = ChatTimeline()..resume(data);
      t.apply('message.delta', {'run_id': 'r', 'delta': '继续'});
      expect(t.displayMessages.last.content, '明白，我会修复。继续');
    },
  );
}
