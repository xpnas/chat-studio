import 'dart:async';
import 'dart:convert';
import 'package:chatstudio/data/agent_catalog.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/ui/widgets/agent_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

http.Response availability(List<Map<String, dynamic>> rows) => http.Response(
  jsonEncode({'revision': 2, 'agents': rows}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> installed(String id, {bool yes = true}) => {
  'id': id,
  'installed': yes,
  'source': yes ? 'user-cli' : 'not-installed',
};
void catalog(TestHarness h, List<Map<String, dynamic>> rows) {
  h.override = (r) async => r.url.path == '/api/agents/availability'
      ? availability(rows)
      : h.response(r);
}

void main() {
  test('icon failures are cached, unauthenticated and retryable', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    var calls = 0;
    h.override = (r) async {
      if (r.url.path.startsWith('/coding-agents/')) {
        calls++;
        expect(r.headers.containsKey('authorization'), false);
        expect(r.followRedirects, false);
        return http.Response('<html>missing</html>', 404);
      }
      return h.response(r);
    };
    expect(await h.controller.api!.agentIcon('pi.svg'), isNull);
    expect(await h.controller.api!.agentIcon('pi.svg'), isNull);
    expect(calls, 1);
    await h.controller.refreshAgents();
    expect(await h.controller.api!.agentIcon('pi.svg'), isNull);
    expect(calls, 2);
    expect(await h.controller.api!.agentIcon('../private.svg'), isNull);
    expect(calls, 2);
  });

  test(
    'catalog uses server installation flags, aliases and strict safe IDs',
    () {
      final rows = AgentChoice.parse([
        installed('claude'),
        installed('codex', yes: false),
        installed('new-agent'),
        installed('../icon'),
        {'id': 'pi', 'installed': 'true'},
        installed('grok'),
        installed('grok', yes: false),
        {...installed('opencode'), 'source': 'not-installed'},
      ]);
      expect(rows.where((a) => a.selectable).map((a) => a.id), ['claude-code']);
      expect(rows.first.name, 'Claude');
      expect(rows.first.icon, 'claude-code.svg');
      expect(rows.where((a) => a.id == 'new-agent').single.supported, false);
      expect(() => AgentChoice.parse({}), throwsFormatException);
    },
  );

  test(
    'login uses public availability, not admin coding-agent status',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      catalog(h, [installed('pi'), installed('codex', yes: false)]);
      await h.login();
      expect(h.controller.availableAgents.map((a) => a.id), ['pi']);
      expect(h.controller.engine, 'pi');
      expect(h.controller.canSend, true);
      expect(
        h.requests.where((r) => r.url.path == '/api/coding-agents'),
        isEmpty,
      );
      h.controller.chooseEngine('codex');
      expect(h.controller.engine, 'pi');
    },
  );

  test(
    'new chat and foreground discover installations without logging out',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      catalog(h, [installed('opencode')]);
      h.controller.newChat();
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.availableAgents.single.id, 'opencode');
      expect(h.controller.engine, 'opencode');
      catalog(h, [installed('grok')]);
      h.controller.onForeground();
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.availableAgents.single.id, 'grok');
    },
  );

  test(
    'failed fetch is explicit and retry recovers without fake options',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      h.override = (r) async => r.url.path == '/api/agents/availability'
          ? http.Response('{}', 503)
          : h.response(r);
      await h.login();
      expect(h.controller.agentsError, isNotNull);
      expect(h.controller.agents, isEmpty);
      expect(h.controller.canSend, false);
      catalog(h, [installed('codex')]);
      await h.controller.refreshAgents();
      expect(h.controller.agentsError, isNull);
      expect(h.controller.canSend, true);
    },
  );

  test('empty and unsupported catalogs cannot send a misrouted run', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    catalog(h, [installed('new-agent')]);
    await h.login();
    h.controller.chooseEngine('new-agent');
    expect(h.controller.send('no wrong Claude fallback'), false);
    catalog(h, []);
    await h.controller.refreshAgents();
    expect(h.controller.availableAgents, isEmpty);
    expect(h.controller.send('no installed agents'), false);
    expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
  });

  test(
    'late older request and old server result cannot overwrite catalog',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final pending = Completer<http.Response>();
      h.override = (r) => r.url.path == '/api/agents/availability'
          ? pending.future
          : Future.value(h.response(r));
      final stale = h.controller.refreshAgents();
      catalog(h, [installed('pi')]);
      await h.controller.refreshAgents();
      pending.complete(availability([installed('codex')]));
      await stale;
      expect(h.controller.availableAgents.single.id, 'pi');
      final oldServer = Completer<http.Response>();
      h.override = (r) => r.url.path == '/api/agents/availability'
          ? oldServer.future
          : Future.value(h.response(r));
      final old = h.controller.refreshAgents();
      await h.controller.addServer();
      oldServer.complete(availability([installed('grok')]));
      await old;
      expect(h.controller.agents, isEmpty);
      expect(h.controller.agentsLoaded, false);
    },
  );

  test(
    'catalog refresh never changes the agent of an open conversation',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.openConversation(
        const Conversation(
          id: 's',
          title: 'Claude history',
          agent: 'claude',
          source: 'coding_agent',
        ),
      );
      expect(h.controller.engine, 'claude-code');
      catalog(h, [installed('codex')]);
      await h.controller.refreshAgents();
      expect(h.controller.engine, 'claude-code');
    },
  );

  for (final id in ['claude-code', 'pi', 'grok', 'opencode']) {
    test(
      '$id new and historical chats use scoped coding-agent routing',
      () async {
        final h = TestHarness();
        addTearDown(h.dispose);
        catalog(h, [installed(id)]);
        await h.login();
        h.controller.chooseEngine(id);
        expect(h.controller.send('hello'), true);
        final data = h.transport.emitted.last.$2;
        expect(data['agent_id'], id);
        expect(data['source'], 'coding_agent');
        expect(data['mode'], 'scoped');
        final sid = h.controller.sessionId!;
        h.transport.receive('abort.completed', {'session_id': sid});
        final conversation = Conversation(
          id: sid,
          title: 'history',
          agent: id == 'claude-code' ? 'claude' : id,
          source: 'coding_agent',
        );
        expect(conversation.canContinue, true);
        await h.controller.openConversation(conversation);
        h.transport.receive('resumed', {
          'session_id': sid,
          'messages': [],
          'isWorking': false,
        });
        expect(h.controller.send('continue'), true);
        expect(h.transport.emitted.last.$2['agent_id'], id);
        expect(
          Conversation(
            id: sid,
            title: '',
            agent: id,
            source: 'global_agent',
          ).canContinue,
          false,
        );
      },
    );
  }

  testWidgets('picker shows icons, current choice first and live refresh', (
    tester,
  ) async {
    final h = TestHarness();
    catalog(h, [
      installed('pi'),
      installed('codex'),
      installed('grok', yes: false),
    ]);
    await h.login();
    h.controller.chooseEngine('codex');
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-picker')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-option:grok')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('agent-option:codex'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('agent-option:pi'))).dy,
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('agent-option:pi')),
        matching: find.byType(AgentAvatar),
      ),
      findsOneWidget,
    );
    catalog(h, [installed('pi'), installed('opencode')]);
    await tester.tap(find.byTooltip('刷新 Agent'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-option:codex')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('agent-option:opencode')));
    await tester.pumpAndSettle();
    expect(h.controller.engine, 'opencode');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('picker handles empty, retry and large text on a small screen', (
    tester,
  ) async {
    final h = TestHarness();
    catalog(h, []);
    await h.login();
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('agent-picker')));
    await tester.tap(find.byKey(const ValueKey('agent-picker')));
    await tester.pumpAndSettle();
    expect(find.textContaining('服务端没有可用'), findsOneWidget);
    h.override = (r) async => r.url.path == '/api/agents/availability'
        ? http.Response('{}', 503)
        : h.response(r);
    await tester.tap(find.byTooltip('刷新 Agent'));
    await tester.pumpAndSettle();
    expect(find.text('重新加载'), findsOneWidget);
    catalog(h, [installed('claude-code'), installed('opencode')]);
    await tester.tap(find.text('重新加载'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('agent-option:claude-code')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
