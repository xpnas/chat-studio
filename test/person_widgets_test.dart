import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/person_models.dart';
import 'package:chatstudio/data/person_history_cache.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/state/app_controller.dart';
import 'package:chatstudio/state/person_controller.dart';
import 'package:chatstudio/state/person_list_controller.dart';
import 'package:chatstudio/ui/person_screens.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'package:chatstudio/ui/widgets/attachment_tile.dart';
import 'person_protocol_test.dart' show personPage, flow;
import 'session_tasks_test.dart' show taskApi, jsonResponse;
import 'support.dart';

PersonController widgetPerson({bool cards = true, StudioApi? client}) {
  final api =
      client ??
      taskApi(
        (r) => jsonResponse({
          'session': {
            'id': 'person-main-a',
            'studio_user_id': 7,
            'title': 'Configured BOT',
          },
          'settings': {
            'model': {'model': 'Saved model'},
            'agents': [
              {'id': 'worker'},
            ],
          },
          'tasks': [],
          'interactions': [],
          'history_revision': 0,
          'profiles': ['work', 'other', 'default'],
        }),
      );
  final c = PersonController(
    api: api,
    account: 7,
    sessionId: 'person-main-a',
    cache: PersonHistoryCache(
      Directory('.local/person-widget-cache'),
      'widget-server',
      '7',
      'person-main-a',
    ),
    identityValid: () => true,
    transport: FakeTransport(),
    observer: FakeSessionSyncTransport(),
  );
  c.snapshot = PersonSnapshot.fromJson({
    'session': {
      'id': c.sessionId,
      'studio_user_id': 7,
      'title': 'Configured BOT',
    },
    'settings': {
      'model': {'model': 'Saved model'},
      'agents': [
        {'id': 'worker'},
      ],
    },
    'tasks': [],
    'interactions': [],
  });
  c.timeline.applyLatest(
    PersonTimelinePage.fromJson(
      cards
          ? personPage(
              refs: [
                {'kind': 'flow', 'id': 'f'},
              ],
              cards: [flow('f')],
            )
          : personPage(),
    ),
  );
  c.connected = true;
  c.resourceAllowed = true;
  return c;
}

