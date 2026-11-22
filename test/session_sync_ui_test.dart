import 'dart:convert';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/state/conversation_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

Map<String, dynamic> observed({
  bool working = false,
  bool unread = true,
  int message = 2,
  int attention = 0,
}) => {
  'sessionId': 'history-1',
  'profile': 'default',
  'working': working,
  'unread': unread,
  'lastMessageId': message,
  'readMessageId': 0,
  'lastAttentionId': attention,
  'readAttentionId': 0,
};
void main() {
  testWidgets(
    'unopened remote completion shows unread without loading its transcript or claiming success',
    (tester) async {
      final h = TestHarness();
      await h.login();
      final conversation = h.controller.conversations.single;
      final before = h.requests
          .where((r) => r.url.path.endsWith('/messages/paginated'))
          .length;
      h.sessionSync.receive('sessions.state.snapshot', {
        'sessions': [observed(working: true, unread: false)],
      });
      expect(
        h.controller.taskStatus(conversation),
        ConversationTaskStatus.running,
      );
      h.sessionSync.receive('sessions.state.updated', observed());
      expect(
        h.controller.taskStatus(conversation),
        ConversationTaskStatus.idle,
      );
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('对话记录'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('session-unread:history-1')),
        findsOneWidget,
      );
      expect(
        h.requests
            .where((r) => r.url.path.endsWith('/messages/paginated'))
            .length,
        before,
      );
      expect(h.transport.emitted.where((event) => event.$1 == 'run'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'reading an old window does not ACK until latest completed messages are painted',
    (tester) async {
      final h = TestHarness();
      final messages = [
        for (var i = 1; i <= 80; i++)
          {
            'id': i,
            'role': i.isEven ? 'assistant' : 'user',
            'content': 'History row $i with enough content to scroll.',
          },
      ];
      h.override = (r) async => r.url.path.endsWith('/messages/paginated')
          ? http.Response(
              jsonEncode({
                'messages': messages,
                'offset': 0,
                'total': 80,
                'hasMore': false,
              }),
              200,
            )
          : h.response(r);
      await h.login();
      await h.controller.openConversation(h.controller.conversations.single);
      h.transport.receive('resumed', {
        'session_id': 'history-1',
        'messages': messages,
        'isWorking': false,
        'messageLoadedCount': 80,
      });
      h.sessionSync.receive('sessions.state.snapshot', {
        'sessions': [observed(unread: false, message: 80)],
      });
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(400);
      await tester.pumpAndSettle();
      h.sessionSync.receive('sessions.state.updated', observed(message: 80));
      await tester.pumpAndSettle();
      expect(h.sessionSync.reads, isEmpty);
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(h.sessionSync.reads.single, {
        'sessionId': 'history-1',
        'messageId': 80,
        'attentionId': 0,
      });
      expect(h.transport.emitted.where((event) => event.$1 == 'run'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'failed ACK and unknown attention preserve unread; scope changes discard old callbacks',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.openConversation(
        const Conversation(id: 'history-1', title: 'History'),
      );
      h.transport.receive('resumed', {
        'session_id': 'history-1',
        'isWorking': false,
        'messages': [
          {'id': 2, 'role': 'assistant', 'content': 'Shown'},
        ],
      });
      h.sessionSync.receive('sessions.state.snapshot', {
        'sessions': [observed(attention: 2)],
      });
      expect(await h.controller.confirmVisibleRead(atLatest: true), false);
      expect(h.sessionSync.reads, isEmpty);
      h.sessionSync.receive('sessions.state.updated', observed());
      h.sessionSync.readReply = () async => {'ok': false};
      expect(await h.controller.confirmVisibleRead(atLatest: true), false);
      expect(
        h.controller.sessionSync.projection.sessions['history-1']!.unread,
        true,
      );
      final callback = h.sessionSync.listener!;
      final connections = h.sessionSync.connections;
      h.controller.onBackground();
      h.controller.onForeground();
      expect(h.sessionSync.connections, connections + 1);
      callback('sessions.state.snapshot', {
        'sessions': [observed()],
      });
      expect(h.controller.sessionSync.projection.sessions, isEmpty);
      await h.controller.switchProfile('work');
      callback('sessions.state.updated', observed());
      expect(h.controller.sessionSync.projection.sessions, isEmpty);
    },
  );
}
