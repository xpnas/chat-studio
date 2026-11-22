import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:chatstudio/data/chat_transport.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/person_api.dart';
import 'package:chatstudio/data/person_history_cache.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/state/app_controller.dart';
import 'package:chatstudio/state/person_controller.dart';
import 'support.dart';

class _CacheFaultTransport extends SocketChatTransport {
  final requests = <Map<String, dynamic>>[];
  void Function()? loseCachedPage;
  int runs = 0;
  @override
  void emit(String event, Map<String, dynamic> data) {
    if (event == 'run') runs++;
    if (event == 'app.resume') {
      requests.add(Map.of(data));
      if (data['id'] != '') {
        final lose = loseCachedPage;
        loseCachedPage = null;
        lose?.call();
      }
    }
    super.emit(event, data);
  }
}

void main() {
  final server = Platform.environment['CHATSTUDIO_TEST_SERVER'];
  test(
    'real stored BOT timeline: mixed pages, 300-reference cache, missing hit, corruption, ACL and remote clear',
    () async {
      final app = AppController(storage: MemoryStorage());
      final root = await Directory.systemTemp.createTemp(
        'person-history-matrix-',
      );
      final clients = <PersonController>[], caches = <PersonHistoryCache>[];
      String? userId;
      Future<void> until(
        Future<bool> Function() condition,
        String stage,
      ) async {
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!await condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'History matrix timeout: $stage; ${clients.map((c) => c.error).join()}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      try {
        await app.initialize();
        expect(
          await app.login(
            server!,
            'admin',
            Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
            true,
          ),
          true,
        );
        final api = app.api!, owner = app.account!.id;
        final bots = (await api.personConversations(owner)).sessions;
        final bot = bots.firstWhere((bot) => bot.title == 'Mobile Bot Cache'),
            peer = bots.firstWhere(
              (bot) => bot.title == 'Mobile Bot Cache Peer',
            );
        final seeded = await Process.run('node', [
          'tools/mock-provider/seed-person-history.mjs',
          bot.id,
          peer.id,
        ]);
        expect(seeded.exitCode, 0, reason: '${seeded.stderr}');
        Future<PersonController> connect(_CacheFaultTransport transport) async {
          final cache = PersonHistoryCache(root, server, '$owner', bot.id);
          caches.add(cache);
          final c = PersonController(
            api: StudioApi(api.address)
              ..token = api.token
              ..profile = api.profile,
            account: owner,
            sessionId: bot.id,
            cache: cache,
            identityValid: () => app.authenticated,
            transport: transport,
          );
          clients.add(c);
          await c.initialize();
          await until(
            () async => c.connected && !c.syncing && c.timeline.latest != null,
            'projected resume',
          );
          return c;
        }

        final t1 = _CacheFaultTransport(), c1 = await connect(t1);
        expect(c1.timeline.items.length, 150);
        expect(c1.timeline.latest!.messages.length, 75);
        expect(c1.timeline.latest!.cards.length, 75);
        final id = c1.timeline.latest!.id;
        await c1.loadOlder();
        await c1.loadOlder();
        expect(c1.timeline.latest!.id, id);
        expect(
          {
            ...c1.timeline.latest!.items.map((i) => i.key),
            ...c1.timeline.items.map((i) => i.key),
          }.length,
          300,
        );
        expect(c1.timeline.hasMore, false);
        final oldWindow = c1.timeline.items.map((i) => i.key).toList();
        await c1.saveCache();
        final t2 = _CacheFaultTransport(), c2 = await connect(t2);
        expect(t2.requests.first['id'], id);
        expect(c2.timeline.items.map((i) => i.key), oldWindow);
        final before = t2.requests.length;
        t2.loseCachedPage = c2.timeline.clear;
        c2.requestResume();
        await until(
          () async => !c2.syncing && c2.timeline.latest != null,
          'missing conditional page',
        );
        expect(t2.requests.length, before + 2);
        expect(t2.requests.last['id'], '');
        expect(t1.runs + t2.runs, 0);
        c1.onBackground();
        c2.onBackground();
        await c1.saveCache();
        await c2.saveCache();
        await c2.cache.file.writeAsString('{corrupted');
        final t3 = _CacheFaultTransport(), c3 = await connect(t3);
        expect(t3.requests.first['id'], '');
        expect(c3.timeline.items.length, 150);
        final oldPage = c3.timeline.latest!.raw;
        final flowId = c3.timeline.latest!.cards.keys.first;
        final oldDetail = await api.personFlowMessages(flowId);
        final peerSnapshot = await api.request(
          '/api/studio/person',
          query: {'session_id': peer.id},
        );
        await api.request(
          '/api/studio/person/clear',
          method: 'POST',
          body: {
            'session_id': peer.id,
            'expected_history_revision': peerSnapshot['history_revision'],
          },
        );
        final changedDetail = await api.personFlowMessages(flowId);
        expect(changedDetail.historyKey, isNot(oldDetail.historyKey));
        c3.draft.text = 'Preserve draft across Web clear';
        c3.timeline.beginReading();
        final snapshot = await api.request(
          '/api/studio/person',
          query: {'session_id': bot.id},
        );
        expect(snapshot['can_clear'], true);
        await api.request(
          '/api/studio/person/clear',
          method: 'POST',
          body: {
            'session_id': bot.id,
            'expected_history_revision': snapshot['history_revision'],
          },
        );
        await c3.refreshSnapshot();
        c3.requestResume(full: true);
        await until(
          () async =>
              !c3.syncing &&
              c3.timeline.latest != null &&
              c3.timeline.items.isEmpty,
          'remote clear',
        );
        expect(c3.draft.text, 'Preserve draft across Web clear');
        c3.onEvent('app.resumed', {
          'session_id': bot.id,
          ...oldPage,
          'messagesCached': false,
          'isWorking': false,
        });
        expect(c3.timeline.items, isEmpty);
        await expectLater(
          api.personFlowMessages(flowId),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
        );

        final username = 'matrix-${const Uuid().v4()}',
            password = const Uuid().v4();
        final managed = await api.request(
          '/api/auth/users',
          method: 'POST',
          body: {
            'username': username,
            'password': password,
            'role': 'admin',
            'profiles': ['default'],
            'defaultProfile': 'default',
          },
        );
        userId = '${asMap(managed['user'])['id']}';
        final login = await api.request(
          '/api/auth/login',
          method: 'POST',
          public: true,
          body: {'username': username, 'password': password},
        );
        final other = StudioApi(api.address)
          ..token = text(login['token'])
          ..profile = 'default';
        expect((await other.personConversations(userId)).sessions, isEmpty);
        await expectLater(
          other.personSnapshot(bot.id, userId),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
        );
        expect(
          await PersonHistoryCache(root, server, userId, bot.id).read(),
          isNull,
        );
        final workspace = await Directory(
          Platform.environment['WORKSPACE_BASE']!,
        ).createTemp('acl-bot-');
        final personal = await other.request(
          '/api/studio/person/conversations',
          method: 'POST',
          body: {
            'title': 'Mobile ACL fixture',
            'workspace': workspace.path,
            'model': {
              'profile': 'default',
              'provider': 'custom:mobile-test',
              'model': 'chatstudio-test',
              'apiMode': 'chat_completions',
            },
          },
        );
        final ownedId = text(asMap(personal['session'])['id']).isNotEmpty
            ? text(asMap(personal['session'])['id'])
            : text(personal['id']);
        expect(ownedId, isNotEmpty);
        final cache = PersonHistoryCache(root, server, userId, ownedId);
        caches.add(cache);
        final owned = PersonController(
          api: other,
          account: userId,
          sessionId: ownedId,
          cache: cache,
          identityValid: () => true,
          transport: _CacheFaultTransport(),
        );
        clients.add(owned);
        await owned.initialize();
        await until(
          () async => owned.connected && !owned.syncing,
          'owned account restore',
        );
        await api.request(
          '/api/auth/users/$userId',
          method: 'PUT',
          body: {'profiles': [], 'defaultProfile': null},
        );
        await owned.refreshSnapshot();
        expect(owned.snapshot?.session.id, ownedId);
        expect(owned.resourceAllowed, false);
        expect(owned.canSend, false);
      } finally {
        for (final c in clients) {
          c.dispose();
        }
        for (final cache in caches) {
          await cache.clear();
        }
        if (userId != null) {
          await app.api?.request('/api/auth/users/$userId', method: 'DELETE');
        }
        app.dispose();
        await root.delete(recursive: true);
      }
    },
    skip:
        server == null ||
        Platform.environment['CHATSTUDIO_TEST_BASELINE'] == 'legacy',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