void main() {
  testWidgets(
    'BOT cards at the bottom do not acknowledge an assistant message outside the painted viewport',
    (tester) async {
      final c = widgetPerson(cards: false),
          app = AppController(storage: MemoryStorage());
      final observer = c.sync.transport as FakeSessionSyncTransport;
      observer.sessions = [
        {
          'sessionId': c.sessionId,
          'profile': 'resource',
          'working': false,
          'unread': true,
          'lastMessageId': 99,
          'readMessageId': 0,
          'lastAttentionId': 0,
          'readAttentionId': 0,
        },
      ];
      final refs = <Map<String, dynamic>>[
        {'kind': 'message', 'id': '7'},
        for (var i = 0; i < 20; i++) {'kind': 'flow', 'id': 'f$i'},
      ];
      final cards = [for (var i = 0; i < 20; i++) flow('f$i')];
      c.timeline.applyLatest(
        PersonTimelinePage.fromJson(
          personPage(
            refs: refs,
            messages: [
              {
                'id': 7,
                'role': 'assistant',
                'content': 'Never painted at the bottom',
              },
            ],
            cards: cards,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PersonScreen(app: app, sessionId: c.sessionId, controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(observer.reads, isEmpty);
      c.timeline.applyLatest(
        PersonTimelinePage.fromJson(
          personPage(
            id: 'new',
            refs: [
              ...refs.skip(1),
              {'kind': 'message', 'id': '8'},
            ],
            messages: [
              {'id': 8, 'role': 'assistant', 'content': 'Actually visible'},
            ],
            cards: cards,
          ),
        ),
      );
      c.changed();
      await tester.pumpAndSettle();
      expect(observer.reads.single['messageId'], 8);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      app.dispose();
    },
  );
  testWidgets(
    'authorized BOT image preview reports revoked access and external links never become authenticated attachments',
    (tester) async {
      final requests = <Uri>[];
      final api = taskApi((request) {
        requests.add(request.url);
        return jsonResponse({'error': 'denied'}, 403);
      });
      final c = widgetPerson(client: api);
      final message = MessageBubble(
        message: const ChatMessage(
          id: '7',
          role: 'assistant',
          content:
              '[local](http://localhost:8080/api/studio/files/download?path=/result.txt) [external](https://unrelated.example/api/studio/files/download?path=/private.txt)',
        ),
        controller: c,
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: message)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('external'));
      await tester.pumpAndSettle();
      expect(find.text('打开外部链接？'), findsOneWidget);
      expect(
        requests.where((uri) => uri.path.startsWith('/api/studio/files/')),
        isEmpty,
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: AttachmentViewer(
            controller: c,
            file: const MessageAttachment(
              name: 'image.png',
              path: '/revoked/image.png',
              mimeType: 'image/png',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AttachmentViewer), findsOneWidget);
      expect(find.textContaining('没有权限查看此附件'), findsWidgets);
      expect(
        requests
            .where((uri) => uri.path.startsWith('/api/studio/files/'))
            .single
            .host,
        'localhost',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'card-only BOT page stays visible with a BOT model control and retained draft',
    (tester) async {
      final c = widgetPerson(), app = AppController(storage: MemoryStorage());
      c.draft.text = 'BOT-scoped draft';
      await tester.pumpWidget(
        MaterialApp(
          home: PersonScreen(app: app, sessionId: c.sessionId, controller: c),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Flow f'), findsOneWidget);
      expect(find.text('开始 BOT 对话'), findsNothing);
      expect(find.text('BOT-scoped draft'), findsOneWidget);
      expect(find.byKey(const Key('model-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      app.dispose();
    },
  );
  testWidgets(
    'durable approval has no permanent option and structured question reuses question component',
    (tester) async {
      final answers = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonQuestion(
              event: {
                'kind': 'approval.requested',
                'description': 'Approve once',
                'durable': true,
                'allow_permanent': false,
              },
              enabled: true,
              submitting: false,
              onAnswer: answers.add,
            ),
          ),
        ),
      );
      expect(find.textContaining('永久'), findsNothing);
      await tester.tap(find.text('仅允许本次'));
      expect(answers, ['once']);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonQuestion(
              event: {
                'kind': 'clarify.requested',
                'question': jsonEncode([
                  {
                    'qid': 'one',
                    'question': 'Which?',
                    'options': ['A', 'B'],
                  },
                ]),
                'durable': true,
              },
              enabled: true,
              submitting: false,
              onAnswer: answers.add,
            ),
          ),
        ),
      );
      expect(find.byType(PersonQuestion), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'BOT list uses server paging/search and does not filter by ordinary Profile',
    (tester) async {
      final h = TestHarness();
      await h.login();
      final owner = h.controller.account!.id;
      h.override = (r) async {
        if (r.url.path == '/api/studio/person/conversations') {
          final offset = r.url.queryParameters['offset'];
          return jsonResponse({
            'sessions': [
              {
                'id': 'person-main-${offset == '50' ? 'b' : 'a'}',
                'studio_user_id': owner,
                'title': offset == '50' ? 'Second BOT' : 'First BOT',
                'profile': 'resource-profile',
              },
            ],
            'next_offset': offset == '50' ? null : 50,
          });
        }
        return h.response(r);
      };
      final list = PersonListController(h.controller.api!, owner, () => true);
      await tester.pumpWidget(
        MaterialApp(
          home: PersonListScreen(app: h.controller, controller: list),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First BOT'), findsOneWidget);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.text('Second BOT'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Search');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(
        h.requests
            .lastWhere((r) => r.url.path == '/api/studio/person/conversations')
            .url
            .queryParameters['search'],
        'Search',
      );
      await tester.pumpWidget(const SizedBox());
      list.dispose();
      h.controller.dispose();
    },
  );
  testWidgets(
    'flow form rejects invalid finite rounds before any create and removal keeps groups renderable',
    (tester) async {
      final c = widgetPerson();
      await tester.pumpWidget(MaterialApp(home: PersonFlowForm(person: c)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Title');
      await tester.enterText(find.byType(TextField).at(1), 'Outcome');
      await tester.enterText(find.byType(TextField).at(2), '0');
      await tester.scrollUntilVisible(
        find.text('预览并确认'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('预览并确认'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('请填写目标、1–13 个阶段及 1–1000 轮'),
        ),
        findsOneWidget,
      );
      expect(c.operation.payload, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
