import 'dart:async';
import 'dart:convert';
import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/native_models.dart';
import 'package:chatstudio/data/protocol_capabilities.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> catalog(
  String agent, {
  String status = 'ready',
  String model = 'opus',
}) => {
  'agentId': agent,
  'status': status,
  'scope': 'available',
  'source': 'control-protocol',
  'models': [
    {
      'id': model,
      'name': 'Alias',
      'resolvedModel': 'resolved-name',
      'provider': 'native-prefix',
      'isDefault': true,
      'reasoningEfforts': ['high', 'enabled'],
      'contextWindow': 100000,
      'inputModalities': ['text', 'image'],
    },
    {'id': 'hidden', 'name': 'Hidden', 'hidden': true},
  ],
};
void main() {
  test(
    'seven statuses and native metadata preserve literal execution identifiers',
    () {
      for (final status in [
        'ready',
        'empty',
        'not_installed',
        'auth_required',
        'unsupported',
        'timeout',
        'error',
      ]) {
        expect(
          NativeModelCatalog.fromJson(
            'claude-code',
            catalog('claude-code', status: status),
          ).status,
          isA<NativeModelStatus>(),
        );
      }
      final parsed = NativeModelCatalog.fromJson(
        'claude-code',
        catalog('claude-code'),
      );
      expect(parsed.models.first.id, 'opus');
      expect(parsed.models.first.provider, 'native-prefix');
      expect(parsed.models.first.reasoningEfforts, ['high', 'enabled']);
      expect(parsed.choices.map((choice) => choice.id), ['', 'opus']);
      expect(parsed.choices.first.native, true);
      expect(parsed.choices.last.provider, '');
      expect(parsed.choices.last.label, 'resolved-name');
      expect(
        () => NativeModelCatalog.fromJson('codex', {
          'status': 'future',
          'models': [],
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'stable native query isolates per-agent failures and keeps cached directory on failed refresh',
    () async {
      var failed = false;
      final api = StudioApi(
        ServerAddress.parse('https://example.test'),
        client: MockClient((r) async {
          expect(r.method, 'GET');
          expect(r.url.path, '/api/coding-agents/models');
          expect(r.url.queryParameters['refresh'], '$failed');
          return http.Response(
            jsonEncode({
              'agents': [
                catalog('codex', status: failed ? 'timeout' : 'ready'),
                catalog('pi', status: 'auth_required'),
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      expect((await api.nativeModels('codex')).status, NativeModelStatus.ready);
      failed = true;
      expect(
        (await api.nativeModels('codex', refresh: true)).status,
        NativeModelStatus.timeout,
      );
      expect(api.cachedNativeModels('codex')!.models.first.id, 'opus');
      expect(api.cachedNativeModels('pi'), isNull);
    },
  );
  test('unified plugin models preserve complete encoded identity', () async {
    late Uri observed;
    final api = StudioApi(
      ServerAddress.parse('https://example.test'),
      client: MockClient((r) async {
        observed = r.url;
        return http.Response(jsonEncode(catalog('plugin:omp/omp')), 200);
      }),
    )..enablePluginAgents = true;
    addTearDown(api.close);
    await api.capabilities.read(ProtocolCapability.agents, () async => true);
    await api.nativeModels('plugin:omp/omp');
    expect(observed.pathSegments, [
      'api',
      'studio',
      'agents',
      'plugin:omp/omp',
      'models',
    ]);
  });
  test(
    'old identity and out-of-order native responses cannot populate cache',
    () async {
      final replies = <Completer<http.Response>>[];
      final api = StudioApi(
        ServerAddress.parse('https://example.test'),
        client: MockClient((r) {
          final reply = Completer<http.Response>();
          replies.add(reply);
          return reply.future;
        }),
      );
      addTearDown(api.close);
      final first = api.nativeModels('codex');
      final assertion = expectLater(
        first,
        throwsA(isA<StaleProtocolResponse>()),
      );
      await Future<void>.delayed(Duration.zero);
      final second = api.nativeModels('codex');
      await Future<void>.delayed(Duration.zero);
      replies[1].complete(
        http.Response(
          jsonEncode({
            'agents': [catalog('codex', model: 'new')],
          }),
          200,
        ),
      );
      await second;
      replies[0].complete(
        http.Response(
          jsonEncode({
            'agents': [catalog('codex', model: 'old')],
          }),
          200,
        ),
      );
      await assertion;
      expect(api.cachedNativeModels('codex')!.models.first.id, 'new');
      final late = api.nativeModels('codex');
      final oldIdentity = expectLater(
        late,
        throwsA(isA<StaleProtocolResponse>()),
      );
      await Future<void>.delayed(Duration.zero);
      api.profile = 'other';
      replies[2].complete(
        http.Response(
          jsonEncode({
            'agents': [catalog('codex')],
          }),
          200,
        ),
      );
      await oldIdentity;
      expect(api.cachedNativeModels('codex'), isNull);
    },
  );
  test(
    'provider model API modes and declared effort sets follow each selected model',
    () {
      final models = ModelChoice.parseGroups([
        {
          'provider': 'p',
          'api_mode': 'chat_completions',
          'models': ['a', 'b', 'c'],
          'api_mode_by_model': {'a': 'codex_responses', 'b': null},
          'model_meta': {
            'a': {
              'reasoning_efforts': ['low', 'high'],
            },
          },
        },
      ]);
      expect(models.map((model) => model.apiMode), [
        'codex_responses',
        '',
        'chat_completions',
      ]);
      expect(models.first.reasoningEfforts, ['low', 'high']);
    },
  );
}
