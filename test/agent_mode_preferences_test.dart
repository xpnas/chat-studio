import 'dart:convert';
import 'package:chatstudio/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/state/app_controller.dart';
import 'package:http/testing.dart';

void main() {
  test(
    'legacy scoped migration is idempotent and cannot overwrite a v2 choice or retain credentials',
    () async {
      final storage = MemoryStorage();
      const scope = 'https://server|1|work';
      storage.choices[scope] = {
        'engine': 'claude',
        'model': 'legacy',
        'provider': 'p',
        'api_key': 'secret',
        'reasoning_effort': 'high',
      };
      expect(await storage.readAgentChoice(scope, 'codex', 'scoped'), isNull);
      expect(
        await storage.readAgentChoice(scope, 'claude-code', 'global'),
        isNull,
      );
      final migrated = await storage.readAgentChoice(
        scope,
        'claude-code',
        'scoped',
      );
      expect(migrated!['model'], 'legacy');
      expect(jsonEncode(migrated), isNot(contains('secret')));
      await storage.saveAgentChoice(scope, 'claude-code', 'scoped', {
        'model': 'new',
        'provider': 'p',
        'api_key': 'must-not-save',
      });
      expect(
        (await storage.readAgentChoice(
          scope,
          'claude-code',
          'scoped',
        ))!['model'],
        'new',
      );
      expect(
        (await storage.readAgentChoice(
          scope,
          'claude-code',
          'scoped',
        ))!['model'],
        'new',
      );
      expect(
        await storage.readAgentChoice(
          'https://other|1|work',
          'claude-code',
          'scoped',
        ),
        isNull,
      );
      expect(
        await storage.readAgentChoice(
          'https://server|2|work',
          'claude-code',
          'scoped',
        ),
        isNull,
      );
      expect(
        await storage.readAgentChoice(
          'https://server|1|other',
          'claude-code',
          'scoped',
        ),
        isNull,
      );
      expect(
        jsonEncode(
          storage.choices.values
              .where((choice) => choice['model'] == 'new')
              .toList(),
        ),
        isNot(contains('must-not-save')),
      );
    },
  );
  test(
    'all saved execution fields round-trip and unknown modes remain read-only',
    () {
      final source = {
        'id': 's',
        'title': 'saved',
        'agent': 'codex',
        'profile': 'work',
        'agent_mode': 'global',
        'model': 'provider/model-alias',
        'provider': 'native-provider',
        'api_mode': 'codex_responses',
        'reasoning_effort': 'enabled',
      };
      final restored = Conversation.fromJson(
        Conversation.fromJson(source).toJson(),
      );
      for (final key in source.keys) {
        expect(restored.toJson()[key], source[key]);
      }
      expect(
        Conversation.fromJson({'id': 'legacy', 'agent': 'claude'}).agentMode,
        'scoped',
      );
      expect(
        Conversation.fromJson({
          'id': 'unknown',
          'agent_mode': 'future',
        }).canContinue,
        false,
      );
    },
  );
  test(
    'mode switching restores each model and effort and sends native aliases unchanged',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      h.override = (r) async => r.url.path == '/api/coding-agents/models'
          ? http.Response(
              jsonEncode({
                'agents': [
                  {
                    'agentId': 'codex',
                    'status': 'ready',
                    'models': [
                      {
                        'id': 'opus',
                        'name': 'Native alias',
                        'resolvedModel': 'Concrete name',
                        'reasoningEfforts': ['high', 'enabled'],
                      },
                    ],
                  },
                ],
              }),
              200,
            )
          : h.response(r);
      await h.login();
      await h.controller.chooseEngine('codex');
      await h.controller.chooseModel(h.controller.models.last);
      await h.controller.chooseAgentMode('global');
      await h.controller.refreshNativeModels();
      await Future<void>.delayed(Duration.zero);
      final native = h.controller.selectableModels.firstWhere(
        (model) => model.id == 'opus',
      );
      await h.controller.chooseModel(native);
      await h.controller.chooseReasoningEffort('enabled');
      await h.controller.chooseAgentMode('scoped');
      expect(h.controller.selectedModel!.id, 'model-b');
      await h.controller.chooseAgentMode('global');
      expect(h.controller.selectedModel!.id, 'opus');
      expect(h.controller.reasoningEffort, 'enabled');
      expect(h.controller.send('native'), true);
      final payload = h.transport.emitted
          .lastWhere((event) => event.$1 == 'run')
          .$2;
      expect(payload['mode'], 'global');
      expect(payload['model'], 'opus');
      expect(payload['reasoning_effort'], 'enabled');
      expect(payload.containsKey('provider'), false);
      expect(payload.containsKey('api_mode'), false);
      final reopened = AppController(
        storage: h.storage,
        transport: FakeTransport(),
        sessionSyncTransport: FakeSessionSyncTransport(),
        apiFactory: (address) =>
            StudioApi(address, client: MockClient((r) async => h.response(r))),
      );
      addTearDown(reopened.dispose);
      await reopened.initialize();
      await reopened.login('https://example.com', 'Alex', 'password', false);
      expect(reopened.engine, 'codex');
      expect(reopened.agentMode, 'global');
      expect(reopened.selectedModel!.id, 'opus');
      expect(reopened.reasoningEffort, 'enabled');
    },
  );
  test(
    'saved API mode wins over directory inference, failures roll back and existing mode cannot change',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.openConversation(
        const Conversation(
          id: 'saved-api',
          title: 'Saved',
          agent: 'codex',
          model: 'model-a',
          provider: 'test',
          apiMode: 'codex_responses',
        ),
      );
      h.transport.receive('resumed', {
        'session_id': 'saved-api',
        'messages': [],
        'isWorking': false,
      });
      expect(h.controller.selectedModel!.apiMode, 'codex_responses');
      await h.controller.chooseAgentMode('global');
      expect(h.controller.agentMode, 'scoped');
      expect(h.controller.workspaceNotice, contains('新建'));
      final before = h.controller.selectedModel;
      final effort = h.controller.reasoningEffort;
      for (final status in [403, 409]) {
        h.override = (r) async =>
            r.url.path.endsWith('/model') ||
                r.url.path.endsWith('/reasoning-effort')
            ? http.Response('{"error":"denied"}', status)
            : h.response(r);
        await h.controller.chooseModel(h.controller.models.last);
        expect(h.controller.selectedModel, same(before));
        await h.controller.chooseReasoningEffort('high');
        expect(h.controller.reasoningEffort, effort);
        expect(h.controller.error, 'denied');
      }
    },
  );
  test('fixed-provider API mode cannot be overridden', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    h.controller.selectedModel = const ModelChoice(
      id: 'fixed',
      provider: 'p',
      label: 'Fixed',
      apiMode: 'anthropic_messages',
    );
    await h.controller.chooseApiMode('codex_responses');
    expect(h.controller.selectedModel!.apiMode, 'anthropic_messages');
  });
}
