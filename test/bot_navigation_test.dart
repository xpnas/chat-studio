import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/person_models.dart';
import 'package:chatstudio/ui/person_screens.dart';
import 'package:chatstudio/ui/widgets/conversation_drawer.dart';
import 'package:chatstudio/ui/widgets/chat_swipe_region.dart';
import 'person_protocol_test.dart' show personPage, flow;
import 'person_widgets_test.dart' show widgetPerson;
import 'session_tasks_test.dart' show jsonResponse;
import 'support.dart';

void main() {
  testWidgets(
    'BOT tab lists account BOTs beside single/group chats and opens their own route',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.override = (r) async => r.url.path == '/api/studio/person/conversations'
          ? jsonResponse({
              'sessions': [
                {
                  'id': 'person-main-a',
                  'studio_user_id': h.controller.account!.id,
                  'title': 'Configured BOT',
                  'profile': 'resource',
                },
              ],
              'next_offset': null,
            })
          : h.response(r);
      final opened = <Conversation>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: ConversationDrawer(
              controller: h.controller,
              onNewChat: () {},
              onOpenConversation: opened.add,
              onOpenGroup: (_) {},
            ),
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('单聊'), findsOneWidget);
      expect(find.text('群聊'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bot-tab')));
      await tester.pumpAndSettle();
      expect(find.text('搜索 BOT'), findsOneWidget);
      expect(find.text('Configured BOT'), findsOneWidget);
      expect(find.text('新建对话'), findsOneWidget);
      await tester.tap(find.text('Configured BOT'));
      await tester.pumpAndSettle();
      expect(opened.single.id, 'person-main-a');
      expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    },
  );

  testWidgets(
    'BOT chat uses shared composer, left-swipe activities, right-swipe list and isolated send',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.controller.draft.text = 'ordinary draft';
      h.override = (r) async => r.url.path == '/api/studio/person/conversations'
          ? jsonResponse({
              'sessions': [
                {
                  'id': 'person-main-a',
                  'studio_user_id': h.controller.account!.id,
                  'title': 'Configured BOT',
                },
              ],
              'next_offset': null,
            })
          : h.response(r);
      final c = widgetPerson(cards: false);
      c.timeline.applyLatest(
        PersonTimelinePage.fromJson(
          personPage(
            refs: [
              {'kind': 'message', 'id': '7'},
              {'kind': 'flow', 'id': 'active'},
            ],
            messages: [
              {
                'id': 7,
                'role': 'assistant',
                'content': '### Shared Markdown\n\nA readable BOT response.',
              },
            ],
            cards: [flow('active', state: 'active')],
          ),
        ),
      );
      c.draft.text = 'BOT draft';
      await tester.pumpWidget(
        MaterialApp(
          home: PersonScreen(
            app: h.controller,
            sessionId: c.sessionId,
            controller: c,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('composer-surface')), findsOneWidget);
      expect(find.byKey(const Key('model-button')), findsOneWidget);
      expect(find.byKey(const Key('reasoning-button')), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        'BOT draft',
      );
      final scaffold = tester.state<ScaffoldState>(
        find
            .descendant(
              of: find.byType(PersonScreen),
              matching: find.byType(Scaffold),
            )
            .first,
      );
      Future<void> swipe(bool right) async {
        final rect = tester.getRect(find.byType(ChatSwipeRegion));
        await tester.timedDragFrom(
          Offset(rect.center.dx + (right ? -85 : 85), rect.center.dy),
          Offset(right ? 170 : -170, 0),
          const Duration(milliseconds: 250),
        );
        await tester.pumpAndSettle();
      }

      await swipe(false);
      expect(scaffold.isEndDrawerOpen, true);
      expect(
        find.descendant(
          of: find.byKey(const Key('bot-activity-drawer')),
          matching: find.text('Flow active'),
        ),
        findsOneWidget,
      );
      scaffold.closeEndDrawer();
      await tester.pumpAndSettle();
      await swipe(true);
      expect(scaffold.isDrawerOpen, true);
      expect(
        find.descendant(
          of: find.byType(ConversationDrawer),
          matching: find.text('搜索 BOT'),
        ),
        findsOneWidget,
      );
      final tabs = find.descendant(
        of: find.byType(ConversationDrawer),
        matching: find.byType(TabBar),
      );
      expect(tabs, findsOneWidget);
      TabController selectedTabs() =>
          DefaultTabController.of(tester.element(tabs));
      expect(selectedTabs().index, 2);
      for (final label in ['单聊', '群聊', 'BOT', '历史']) {
        expect(
          find.descendant(of: tabs, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(find.byKey(const Key('bot-list-drawer')), findsNothing);
      await tester.tap(find.descendant(of: tabs, matching: find.text('单聊')));
      await tester.pumpAndSettle();
      expect(selectedTabs().index, 0);
      await tester.tap(find.byKey(const Key('bot-tab')));
      await tester.pumpAndSettle();
      expect(selectedTabs().index, 2);
      await tester.tap(
        find.descendant(
          of: find.byType(ConversationDrawer),
          matching: find.text('Configured BOT'),
        ),
      );
      await tester.pumpAndSettle();
      expect(scaffold.isDrawerOpen, false);
      expect(find.byType(PersonScreen), findsOneWidget);
      expect(c.draft.text, 'BOT draft');
      await tester.drag(
        find.byKey(const Key('message-input')),
        const Offset(-170, 0),
      );
      await tester.pumpAndSettle();
      expect(scaffold.isEndDrawerOpen, false);
      c.syncing = false;
      c.connected = true;
      c.changed();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pump();
      final runs = (c.transport as FakeTransport).emitted.where(
        (e) => e.$1 == 'run',
      );
      expect(runs.length, 1);
      expect(runs.single.$2['session_id'], c.sessionId);
      expect(runs.single.$2.containsKey('model'), false);
      expect(h.controller.draft.text, 'ordinary draft');
      expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      h.controller.dispose();
    },
  );
}
