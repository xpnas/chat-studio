import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ekko_app/main.dart';
import 'package:ekko_app/data/speech_playback.dart';
import 'support.dart';

Map<String, dynamic> approval(String? sid, {bool permanent = true}) => {
  'session_id': sid,
  'approval_id': 'a',
  'choices': ['once', 'always', 'deny'],
  'allow_permanent': permanent,
  'description': 'Test tool',
  'remaining_timeout_ms': 1000,
};
void main() {
  testWidgets(
    'failed receipt retains card, duplicate submission blocked, stale clears',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.controller.send('work');
      final sid = h.controller.sessionId;
      h.transport.receive('approval.requested', approval(sid));
      h.controller.respondToInteraction('once');
      final count = h.transport.emitted.length;
      h.controller.respondToInteraction('deny');
      expect(h.transport.emitted.length, count);
      h.transport.receive('approval.resolved', {
        'session_id': sid,
        'approval_id': 'a',
        'resolved': false,
        'error': 'Denied by server',
      });
      expect(h.controller.timeline.interaction, isNotNull);
      expect(h.controller.timeline.interactionSubmitting, false);
      expect(h.controller.timeline.interactionError, 'Denied by server');
      h.transport.receive('approval.resolved', {
        'session_id': sid,
        'approval_id': 'other',
        'resolved': true,
      });
      expect(h.controller.timeline.interaction, isNotNull);
      h.transport.receive('approval.resolved', {
        'session_id': sid,
        'approval_id': 'a',
        'resolved': false,
        'stale': true,
      });
      expect(h.controller.timeline.interaction, isNull);
      h.dispose();
    },
  );
  testWidgets(
    'permanent requires server permission, explicit confirmation, and valid lifetime',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.controller.send('work');
      final sid = h.controller.sessionId;
      h.transport.receive(
        'approval.requested',
        approval(sid, permanent: false),
      );
      final n = h.transport.emitted.length;
      h.controller.respondToInteraction('always');
      expect(h.transport.emitted.length, n);
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await tester.pump();
      expect(find.text('永久允许'), findsNothing);
      h.transport.receive('approval.resolved', {
        'session_id': sid,
        'approval_id': 'a',
        'resolved': true,
      });
      h.transport.receive('approval.requested', {
        ...approval(sid),
        'remaining_timeout_ms': 60000,
      });
      await tester.pump();
      await tester.tap(find.text('永久允许'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('确认永久授权？'), findsOneWidget);
      expect(h.transport.emitted.length, n);
      await tester.tap(find.widgetWithText(FilledButton, '永久允许'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(h.transport.emitted.last.$2['choice'], 'always');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'expired approval never sends and duplicate request cannot extend expiry',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.controller.send('work');
      h.transport.receive(
        'approval.requested',
        {
          ...approval(h.controller.sessionId),
          'requested_at': DateTime.now().millisecondsSinceEpoch - 5000,
          'timeout_ms': 1,
        }..remove('remaining_timeout_ms'),
      );
      await tester.pump();
      final n = h.transport.emitted.length;
      h.transport.receive(
        'approval.requested',
        approval(h.controller.sessionId),
      );
      h.controller.respondToInteraction('always');
      expect(h.transport.emitted.length, n);
      h.dispose();
    },
  );
  test(
    'new session ignores pre-start snapshot and old activity without premature resume',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final stamp = DateTime.now().millisecondsSinceEpoch - 100;
      h.controller.send('first');
      final sid = h.controller.sessionId;
      final n = h.transport.emitted.length;
      h.transport.receive('session.activity.snapshot', {
        'timestamp': stamp,
        'sessions': [],
      });
      h.transport.receive('session.activity', {
        'session_id': sid,
        'timestamp': stamp,
        'status': 'failed',
      });
      expect(h.transport.emitted.length, n);
      expect(h.controller.syncing, false);
      h.transport.receive('run.started', {
        'session_id': sid,
        'run_id': 'first',
      });
      expect(h.controller.canQueue, true);
      expect(h.controller.error, isNull);
    },
  );
  test(
    'queue is server-authoritative, cancellation and dequeue preserve active response',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.send('one');
      final sid = h.controller.sessionId;
      expect(h.controller.send('too early'), false);
      h.transport.receive('run.started', {'session_id': sid, 'run_id': 'r1'});
      h.transport.receive('message.delta', {
        'session_id': sid,
        'run_id': 'r1',
        'delta': 'answer',
      });
      expect(h.controller.send('two'), true);
      final qid = h.transport.emitted.last.$2['queue_id'];
      expect(h.controller.timeline.queue.single.status, 'sending');
      expect(h.controller.timeline.messages.last.content, 'answer');
      h.transport.receive('run.queued', {
        'session_id': sid,
        'queue_length': 1,
        'queued_messages': [
          {'id': qid, 'content': 'two'},
        ],
      });
      h.controller.cancelQueued(qid, expectedSession: sid!);
      expect(h.transport.emitted.last.$1, 'cancel_queued_run');
      expect(h.controller.timeline.queue.length, 1);
      h.transport.receive('run.completed', {
        'session_id': sid,
        'run_id': 'r1',
        'queue_remaining': 1,
      });
      h.transport.receive('run.queued', {
        'session_id': sid,
        'dequeued_queue_id': qid,
        'queue_length': 0,
        'queued_messages': [],
      });
      h.transport.receive('run.started', {
        'session_id': sid,
        'run_id': 'r2',
        'queue_id': qid,
      });
      expect(
        h.controller.timeline.messages
            .where((m) => m.role == 'user' && m.content == 'two')
            .length,
        1,
      );
      expect(h.controller.timeline.queue, isEmpty);
      expect(h.controller.timeline.runId, 'r2');
    },
  );
  test('cancel during pre-play await prevents late synthesis', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    var requests = 0;
    h.override = (r) async {
      requests++;
      return http.Response.bytes(
        [1],
        200,
        headers: {'content-type': 'audio/mpeg'},
      );
    };
    final speech = SpeechPlayback(outputFactory: FakeSpeech.new);
    addTearDown(speech.dispose);
    final speaking = speech.speak(h.controller.api!, 'm', 'hello');
    await speech.stop();
    await speaking;
    expect(requests, 0);
    expect(speech.activeId, isNull);
  });
  test(
    'TTS uses profile credentials, validates bytes and native playback stop',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.override = (r) async {
        expect(r.url.path, '/api/studio/tts/synthesize');
        expect(jsonDecode(r.body), {'text': 'hello'});
        expect(r.headers['X-Hermes-Profile'], 'default');
        expect(r.followRedirects, false);
        return http.Response.bytes(
          [1, 2, 3],
          200,
          headers: {'content-type': 'audio/mpeg'},
        );
      };
      final out = FakeSpeech();
      final speech = SpeechPlayback(outputFactory: () => out);
      addTearDown(speech.dispose);
      await speech.speak(h.controller.api!, 'm', 'hello');
      expect(out.bytes, [1, 2, 3]);
      expect(speech.activeId, 'm');
      await speech.stop();
      expect(speech.activeId, isNull);
      h.override = (r) async => http.Response(
        'not audio',
        200,
        headers: {'content-type': 'text/html'},
      );
      await speech.speak(h.controller.api!, 'm', 'hello');
      expect(speech.error, contains('格式无效'));
      expect(speech.activeId, isNull);
    },
  );
}

class FakeSpeech implements SpeechOutput {
  Uint8List? bytes;
  @override
  Stream<void> get completed => const Stream.empty();
  @override
  Future<void> play(Uint8List data, String mime) async {
    bytes = data;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
