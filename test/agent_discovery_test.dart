import 'dart:convert';
import 'package:chatstudio/data/agent_catalog.dart';
import 'package:chatstudio/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

Map<String, dynamic> descriptor(
  String id, {
  List<String> modes = const ['global'],
  List<String> surfaces = const ['chat'],
  bool installed = true,
}) => {
  'id': id,
  'name': id,
  'modes': modes,
  'surfaces': surfaces,
  'status': {'installed': installed},
};
void main() {
  test('plugin identity is validated and one complete path segment', () {
    final rows = AgentChoice.parseDescriptors([
      descriptor('plugin:omp/omp'),
      descriptor('plugin:../omp'),
      descriptor('plugin:x/x/y'),
      descriptor('plugin:constructor/x'),
      descriptor('plugin:x%2fy/z'),
      descriptor('plugin:no/chat', surfaces: []),
      descriptor('plugin:unknown/mode', modes: ['future']),
    ], enablePlugins: true);
    expect(rows.where((r) => r.selectable).map((r) => r.id), [
      'plugin:omp/omp',
    ]);
    expect(rows.first.encodedRouteId, 'plugin%3Aomp%2Fomp');
    expect(
      AgentChoice.parseDescriptors([
        descriptor('plugin:omp/omp'),
      ]).single.selectable,
      false,
    );
  });
  test('descriptors cannot broaden commands and conflicts restrict modes', () {
    final rows = AgentChoice.parseDescriptors([
      descriptor('qwen', modes: ['scoped', 'global']),
      descriptor('qwen', modes: ['global']),
      descriptor('codex'),
      descriptor('codex', installed: false),
      descriptor('unknown-agent'),
    ]);
    expect(rows.first.modes, ['global']);
    expect(rows.first.supportsCompact, false);
    expect(rows.where((r) => r.selectable).map((r) => r.id), ['qwen']);
  });
  test(
    'empty Coding directory preserves core availability without guessing Coding installation',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.override = (r) async => r.url.path == '/api/studio/agents'
          ? http.Response('{"agents":[]}', 200)
          : h.response(r);
      final before = h.requests
          .where((r) => r.url.path == '/api/agents/availability')
          .length;
      await h.controller.refreshAgents();
      expect(h.controller.availableAgents.map((agent) => agent.id), [
        'ekko-agent',
        'hermes',
      ]);
      expect(
        h.requests
            .where((r) => r.url.path == '/api/agents/availability')
            .length,
        before + 1,
      );
    },
  );
  test('core and Coding records each use their authoritative source', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    h.override = (r) async {
      if (r.url.path == '/api/studio/agents') {
        return http.Response(
          jsonEncode({
            'agents': [
              descriptor('codex', installed: false),
              descriptor('qwen'),
              descriptor('hermes'),
              descriptor('ekko-agent', installed: false),
            ],
          }),
          200,
        );
      }
      if (r.url.path == '/api/agents/availability') {
        return http.Response(
          jsonEncode({
            'agents': [
              {'id': 'ekko', 'installed': true},
              {'id': 'hermes', 'installed': false},
              {'id': 'codex', 'installed': true},
              {'id': 'qwen', 'installed': false},
            ],
          }),
          200,
        );
      }
      return h.response(r);
    };
    await h.login();
    expect(h.controller.availableAgents.map((agent) => agent.id), [
      'ekko-agent',
      'qwen',
    ]);
    expect(
      h.controller.agents
          .where((agent) => agent.id == 'hermes')
          .single
          .installed,
      false,
    );
    expect(
      h.controller.agents
          .where((agent) => agent.id == 'codex')
          .single
          .installed,
      false,
    );
  });
  test(
    'missing core records are not installed implicitly and core permission failure is surfaced',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      var coreStatus = 200;
      h.override = (r) async {
        if (r.url.path == '/api/studio/agents') {
          return http.Response('{"agents":[]}', 200);
        }
        if (r.url.path == '/api/agents/availability') {
          return http.Response(
            coreStatus == 200 ? '{"agents":[]}' : '{"error":"forbidden"}',
            coreStatus,
          );
        }
        return h.response(r);
      };
      await h.login();
      expect(h.controller.availableAgents, isEmpty);
      coreStatus = 403;
      await h.controller.refreshAgents();
      expect(h.controller.agentsErrorStatus, 403);
      expect(h.controller.availableAgents, isEmpty);
    },
  );
  test(
    'transient and permission errors never trigger legacy fallback and can retry',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final before = h.requests
          .where((r) => r.url.path == '/api/agents/availability')
          .length;
      for (final status in [503, 403]) {
        h.override = (r) async => r.url.path == '/api/studio/agents'
            ? http.Response('{"error":"failed"}', status)
            : h.response(r);
        await h.controller.refreshAgents();
        expect(h.controller.agentsError, isNotNull);
      }
      expect(
        h.requests
            .where((r) => r.url.path == '/api/agents/availability')
            .length,
        before,
      );
      h.override = (r) async => r.url.path == '/api/studio/agents'
          ? http.Response(
              jsonEncode({
                'agents': [descriptor('cursor')],
              }),
              200,
            )
          : h.response(r);
      await h.controller.refreshAgents();
      await h.controller.chooseEngine('cursor');
      expect(h.controller.send('native default'), true);
      final run = h.transport.emitted.lastWhere((e) => e.$1 == 'run').$2;
      expect(run['mode'], 'global');
      expect(run.containsKey('provider'), false);
      expect(run['model'], '');
    },
  );
  test(
    'saved global configuration resumes without scoped provider values',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.openConversation(
        Conversation.fromJson({
          'id': 'global-saved',
          'agent': 'codex',
          'agent_mode': 'global',
          'model': 'native-alias',
          'provider': 'old-provider',
          'reasoning_effort': 'high',
        }),
      );
      h.transport.receive('resumed', {
        'session_id': 'global-saved',
        'messages': [],
        'working': false,
      });
      expect(h.controller.agentMode, 'global');
      expect(h.controller.send('continue'), true);
      final run = h.transport.emitted.lastWhere((e) => e.$1 == 'run').$2;
      expect(run['model'], 'native-alias');
      expect(run['mode'], 'global');
      expect(run.containsKey('provider'), false);
      expect(
        Conversation.fromJson({
          'id': 'future',
          'agent_mode': 'future',
        }).canContinue,
        false,
      );
    },
  );
}
