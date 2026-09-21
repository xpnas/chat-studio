import 'dart:convert';
import 'dart:io';
import 'package:chatstudio/data/app_storage.dart';
import 'package:chatstudio/data/file_export.dart';
import 'package:chatstudio/data/studio_protocol.dart';
import 'package:chatstudio/ui/widgets/agent_avatar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = FlutterSecureStorage();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('session and servers round trip in the new secure namespace', () async {
    final storage = SecureAppStorage();
    final session = {'server': 'https://studio.example', 'token': 'test-token'};
    await storage.saveSession(session);
    await storage.saveServers([session]);
    expect(await SecureAppStorage().readSession(), session);
    expect(await SecureAppStorage().readServers(), [session]);
    final values = await secure.readAll();
    expect(
      values.keys,
      unorderedEquals(['chatstudio.session.v1', 'chatstudio.servers.v1']),
    );
    expect(jsonDecode(values['chatstudio.session.v1']!), session);
    await storage.clearSession();
    expect(await storage.readSession(), isNull);
    expect(await storage.readServers(), [session]);
  });

  test(
    'model choices are namespaced and isolated by server account/profile',
    () async {
      final storage = SecureAppStorage();
      const scope = 'https://studio.example/account/profile';
      final choice = {
        'engine': StudioProtocol.builtInAgentId,
        'model': 'model-a',
      };
      await storage.saveChoice(scope, choice);
      expect(await SecureAppStorage().readChoice(scope), choice);
      expect(
        await storage.readChoice('https://other.example/account/profile'),
        isNull,
      );
      final key =
          'chatstudio.choice.v1.${base64Url.encode(utf8.encode(scope))}';
      expect((await secure.readAll()).keys, [key]);
    },
  );

  test(
    'new storage tolerates corrupt session, server and choice values',
    () async {
      const scope = 'test-scope';
      FlutterSecureStorage.setMockInitialValues({
        'chatstudio.session.v1': '{broken',
        'chatstudio.servers.v1': '{broken',
        'chatstudio.choice.v1.${base64Url.encode(utf8.encode(scope))}':
            '{broken',
      });
      final storage = SecureAppStorage();
      expect(await storage.readSession(), isNull);
      expect(await storage.readServers(), isEmpty);
      expect(await storage.readChoice(scope), isNull);
      expect(await secure.read(key: 'chatstudio.session.v1'), isNull);
    },
  );

  test(
    'file export invokes the renamed native channel with a path, not bytes',
    () async {
      const channel = MethodChannel('ai.chatstudio.app/file_export');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'content://export/saved';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final file = File('chatstudio-download/image.png');
      expect(
        await FileExport.save(file, 'image.png', 'image/png'),
        'content://export/saved',
      );
      expect(calls.single.method, 'save');
      expect(calls.single.arguments, {
        'path': file.path,
        'name': 'image.png',
        'mime': 'image/png',
      });
    },
  );

  test('native export cancellation and failure propagate unchanged', () async {
    const channel = MethodChannel('ai.chatstudio.app/file_export');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(
      await FileExport.save(
        File('chatstudio-download/test'),
        'test',
        'text/plain',
      ),
      isNull,
    );
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'busy'),
    );
    await expectLater(
      FileExport.save(File('chatstudio-download/test'), 'test', 'text/plain'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('client rename never changes the built-in upstream wire ID or icon', () {
    expect(StudioProtocol.builtInAgentId, 'ekko-agent');
    expect(StudioProtocol.builtInAgentName, 'Ekko');
    expect(StudioProtocol.builtInAgentIcon, 'ekko-agent.png');
    for (final id in ['', 'ekko', 'ekko_agent', 'ekko-agent']) {
      final identity = AgentIdentity.resolve(id);
      expect(identity.name, 'Ekko');
      expect(identity.file, 'ekko-agent.png');
    }
    expect(AgentIdentity.resolve('codex').name, 'Codex');
    expect(AgentIdentity.resolve('hermes').name, 'Hermes');
  });
}
