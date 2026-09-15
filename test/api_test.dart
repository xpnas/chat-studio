import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/studio_api.dart';

void main() {
  test('requests never forward bearer credentials through redirects', () async {
    final api = StudioApi(
      ServerAddress.parse('https://example.com'),
      client: MockClient((request) async {
        expect(request.followRedirects, false);
        return http.Response(
          '{"error":"redirect disallowed"}',
          302,
          headers: {'location': 'https://elsewhere.example'},
        );
      }),
    );
    addTearDown(api.close);
    await expectLater(api.me(), throwsA(isA<ApiException>()));
  });
  test(
    'history offset counts invisible tool rows; mode reaches set-model endpoint',
    () async {
      final api = StudioApi(
        ServerAddress.parse('https://example.com'),
        client: MockClient((request) async {
          if (request.method == 'POST') {
            expect(jsonDecode(request.body)['api_mode'], 'chat_completions');
            return http.Response('{}', 200);
          }
          return http.Response(
            jsonEncode({
              'messages': [
                {'id': 1, 'role': 'tool', 'content': 'hidden'},
                {'id': 2, 'role': 'assistant', 'content': 'visible'},
              ],
              'offset': 60,
              'total': 80,
              'hasMore': true,
            }),
            200,
          );
        }),
      );
      addTearDown(api.close);
      final page = await api.messages('s1', offset: 60);
      expect(page.offset, 62);
      expect(page.messages.where((m) => m.visible).length, 1);
      await api.setModel(
        's1',
        const ModelChoice(
          id: 'm',
          provider: 'p',
          label: 'm',
          apiMode: 'chat_completions',
        ),
      );
    },
  );
  test(
    'HTML proxy errors produce useful messages instead of JSON crashes',
    () async {
      final api = StudioApi(
        ServerAddress.parse('https://example.com'),
        client: MockClient(
          (_) async => http.Response('<html>proxy down</html>', 502),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.me(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('反向代理'),
          ),
        ),
      );
    },
  );
}
