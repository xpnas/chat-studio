import 'dart:convert';

import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'management APIs preserve Studio routes, profile and revision contracts',
    () async {
      final requests = <http.Request>[];
      final api =
          StudioApi(
              ServerAddress.parse('https://studio.example.com'),
              client: MockClient((request) async {
                requests.add(request);
                return http.Response('{}', 200);
              }),
            )
            ..token = 'session-token'
            ..profile = 'work';
      addTearDown(api.close);

      await api.codingAgents();
      await api.installCodingAgent('codex');
      await api.checkCodingAgentUpdate('codex');
      await api.setCodingAgentAutoUpdate('codex', true);
      await api.codingAgentConfig('codex', 'config');
      await api.saveCodingAgentConfig('codex', 'config', '{"model":"x"}');
      await api.patchProviderEditor('custom:edge', 'rev-7', {
        'base_url': 'https://models.example.com/v1',
      });
      await api.refreshProviderModels('custom:edge', confirm: true);
      await api.removeProvider(
        'custom:edge',
        source: 'providers',
        providerKey: 'edge-router',
      );
      await api.saveVoiceProvider('tts', 'custom', {
        'model': 'tts-1',
        'voice': 'nova',
      }, apiKey: 'replacement-only');
      await api.deleteVoiceProvider('stt', 'custom');

      expect(requests, hasLength(11));
      for (final request in requests) {
        expect(request.headers['authorization'], 'Bearer session-token');
        expect(request.headers['x-hermes-profile'], 'work');
      }
      expect(requests[0].url.path, '/api/coding-agents');
      expect(requests[1].method, 'POST');
      expect(requests[1].url.path, endsWith('/coding-agents/codex/install'));
      expect(
        requests[2].url.path,
        endsWith('/coding-agents/codex/check-update'),
      );
      expect(requests[3].method, 'PUT');
      expect(jsonDecode(requests[3].body), {'autoUpdate': true});
      expect(
        requests[4].url.path,
        endsWith('/coding-agents/codex/config-files/config'),
      );
      expect(requests[5].method, 'PUT');
      expect(jsonDecode(requests[5].body)['content'], '{"model":"x"}');
      expect(requests[6].method, 'PATCH');
      expect(requests[6].url.path, contains('/providers/custom%3Aedge/editor'));
      expect(jsonDecode(requests[6].body), {
        'base_url': 'https://models.example.com/v1',
        'revision': 'rev-7',
      });
      expect(
        requests[7].url.path,
        contains('/providers/custom%3Aedge/models/refresh'),
      );
      expect(jsonDecode(requests[7].body), {'confirm': true});
      expect(requests[8].method, 'DELETE');
      expect(requests[8].url.queryParameters, {
        'source': 'providers',
        'providerKey': 'edge-router',
      });
      expect(requests[9].url.path, '/api/studio/tts/settings/custom');
      expect(jsonDecode(requests[9].body), {
        'settings': {'model': 'tts-1', 'voice': 'nova'},
        'secrets': {'apiKey': 'replacement-only'},
      });
      expect(requests[10].url.path, '/api/studio/stt/settings/custom');
      expect(requests[10].method, 'DELETE');
    },
  );
}
