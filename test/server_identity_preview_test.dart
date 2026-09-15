import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/ui/home_screen.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:chatstudio/ui/widgets/agent_avatar.dart';
import 'package:chatstudio/ui/widgets/attachment_tile.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'support.dart';

void main() {
  test(
    'migrates existing single session without dropping token or local HTTP opt-in',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      h.storage.session = {
        'server': 'http://192.168.1.2:8641',
        'token': 'legacy-token',
        'profile': 'work',
        'allowLocalHttp': true,
      };
      await h.controller.initialize();
      expect(h.controller.authenticated, isTrue);
      expect(h.controller.profile, 'work');
      expect(h.controller.allowLocalHttp, isTrue);
      expect(h.storage.servers.single['token'], 'legacy-token');
    },
  );
  test(
    'switch restores isolated token/profile, drops drafts and rejects stale socket callbacks',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.switchProfile('work');
      final oldListener = h.transport.listener!;
      final oldUnauthorized = h.controller.api!.onUnauthorized!;
      h.controller.draft.text = 'private unsent';
      await h.controller.addServer();
      expect(h.controller.authenticated, isFalse);
      expect(h.storage.servers.single['token'], 'device-token');
      h.override = (r) async => r.url.path == '/api/auth/app-login'
          ? http.Response(
              '{"token":"second-token","profiles":["default"]}',
              200,
            )
          : h.response(r);
      await h.controller.login(
        'https://second.example/',
        'Alex',
        'password',
        false,
      );
      expect(h.storage.servers.length, 2);
      expect(h.controller.draft.text, isEmpty);
      expect(h.controller.profile, 'default');
      expect(h.controller.api!.token, 'second-token');
      oldUnauthorized();
      expect(h.controller.authenticated, isTrue);
      oldListener('message.delta', {'delta': 'old private text'});
      expect(h.controller.timeline.messages, isEmpty);
      await h.controller.switchServer('https://example.com');
      expect(h.controller.api!.token, 'device-token');
      expect(h.controller.profile, 'work');
      expect(h.storage.session!['server'], 'https://example.com');
      final lastMe = h.requests.lastWhere((r) => r.url.path == '/api/auth/me');
      expect(lastMe.headers['Authorization'], 'Bearer device-token');
      expect(lastMe.url.host, 'example.com');
    },
  );
  test(
    'saved servers and active selection survive a controller restart',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.addServer();
      await h.controller.login(
        'https://second.example',
        'Alex',
        'password',
        false,
      );
      final restarted = TestHarness();
      addTearDown(restarted.dispose);
      restarted.storage.session = h.storage.session;
      restarted.storage.servers = h.storage.servers;
      await restarted.controller.initialize();
      expect(restarted.controller.authenticated, isTrue);
      expect(restarted.controller.api!.address.value, 'https://second.example');
      expect(restarted.controller.servers.length, 2);
      expect(
        jsonEncode(restarted.storage.servers),
        isNot(contains('password')),
      );
      expect(
        jsonEncode(restarted.storage.servers),
        isNot(contains('MUST-NOT-BE-STORED')),
      );
    },
  );
  test(
    'logout clears only current token, removal forgets inactive server, relogin deduplicates',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.addServer();
      await h.controller.login(
        'https://second.example',
        'Alex',
        'password',
        false,
      );
      await h.controller.logout();
      expect(h.storage.session, isNull);
      expect(h.storage.servers.first['token'], isEmpty);
      expect(h.storage.servers.last['token'], 'device-token');
      await h.controller.switchServer('https://second.example');
      expect(h.controller.authenticated, isFalse);
      expect(h.controller.serverInput, 'https://second.example');
      await h.controller.login(
        'https://second.example/',
        'Alex',
        'password',
        false,
      );
      expect(h.storage.servers.length, 2);
      await h.controller.removeServer('https://example.com');
      expect(h.storage.servers.single['server'], 'https://second.example');
      await h.controller.removeServer('https://second.example');
      expect(
        h.storage.servers.length,
        1,
      ); // Active records cannot be removed accidentally.
    },
  );
  test(
    'expired saved token returns to login and leaves other server authorized',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.addServer();
      await h.controller.login(
        'https://second.example',
        'Alex',
        'password',
        false,
      );
      h.override = (r) async =>
          r.url.host == 'example.com' && r.url.path == '/api/auth/me'
          ? http.Response('{}', 401)
          : h.response(r);
      await h.controller.switchServer('https://example.com');
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.authenticated, isFalse);
      expect(h.controller.busy, isFalse);
      expect(
        h.storage.servers.firstWhere(
          (s) => s['server'] == 'https://example.com',
        )['token'],
        isEmpty,
      );
      expect(
        h.storage.servers.firstWhere(
          (s) => s['server'] == 'https://second.example',
        )['token'],
        isNotEmpty,
      );
    },
  );
  test(
    'offline switching preserves configuration for retry and ignores rapid repeated switches',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.addServer();
      await h.controller.login(
        'https://second.example',
        'Alex',
        'password',
        false,
      );
      final gate = Completer<http.Response>();
      h.override = (r) async =>
          r.url.path == '/api/auth/me' ? gate.future : h.response(r);
      final first = h.controller.switchServer('https://example.com');
      final second = h.controller.switchServer('https://second.example');
      await Future<void>.delayed(Duration.zero);
      gate.completeError(Exception('offline'));
      await Future.wait([first, second]);
      expect(h.controller.serverInput, 'https://example.com');
      expect(h.controller.busy, isFalse);
      expect(h.storage.servers.length, 2);
      expect(h.controller.error, contains('连接未完成'));
      h.override = null;
      await h.controller.switchServer('https://example.com');
      expect(h.controller.authenticated, isTrue);
    },
  );
  test(
    'storage failure still clears active session and failed deletion remains visible',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.storage.failServerWrites = true;
      await h.controller.logout();
      expect(h.controller.authenticated, isFalse);
      expect(h.storage.session, isNull);
      expect(h.controller.error, contains('本地凭据清理失败'));
      await h.controller.removeServer('https://example.com');
      expect(h.controller.servers.length, 1);
      expect(h.controller.error, contains('删除服务器记录失败'));
    },
  );
  test(
    'Agent mappings include all pinned Manager identities and safe unknown fallback',
    () {
      for (final pair in {
        '': 'Ekko',
        'ekko_agent': 'Ekko',
        'hermes': 'Hermes',
        'codex': 'Codex',
        'claude-code': 'Claude',
        'pi': 'Pi',
        'grok': 'Grok',
        'opencode': 'OpenCode',
        'custom': 'custom',
      }.entries) {
        expect(AgentIdentity.resolve(pair.key).name, pair.value);
      }
      expect(AgentIdentity.resolve('custom').file, isNull);
    },
  );
  testWidgets(
    'header and assistant use viewed Agent rather than draft engine',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.current = const Conversation(
        id: 'c',
        title: 'Codex task',
        agent: 'codex',
      );
      h.controller.engine = 'ekko-agent';
      h.controller.timeline.replace(const [
        ChatMessage(id: 'a', role: 'assistant', content: 'result'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: chatstudioTheme(Brightness.light),
          home: HomeScreen(controller: h.controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AgentAvatar), findsNWidgets(2));
      expect(find.text('Codex'), findsOneWidget);
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(
        images.every(
          (i) => (i.image as NetworkImage).url.endsWith('codex-openai.png'),
        ),
        isTrue,
      );
      expect(find.byType(MessageBubble), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'image lightbox fills viewport, hides filename, saves and tap dismisses',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      );
      h.override = (r) async => r.url.path == '/api/studio/files/download'
          ? http.Response.bytes(png, 200)
          : h.response(r);
      const file = MessageAttachment(
        name: 'private-filename.png',
        path: '/tmp/image.png',
        mimeType: 'image/png',
      );
      var saved = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AttachmentViewer(
                    file: file,
                    controller: h.controller,
                    saveFile: (name, bytes, mime) async {
                      expect(bytes, png);
                      saved++;
                      return null;
                    },
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text(file.name), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester.getSize(find.byKey(const Key('dismiss-image-preview'))),
        const Size(800, 600),
      );
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, 1);
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentViewer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
