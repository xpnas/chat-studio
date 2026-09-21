import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/models.dart';
import 'support.dart';

void main() {
  late TestHarness h;
  setUp(() {
    h = TestHarness();
  });
  tearDown(() => h.dispose());
  test(
    'web login sends shared contract, stores token but never password',
    () async {
      await h.login();
      final request = h.requests.firstWhere(
        (r) => r.url.path == '/api/auth/login',
      );
      final data = jsonDecode(request.body) as Map;
      expect(data['username'], 'Alex');
      expect(data['password'], 'password');
      expect(data.containsKey('device_code'), false);
      expect(data.containsKey('device_name'), false);
      expect(request.headers.containsKey('Authorization'), false);
      expect(h.storage.session!['token'], 'web-token');
      expect(h.storage.session!.containsKey('password'), false);
      expect(h.controller.authenticated, true);
      expect(
        h.requests
            .where((r) => r.url.path.endsWith('available-models'))
            .single
            .url
            .queryParameters['profile'],
        'default',
      );
    },
  );
  test('cannot send offline; reconnect does not replay a run', () async {
    await h.login();
    h.transport.receive('disconnected', {});
    expect(h.controller.send('hello'), false);
    h.transport.receive('connected', {});
    expect(h.controller.send('hello'), true);
    final sid = h.controller.sessionId!;
    h.transport.receive('disconnected', {});
    h.transport.receive('connected', {});
    expect(h.transport.emitted.where((e) => e.$1 == 'run').length, 1);
    expect(h.transport.emitted.last.$1, 'resume');
    expect(h.transport.emitted.last.$2, {'session_id': sid});
  });
  test(
    'rejects foreign-session tokens and prevents concurrent sends',
    () async {
      await h.login();
      h.controller.send('hello');
      h.transport.receive('message.delta', {
        'session_id': 'foreign',
        'delta': 'wrong',
      });
      expect(h.controller.timeline.messages.length, 1);
      expect(h.controller.send('duplicate'), false);
      final run = h.transport.emitted.single.$2;
      expect(run['agent_id'], 'ekko-agent');
      expect(run['source'], 'coding_agent');
      expect(run['provider'], 'test');
    },
  );
  test(
    'stale terminal event cannot replace a newer in-flight history',
    () async {
      await h.login();
      h.controller.send('hello');
      final sid = h.controller.sessionId;
      h.transport.receive('run.started', {
        'session_id': sid,
        'run_id': 'current',
      });
      h.transport.receive('message.delta', {
        'session_id': sid,
        'run_id': 'current',
        'delta': 'partial',
      });
      final requests = h.requests.length;
      h.transport.receive('run.completed', {
        'session_id': sid,
        'run_id': 'old',
        'output': 'obsolete',
      });
      await Future<void>.delayed(Duration.zero);
      expect(h.requests.length, requests);
      expect(h.controller.working, true);
      expect(h.controller.timeline.messages.last.content, 'partial');
    },
  );
  test('401 clears stored credentials and all user state', () async {
    await h.login();
    h.override = (_) async => http.Response('{"error":"expired"}', 401);
    await h.controller.refreshSessions();
    await Future<void>.delayed(Duration.zero);
    expect(h.controller.authenticated, false);
    expect(h.storage.session, isNull);
    expect(h.controller.conversations, isEmpty);
    expect(h.controller.error, contains('过期'));
  });
  test('late history response cannot leak after logout', () async {
    await h.login();
    final pending = Completer<http.Response>();
    h.override = (request) => request.url.path.contains('/messages/')
        ? pending.future
        : Future.value(h.response(request));
    final load = h.controller.openConversation(
      h.controller.conversations.single,
    );
    await Future<void>.delayed(Duration.zero);
    await h.controller.logout();
    pending.complete(
      http.Response(
        '{"messages":[{"id":1,"role":"user","content":"private"}]}',
        200,
      ),
    );
    await load;
    expect(h.controller.timeline.messages, isEmpty);
    expect(h.controller.authenticated, false);
  });
  test('profile change scopes socket and request state', () async {
    await h.login();
    await h.controller.switchProfile('work');
    expect(h.controller.profile, 'work');
    expect(h.controller.sessionId, isNull);
    expect(h.requests.last.url.queryParameters['profile'], 'work');
    expect(h.storage.session!['profile'], 'work');
  });
  test('HTTP redirects are disabled on credential requests', () async {
    await h.login();
    expect(h.requests.every((r) => !r.followRedirects), true);
  });
  test('explicit permissions are not optimistically resolved', () async {
    await h.login();
    h.controller.send('do something');
    h.transport.receive('approval.requested', {
      'session_id': h.controller.sessionId,
      'approval_id': 'a',
      'choices': ['once', 'deny'],
    });
    h.controller.respondToInteraction('once');
    expect(h.transport.emitted.last.$1, 'approval.respond');
    expect(h.controller.timeline.interaction, isNotNull);
    h.transport.receive('approval.resolved', {
      'session_id': h.controller.sessionId,
      'approval_id': 'a',
      'resolved': true,
    });
    expect(h.controller.timeline.interaction, isNull);
  });
  test('unsupported automation sessions are read-only', () {
    expect(
      const Conversation(
        id: 'x',
        title: 'workflow',
        source: 'workflow',
      ).canContinue,
      false,
    );
  });
}
