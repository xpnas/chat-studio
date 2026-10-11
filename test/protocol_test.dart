import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/structured_interaction.dart';
import 'package:chatstudio/state/chat_timeline.dart';

void main() {
  group('Server address transport security', () {
    test('normalizes an HTTPS origin', () {
      expect(
        ServerAddress.parse(' https://example.com:8443/ ').value,
        'https://example.com:8443',
      );
    });
    for (final bad in [
      'ftp://example.com',
      'https://u:p@example.com',
      'https://example.com/api',
      'https://example.com?token=x',
      'https://example.com#x',
      'example.com',
      'http://example.com',
      'http://127.0.0.1',
    ]) {
      test('rejects $bad', () {
        expect(() => ServerAddress.parse(bad), throwsFormatException);
      });
    }
    for (final local in [
      '127.0.0.1',
      '10.0.2.2',
      '192.168.2.3',
      '172.16.0.1',
      '[::1]',
      '[fd00::1]',
      'studio.local',
    ]) {
      test('opt-in LAN $local', () {
        expect(
          ServerAddress.parse(
            'http://$local:8648',
            allowLocalHttp: true,
          ).uri.scheme,
          'http',
        );
      });
    }
    test('opt-in does not permit public HTTP', () {
      expect(
        () => ServerAddress.parse('http://8.8.8.8', allowLocalHttp: true),
        throwsFormatException,
      );
    });
  });
  test(
    'model parser uses configured groups, filters disabled and omits keys',
    () {
      final models = ModelChoice.parseGroups([
        {
          'provider': 'p',
          'label': 'Provider',
          'models': ['a', 'b'],
          'api_key': 'secret',
          'model_meta': {
            'a': {'alias': 'Friendly'},
            'b': {'disabled': true},
          },
        },
      ]);
      expect(models.single.label, 'Friendly');
      expect(models.single.key, 'p::a');
    },
  );
  test('history parses Unicode content blocks and display role', () {
    final m = ChatMessage.fromJson({
      'id': 2,
      'role': 'tool',
      'display_role': 'assistant',
      'display_content': '[{"type":"text","text":"你好 🌱"}]',
    });
    expect(m.visible, true);
    expect(m.content, '你好 🌱');
  });
  test('structured clarification parses Python repr and preserves answers', () {
    const raw =
        "[{'qid': 'q0', 'question': '多问题卡片渲染是否正常？', 'choices': ['正常 (Recommended)', '异常', '部分正常'], 'choices_offered': ['正常', '异常', '部分正常'], 'multi_select': False}, {'qid': 'q1', 'question': '这是第二个问题（单选 + 推荐项）', 'choices': ['选项 A（推荐） (Recommended)', '选项 B'], 'choices_offered': ['选项 A（推荐）', '选项 B'], 'multi_select': False}, {'qid': 'q2', 'question': '这是第三个问题（多选）', 'choices': ['标签一 (Recommended)', '标签二'], 'choices_offered': ['标签一', '标签二'], 'multi_select': True}, {'qid': 'q3', 'question': '这是第四个问题（开放输入，无选项）', 'choices': None, 'choices_offered': None, 'multi_select': False}]";
    final set = StructuredQuestionSet.parse(raw);
    expect(set, isNotNull);
    expect(set!.questions, hasLength(4));
    expect(set.questions[0].choices.first.label, '正常');
    expect(set.questions[0].choices.first.recommended, true);
    expect(set.questions[1].choices.first.label, '选项 A');
    expect(set.questions[2].multiSelect, true);
    expect(set.questions[3].isOpen, true);

    final response =
        jsonDecode(
              set.encodeResponses({
                'q0': '正常 (Recommended)',
                'q1': '选项 A（推荐） (Recommended)',
                'q2': ['标签一 (Recommended)', '标签二'],
                'q3': '继续执行',
              }),
            )
            as Map<String, dynamic>;
    expect((response['responses'] as List), hasLength(4));
    expect((response['responses'] as List)[2]['answers'], [
      '标签一 (Recommended)',
      '标签二',
    ]);
  });
  test(
    'structured clarification ignores ordinary text and accepts JSON arrays',
    () {
      expect(StructuredQuestionSet.parse('普通澄清问题'), isNull);
      final set = StructuredQuestionSet.parse([
        {
          'qid': 'q0',
          'question': '选择',
          'choices': ['A'],
          'choices_offered': ['A'],
          'multi_select': false,
        },
      ]);
      expect(set?.questions.single.id, 'q0');
      expect(
        StructuredQuestionSet.parse({
          'questions': [
            {
              'qid': 'nested',
              'question': '嵌套结构',
              'choices': ['可以'],
            },
          ],
        })?.questions.single.id,
        'nested',
      );
    },
  );
  group('streaming reducer', () {
    late ChatTimeline timeline;
    setUp(() {
      timeline = ChatTimeline();
      timeline.begin('hello', 'u1');
    });
    test('deltas append once; completion is authoritative', () {
      timeline.apply('run.started', {'run_id': 'r1'});
      timeline.apply('message.delta', {'run_id': 'r1', 'delta': '你'});
      timeline.apply('message.delta', {'run_id': 'r1', 'delta': '好'});
      expect(timeline.messages.last.content, '你好');
      timeline.apply('run.completed', {
        'run_id': 'r1',
        'output': '你好！',
        'message_id': 9,
      });
      expect(timeline.messages.length, 2);
      expect(timeline.messages.last.content, '你好！');
      expect(timeline.messages.last.id, '9');
      expect(timeline.working, false);
    });
    test('ignores events from another run', () {
      timeline.apply('run.started', {'run_id': 'r1'});
      timeline.apply('message.delta', {'run_id': 'old', 'delta': 'incorrect'});
      expect(timeline.messages.length, 1);
    });
    test('abort settles pending bubbles', () {
      timeline.apply('message.delta', {'delta': 'partial'});
      timeline.apply('abort.completed', {});
      expect(timeline.working, false);
      expect(timeline.messages.any((m) => m.pending), false);
    });
    test('resume replaces optimistic state, replays only current run', () {
      timeline.resume({
        'messages': [
          {'id': 1, 'role': 'user', 'content': 'question'},
        ],
        'isWorking': true,
        'events': [
          {
            'event': 'run.started',
            'data': {'run_id': 'r0'},
          },
          {
            'event': 'message.delta',
            'data': {'run_id': 'r0', 'delta': 'old'},
          },
          {
            'event': 'run.started',
            'data': {'run_id': 'r1'},
          },
          {
            'event': 'message.delta',
            'data': {'run_id': 'r1', 'delta': 'new'},
          },
        ],
      });
      expect(timeline.messages.length, 2);
      expect(timeline.messages.last.content, 'new');
    });
    test('expired approval never becomes actionable', () {
      timeline.apply('approval.requested', {
        'approval_id': 'a',
        'remaining_timeout_ms': 0,
      });
      expect(timeline.interaction, isNull);
    });
    test('prepend deduplicates overlap', () {
      timeline.replace([
        const ChatMessage(id: '2', role: 'user', content: 'b'),
      ]);
      timeline.prepend([
        const ChatMessage(id: '1', role: 'assistant', content: 'a'),
        const ChatMessage(id: '2', role: 'user', content: 'b'),
      ]);
      expect(timeline.messages.map((m) => m.id), ['1', '2']);
    });
  });
}
