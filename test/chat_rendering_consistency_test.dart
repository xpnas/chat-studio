import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/person_models.dart';
import 'package:chatstudio/ui/person_screens.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:chatstudio/ui/widgets/attachment_tile.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'support.dart';
import 'person_widgets_test.dart' show widgetPerson;
import 'person_protocol_test.dart' show personPage, flow;

void main() {
  testWidgets('blank resume preserves an existing global session mode', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    final old = Conversation.fromJson({
      'id': 'global-chat',
      'agent': 'ekko-agent',
      'profile': 'default',
      'agent_mode': 'global',
      'model': 'model-a',
    });
    await h.controller.openConversation(old);
    h.transport.receive('resumed', {
      'session_id': old.id,
      'agent_mode': '',
      'isWorking': false,
      'messages': [],
    });
    expect(h.controller.agentMode, 'global');
    h.dispose();
  });

  testWidgets(
    'BOT shows peer input and completed output before persisted refresh',
    (tester) async {
      final h = TestHarness();
      await h.login();
      final c = widgetPerson(cards: false);
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
      c.onEvent('run.peer_user_message', {
        'session_id': c.sessionId,
        'message_id': 51,
        'input': 'Input from another device',
      });
      c.onEvent('run.started', {'session_id': c.sessionId, 'run_id': 'remote'});
      c.onEvent('run.completed', {
        'session_id': c.sessionId,
        'run_id': 'remote',
        'message_id': 52,
        'output': 'Finished response before refresh',
      });
      await tester.pump();
      expect(find.text('Input from another device'), findsOneWidget);
      expect(find.text('Finished response before refresh'), findsOneWidget);
      expect(c.timeline.messages, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'BOT groups assistant segments like single chat without crossing flow cards',
    (tester) async {
      final h = TestHarness();
      await h.login();
      final c = widgetPerson(cards: false);
      c.timeline.applyLatest(
        PersonTimelinePage.fromJson(
          personPage(
            refs: [
              {'kind': 'message', 'id': '1'},
              {'kind': 'message', 'id': '2'},
              {'kind': 'flow', 'id': 'f'},
              {'kind': 'message', 'id': '3'},
            ],
            messages: [
              {'id': 1, 'role': 'assistant', 'content': 'First segment'},
              {'id': 2, 'role': 'assistant', 'content': 'Second segment'},
              {'id': 3, 'role': 'assistant', 'content': 'After collaboration'},
            ],
            cards: [flow('f')],
          ),
        ),
      );
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
      final bubbles = tester
          .widgetList<MessageBubble>(find.byType(MessageBubble))
          .toList();
      expect(bubbles.length, 2);
      expect(
        bubbles.map((b) => b.message.content),
        contains('First segment\n\nSecond segment'),
      );
      expect(find.text('Flow f'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'existing legacy chat with blank mode remains sendable after resume',
    (tester) async {
      final h = TestHarness();
      await h.login();
      final old = Conversation.fromJson({
        'id': 'legacy-chat',
        'title': 'Existing chat',
        'profile': 'default',
        'agent': 'ekko-agent',
        'source': 'builtin_agent',
        'agent_mode': '',
        'model': 'model-a',
        'provider': 'test',
      });
      await h.controller.openConversation(old);
      h.transport.receive('resumed', {
        'session_id': old.id,
        'agent_mode': '',
        'isWorking': false,
        'messages': [
          {'id': 1, 'role': 'assistant', 'content': 'Saved reply'},
        ],
      });
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('message-input')),
        'Continue the existing chat',
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('send-button')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pump();
      expect(
        h.transport.emitted.lastWhere((e) => e.$1 == 'run').$2['session_id'],
        old.id,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'ordinary typing enables sending and dispatches exactly one ordinary run',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('message-input')),
        'Send from ordinary chat',
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('send-button')))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pump();
      expect(h.transport.emitted.where((e) => e.$1 == 'run').length, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'BOT streaming redraws every delta and stays at latest while keyboard and content resize',
    (tester) async {
      tester.view.physicalSize = const Size(390, 660);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final h = TestHarness();
      await h.login();
      final c = widgetPerson(cards: false);
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
      c.syncing = false;
      expect(c.send('Start streaming'), true);
      c.onEvent('run.started', {
        'session_id': c.sessionId,
        'run_id': 'stream-check',
      });
      c.onEvent('message.delta', {
        'session_id': c.sessionId,
        'run_id': 'stream-check',
        'delta': 'First fragment',
      });
      await tester.pumpAndSettle();
      expect(find.text('First fragment'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        c.onEvent('message.delta', {
          'session_id': c.sessionId,
          'run_id': 'stream-check',
          'delta': ' stream fragment $i',
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.textContaining('stream fragment 9'), findsOneWidget);
      expect(c.timeline.readingOlder, false);
      final list = tester.widget<ListView>(
        find
            .descendant(
              of: find.byType(PersonScreen),
              matching: find.byType(ListView),
            )
            .first,
      );
      expect(list.reverse, true);
      expect(list.controller!.offset, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      h.controller.dispose();
    },
  );

  testWidgets(
    'ordinary and BOT bodies render identical pixels through the same bubble',
    (tester) async {
      final h = TestHarness();
      await h.login();
      final bot = widgetPerson(cards: false);
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      Future<List<int>> capture(ChatMessage message, bool useBot) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: chatstudioTheme(Brightness.light),
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: key,
                  child: MessageBubble(
                    message: message,
                    controller: useBot ? bot : h.controller,
                    senderLabel: 'Assistant',
                    agentId: 'ekko-agent',
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          image.dispose();
          return bytes!.buffer.asUint8List();
        });
        return bytes!;
      }

      for (final message in [
        const ChatMessage(
          id: 'user',
          role: 'user',
          content: 'A user message with a draft.',
        ),
        const ChatMessage(
          id: 'assistant',
          role: 'assistant',
          content:
              '### Heading\n\n**Bold** and a paragraph.\n\n- First item\n- Second item\n\n```dart\nfinal answer = 42;\n```',
        ),
        const ChatMessage(
          id: 'stream',
          role: 'assistant',
          content: 'A partial streaming response',
          pending: true,
        ),
        const ChatMessage(
          id: 'file',
          role: 'assistant',
          content: 'Result attached',
          attachments: [
            MessageAttachment(
              name: 'result.txt',
              path: '/result.txt',
              mimeType: 'text/plain',
              size: 42,
            ),
          ],
        ),
      ]) {
        final ordinary = await capture(message, false);
        final person = await capture(message, true);
        expect(
          person,
          orderedEquals(ordinary),
          reason: '${message.id} uses the same rendered presentation',
        );
        if (message.attachments.isNotEmpty) {
          expect(find.byType(AttachmentTile), findsOneWidget);
        }
      }
      await tester.pumpWidget(const SizedBox());
      bot.dispose();
      h.controller.dispose();
    },
  );
}
