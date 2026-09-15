import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/state/chat_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> event(String name, Map<String, dynamic> data) => {
  'event': name,
  'data': {'run_id': 'current', ...data},
};

Map<String, dynamic> recovery(
  List<Map<String, dynamic>> events, {
  bool complete = true,
  List<Map<String, dynamic>> history = const [],
}) => {
  'isWorking': true,
  'messages': [
    ...history,
    {'id': 'user', 'role': 'user', 'content': 'current prompt'},
  ],
  'events': [if (complete) event('run.started', {}), ...events],
};

void main() {
  for (final kind in ['approval', 'clarify']) {
    for (final complete in [true, false]) {
      test('$kind remains actionable after live delivery and resume '
          '(complete=$complete)', () {
        final t = ChatTimeline()..apply('run.started', {'run_id': 'current'});
        final request = {
          'run_id': 'current',
          '${kind}_id': 'request',
          'remaining_timeout_ms': 60000,
          'choices': ['once', 'deny'],
        };
        t.apply('$kind.requested', request);
        t.interactionSubmitting = true;
        final data = recovery([
          event('$kind.requested', {...request, 'remaining_timeout_ms': 30000}),
        ], complete: complete);
        for (var i = 0; i < 3; i++) {
          t.resume(data);
          expect(t.interaction?['${kind}_id'], 'request');
          expect(t.interaction?['kind'], '$kind.requested');
          expect(t.interactionSubmitting, false);
          expect(t.interactionExpired, false);
          expect(t.canApprove('once'), true);
          expect(t.interactionDeadline, isNotNull);
          expect(
            t.interactionDeadline!.difference(DateTime.now()).inMilliseconds,
            inInclusiveRange(29000, 30000),
          );
        }
      });
    }

    test('$kind resolved in replay does not resurrect the live request', () {
      final t = ChatTimeline()..apply('run.started', {'run_id': 'current'});
      final request = {'${kind}_id': 'request', 'remaining_timeout_ms': 60000};
      t.apply('$kind.requested', {'run_id': 'current', ...request});
      final data = recovery([
        event('$kind.requested', request),
        event('$kind.resolved', {'${kind}_id': 'request', 'resolved': true}),
      ]);
      for (var i = 0; i < 3; i++) {
        t.resume(data);
        expect(t.interaction, isNull);
        expect(t.interactionDeadline, isNull);
        expect(t.canApprove('once'), false);
      }
    });

    test('$kind expired in authoritative resume is not kept locally', () {
      final t = ChatTimeline()..apply('run.started', {'run_id': 'current'});
      final request = {'${kind}_id': 'request', 'remaining_timeout_ms': 60000};
      t.apply('$kind.requested', {'run_id': 'current', ...request});
      t.resume(
        recovery([
          event('$kind.requested', {...request, 'remaining_timeout_ms': 0}),
        ]),
      );
      expect(t.interaction, isNull);
      expect(t.canApprove('once'), false);
    });
  }

  test(
    'already observed tool events rebuild status even without DB tool rows',
    () {
      final t = ChatTimeline()..apply('run.started', {'run_id': 'current'});
      final tool = {'tool_call_id': 'tool', 'tool_name': 'read_file'};
      t.apply('tool.started', {'run_id': 'current', ...tool});
      t.apply('tool.completed', {'run_id': 'current', ...tool});
      final key = t.messages.last.renderKey;
      final data = recovery([
        event('tool.started', tool),
        event('tool.completed', tool),
      ]);
      for (var i = 0; i < 3; i++) {
        t.resume(data);
        expect(t.messages.last.tools.single.id, 'tool');
        expect(t.messages.last.tools.single.status, 'done');
        expect(t.messages.last.renderKey, key);
      }
    },
  );

  test(
    'equal live and replay delta values retain their ordered multiplicity',
    () {
      final t = ChatTimeline()..apply('run.started', {'run_id': 'current'});
      t.apply('message.delta', {'run_id': 'current', 'delta': '哈'});
      final key = t.messages.last.renderKey;
      final data = recovery([
        event('message.delta', {'delta': '哈'}),
        event('message.delta', {'delta': '哈'}),
        event('message.delta', {'delta': '哈'}),
      ]);
      for (var i = 0; i < 3; i++) {
        t.resume(data);
        expect(t.messages.last.content, '哈哈哈');
        expect(t.messages.last.renderKey, key);
      }
      t.apply('message.delta', {'run_id': 'current', 'delta': '哈'});
      expect(t.messages.last.content, '哈哈哈哈');
    },
  );

  for (final pending in [true, false]) {
    test('an old ${pending ? 'pending' : 'completed'} run cannot supply '
        'the current body, reasoning or render key', () {
      for (final complete in [true, false]) {
        final t = ChatTimeline()
          ..runId = pending ? 'current' : null
          ..messages = [
            ChatMessage(
              id: 'old-assistant',
              role: 'assistant',
              content: 'old body',
              reasoning: 'old reasoning',
              pending: pending,
              runMarker: 'old',
              localKey: 'stream:old',
            ),
          ];
        t.resume(
          recovery(
            [
              event('message.delta', {'delta': 'new body'}),
              event('reasoning.delta', {'delta': 'new reasoning'}),
            ],
            complete: complete,
            history: [
              {
                'id': 'old-assistant',
                'role': 'assistant',
                'content': 'old body',
                'reasoning': 'old reasoning',
                'run_marker': 'old',
                'finish_reason': 'stop',
              },
            ],
          ),
        );
        expect(t.messages.first.content, 'old body');
        expect(t.messages.last.content, 'new body');
        expect(t.messages.last.reasoning, 'new reasoning');
        expect(t.messages.last.runMarker, 'current');
        expect(t.messages.last.renderKey, isNot('stream:old'));
        expect(
          t.messages.map((m) => m.renderKey).toSet().length,
          t.messages.length,
        );
      }
    });
  }

  test(
    'a pending message from another run is not prepended to an empty replay',
    () {
      final t = ChatTimeline()
        ..runId = 'old'
        ..messages = [
          const ChatMessage(
            id: 'old-assistant',
            role: 'assistant',
            content: 'old cached text',
            pending: true,
            runMarker: 'old',
          ),
        ];
      t.resume(recovery([]));
      expect(t.messages.where((m) => m.role == 'assistant'), isEmpty);
      expect(t.runId, 'current');
      expect(t.working, true);
    },
  );
}
