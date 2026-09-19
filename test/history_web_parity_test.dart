import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/state/history_controller.dart';
import 'package:chatstudio/ui/history_detail_screen.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'support.dart';

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> entry(String id, String source, {bool pinned = false}) => {
  'id': id,
  'source': source,
  'title': id,
  'agent': 'hermes',
  'is_pinned': pinned,
  'webui_imported': true,
  'ended_at': 100,
};

void main() {
  test(
    'history links use the Web hash route and preserve scoped identifiers',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final history = HistoryController(h.controller.api!, 'work');
      addTearDown(history.dispose);
      final row = HistoryEntry(entry('session/a #1', 'cli'), 'work & review');
      final link = history.linkFor(row);
      expect(link.origin, h.controller.api!.address.uri.origin);
      expect(link.path, '/');
      expect(link.query, isEmpty);
      final route = Uri.parse(link.fragment);
      expect(route.pathSegments, [
        'hermes',
        'history',
        'session',
        'session/a #1',
      ]);
      expect(route.queryParameters['profile'], 'work & review');
      expect(link.toString(), contains('#/hermes/history/session/'));
    },
  );

  test(
    'source groups, pinned rows, raw offsets and empty pages match Web',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final history = HistoryController(h.controller.api!, 'work');
      addTearDown(history.dispose);
      var page = 0;
      h.override = (r) async {
        if (r.url.path.endsWith('/hermes/groups')) {
          return json({
            'groups': [
              {
                'source': 'cron',
                'sessions': [entry('cron', 'cron')],
              },
              {
                'source': 'cli',
                'sessions': [entry('cli', 'cli')],
              },
              {
                'source': 'api_server',
                'hasMore': true,
                'sessions': [
                  entry('pinned', 'api_server', pinned: true),
                  entry('api', 'api_server'),
                ],
              },
            ],
            'included': [entry('included', 'telegram')],
          });
        }
        if (r.url.path.endsWith('/hermes')) {
          page++;
          expect(r.url.queryParameters['offset'], page == 1 ? '2' : '4');
          expect(r.url.queryParameters['source'], 'api_server');
          return json({
            'hasMore': true,
            'sessions': page == 1
                ? [entry('api', 'api_server'), entry('new', 'api_server')]
                : [],
          });
        }
        return h.response(r);
      };
      await history.refresh();
      expect(history.groups.map((g) => g.source), [
        'api_server',
        'cli',
        'telegram',
        'cron',
      ]);
      expect(history.rows(pinned: true).single.conversation.id, 'pinned');
      expect(history.rows(source: 'api_server').single.conversation.id, 'api');
      expect(history.rows(source: 'cli').single.conversation.updatedAt, 100);
      final group = history.groups.first;
      await history.loadMore(group);
      expect(history.rows(source: 'api_server').length, 2);
      await history.loadMore(group);
      await history.loadMore(group);
      expect(group.hasMore, false);
      expect(page, 2);
      expect(
        h.requests
            .where((r) => r.url.path.startsWith('/api/studio/sessions/hermes'))
            .every((r) => r.url.queryParameters['profile'] == 'work'),
        true,
      );
    },
  );

  test(
    'failed history can retry; old and disposed responses cannot replace rows',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final history = HistoryController(h.controller.api!, 'default');
      h.override = (_) async => json({'error': 'unavailable'}, 503);
      await history.refresh();
      expect(history.loading, false);
      expect(history.error, isNotNull);
      final pending = Completer<http.Response>();
      h.override = (_) => pending.future;
      final old = history.refresh();
      h.override = (_) async => json({
        'groups': [
          {
            'source': 'cli',
            'sessions': [entry('fresh', 'cli')],
          },
        ],
      });
      await history.refresh();
      pending.complete(json({'groups': []}));
      await old;
      expect(history.entries.values.single.conversation.id, 'fresh');
      expect(history.error, isNull);
      final late = Completer<http.Response>();
      h.override = (_) => late.future;
      final loading = history.refresh();
      history.dispose();
      late.complete(json({'groups': []}));
      await loading;
      expect(history.entries.values.single.conversation.id, 'fresh');
    },
  );

  test(
    'history actions use server booleans and profile-aware batch targets',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final history = HistoryController(h.controller.api!, 'work');
      addTearDown(history.dispose);
      final row = HistoryEntry(entry('history-id', 'cli'), 'work');
      for (final action in ['pin', 'import', 'unarchive', 'delete']) {
        await history.action(row, action);
        final req = h.requests.lastWhere((r) => r.method != 'GET');
        expect(req.url.queryParameters['profile'], 'work');
        expect(req.method, action == 'delete' ? 'DELETE' : 'POST');
        if (action == 'pin') expect(jsonDecode(req.body), {'is_pinned': true});
        if (action == 'import') {
          expect(req.url.path, '/api/studio/sessions/hermes/history-id/import');
        }
      }
      await history.deleteSelected([
        row,
        HistoryEntry({
          ...entry('history-id', 'cli'),
          'profile': 'default',
        }, 'work'),
      ]);
      final batch = h.requests.lastWhere((r) => r.method == 'POST');
      expect(jsonDecode(batch.body)['sessions'], [
        {'id': 'history-id', 'profile': 'work'},
        {'id': 'history-id', 'profile': 'default'},
      ]);
    },
  );

  for (final legacy in [false, true]) {
    testWidgets(
      'history detail is isolated, shared rendering, legacy=$legacy',
      (tester) async {
        final h = TestHarness();
        await h.login();
        h.controller.sessionId = 'active-chat';
        h.controller.draft.text = 'keep draft';
        h.controller.timeline.replace(const [
          ChatMessage(
            id: 'active',
            role: 'assistant',
            content: 'active answer',
          ),
        ]);
        h.override = (r) async {
          if (r.url.path.endsWith('/messages/paginated')) {
            expect(r.url.queryParameters['profile'], 'work');
            if (legacy) return json({'error': 'not found'}, 404);
            return json({
              'messages': [
                {'id': 1, 'role': 'assistant', 'content': '**history answer**'},
              ],
              'hasMore': false,
            });
          }
          if (r.url.path == '/api/studio/sessions/hermes/old') {
            return json({
              'session': {
                'messages': [
                  {
                    'id': 1,
                    'role': 'assistant',
                    'content': '**history answer**',
                  },
                ],
              },
            });
          }
          return h.response(r);
        };
        await tester.pumpWidget(
          MaterialApp(
            home: HistoryDetailScreen(
              controller: h.controller,
              conversation: const Conversation(
                id: 'old',
                title: 'Old history',
                profile: 'work',
                agent: 'hermes',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MessageBubble), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(h.controller.sessionId, 'active-chat');
        expect(h.controller.draft.text, 'keep draft');
        expect(h.controller.timeline.messages.single.content, 'active answer');
        final count = h.requests.length;
        await tester.pump(const Duration(seconds: 3));
        expect(h.requests.length, count);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        h.dispose();
      },
    );
  }

  testWidgets('history detail failure stops loading and retry recovers', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    var fail = true;
    h.override = (r) async => r.url.path.endsWith('/messages/paginated') && fail
        ? json({'error': 'temporary'}, 503)
        : h.response(r);
    await tester.pumpWidget(
      MaterialApp(
        home: HistoryDetailScreen(
          controller: h.controller,
          conversation: const Conversation(id: 'old', title: 'Old'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      h.requests.where((r) => r.url.path == '/api/studio/sessions/hermes/old'),
      isEmpty,
    );
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(find.byType(MaterialBanner), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    h.dispose();
  });
}
