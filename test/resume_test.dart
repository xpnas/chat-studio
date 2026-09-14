import 'package:flutter_test/flutter_test.dart';
import 'package:ekko_app/state/chat_timeline.dart';
import 'package:ekko_app/data/chat_transport.dart';

void main() {
  test('Socket.IO recovery offset is not mistaken for the event payload', () {
    final payload = {'session_id': 's1', 'delta': '你好'};
    expect(decodeSocketPayload(payload), payload);
    expect(decodeSocketPayload([payload, 'recovery-offset']), payload);
    expect(decodeSocketPayload(null), isEmpty);
  });
  test('Hermes snapshot reuses partial bubble without duplicating replay', () {
    final timeline = ChatTimeline();
    timeline.resume({
      'isWorking': true,
      'messages': [
        {'id': 1, 'role': 'user', 'content': 'hello'},
        {
          'id': 2,
          'role': 'assistant',
          'content': '你好',
          'reasoning': '想',
          'runMarker': 'r1',
          'finish_reason': null,
        },
      ],
      'events': [
        {
          'event': 'run.started',
          'data': {'run_id': 'r1'},
        },
        {
          'event': 'reasoning.delta',
          'data': {'run_id': 'r1', 'delta': '想'},
        },
        {
          'event': 'message.delta',
          'data': {'run_id': 'r1', 'delta': '你好'},
        },
      ],
    });
    timeline.apply('message.delta', {'run_id': 'r1', 'delta': '！'});
    expect(timeline.messages.length, 2);
    expect(timeline.messages.last.content, '你好！');
    expect(timeline.messages.last.reasoning, '想');
    timeline.apply('run.completed', {'run_id': 'r1', 'output': '你好！'});
    timeline.apply('message.delta', {
      'run_id': 'r1',
      'delta': 'late duplicate',
    });
    expect(timeline.messages.length, 2);
    expect(timeline.working, false);
    expect(timeline.messages.last.content, '你好！');
  });
  test('completed previous assistant is not reused for new run', () {
    final timeline = ChatTimeline();
    timeline.resume({
      'isWorking': true,
      'messages': [
        {
          'id': 1,
          'role': 'assistant',
          'content': 'old',
          'finish_reason': 'stop',
          'runMarker': 'old',
        },
      ],
      'events': [
        {
          'event': 'run.started',
          'data': {'run_id': 'new'},
        },
        {
          'event': 'message.delta',
          'data': {'run_id': 'new', 'delta': 'new'},
        },
      ],
    });
    expect(timeline.messages.map((m) => m.content), ['old', 'new']);
  });
}
