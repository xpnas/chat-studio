import 'dart:async';
import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/protocol_capabilities.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'resource 404 is distinct from confirmed missing route and permissions',
    () {
      expect(
        classifyProtocolFailure(const ApiException('missing', 404)),
        ProtocolFailure.notFound,
      );
      expect(
        classifyProtocolFailure(
          const ApiException('missing', 404),
          confirmedMissingRoute: true,
        ),
        ProtocolFailure.unsupported,
      );
      for (final code in [401, 403]) {
        expect(
          classifyProtocolFailure(
            ApiException('denied', code),
            confirmedMissingRoute: true,
          ),
          code == 401
              ? ProtocolFailure.unauthenticated
              : ProtocolFailure.forbidden,
        );
      }
    },
  );
  test(
    'transient failure can retry and resource absence does not erase support',
    () async {
      final registry = ProtocolCapabilities();
      const feature = ProtocolCapability.sessionTasks;
      await expectLater(
        registry.read(
          feature,
          () async => throw const ApiException('offline', 503),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(registry[feature], CapabilityState.unavailable);
      expect(await registry.read(feature, () async => 'ok'), 'ok');
      await expectLater(
        registry.read(
          feature,
          () async => throw const ApiException('resource', 404),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(registry[feature], CapabilityState.supported);
      await expectLater(
        registry.read(
          feature,
          () async => throw const ApiException('route', 404),
          isMissingRoute: (_) => true,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(registry[feature], CapabilityState.unsupported);
      registry.invalidate();
      expect(registry[feature], CapabilityState.unknown);
    },
  );
  test(
    'all features start unknown and old requests cannot replace newer probes',
    () async {
      final registry = ProtocolCapabilities();
      for (final feature in ProtocolCapability.values) {
        expect(registry[feature], CapabilityState.unknown);
      }
      final old = Completer<String>();
      final pending = registry.read(
        ProtocolCapability.agents,
        () => old.future,
      );
      final assertion = expectLater(
        pending,
        throwsA(isA<StaleProtocolResponse>()),
      );
      await registry.read(ProtocolCapability.agents, () async => 'new');
      old.complete('old');
      await assertion;
      expect(registry[ProtocolCapability.agents], CapabilityState.supported);
    },
  );
  for (final change in ['profile', 'token', 'close', 'refresh']) {
    test('$change invalidates in-flight reads and ignores old 401', () async {
      final reply = Completer<http.Response>();
      var unauthorized = 0;
      final api = StudioApi(
        ServerAddress.parse('https://example.test'),
        client: MockClient((r) {
          expect(r.method, 'GET');
          return reply.future;
        }),
      )..onUnauthorized = () => unauthorized++;
      final pending = api.readCapability(
        ProtocolCapability.person,
        '/api/studio/person',
      );
      final assertion = expectLater(
        pending,
        throwsA(isA<StaleProtocolResponse>()),
      );
      switch (change) {
        case 'profile':
          api.profile = 'other';
        case 'token':
          api.token = 'other';
        case 'close':
          api.close();
        case 'refresh':
          api.resetCapabilities();
      }
      reply.complete(http.Response('{"error":"old"}', 401));
      await assertion;
      expect(unauthorized, 0);
      expect(
        api.capabilities[ProtocolCapability.person],
        CapabilityState.unknown,
      );
      api.close();
    });
  }
  for (final code in [401, 403, 500]) {
    test(
      'HTTP $code remains an error without fallback or write probing',
      () async {
        var count = 0;
        var unauthorized = 0;
        final api = StudioApi(
          ServerAddress.parse('https://example.test'),
          client: MockClient((r) async {
            expect(r.method, 'GET');
            count++;
            return http.Response('{"error":"denied"}', code);
          }),
        )..onUnauthorized = () => unauthorized++;
        addTearDown(api.close);
        await expectLater(
          api.readCapability(ProtocolCapability.timeline, '/optional'),
          throwsA(isA<ApiException>()),
        );
        expect(count, 1);
        expect(unauthorized, code == 401 ? 1 : 0);
        expect(
          api.capabilities[ProtocolCapability.timeline],
          CapabilityState.unavailable,
        );
      },
    );
  }
}
