import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

List<Map<String, dynamic>> messages(int start, int end) => [
  for (var id = start; id <= end; id++)
    {
      'id': id,
      'role': id.isEven ? 'assistant' : 'user',
      'content': 'message $id',
    },
];
Future<TestHarness> opened() async {
  final h = TestHarness();
  await h.login();
  await h.controller.openConversation(h.controller.conversations.single);
  h.transport.receive('resumed', {
    'session_id': 'history-1',
    'isWorking': false,
    'messages': messages(1, 4),
    'messageLoadedCount': 4,
    'messageTotal': 4,
  });
  h.controller.draft.text = 'typing is preserved';
  h.controller.draft.scrollOffset = 300;
  h.controller.beginReadingWindow();
  return h;
}

void main() {
  test(
    'reconnect merges live state behind the old reading window and latest is fetched explicitly',
    () async {
      final h = await opened();
      addTearDown(h.dispose);
      h.override = (r) async => r.url.path.endsWith('/messages/paginated')
          ? http.Response(
              jsonEncode({
                'messages': messages(5, 6),
                'offset': 0,
                'total': 6,
                'hasMore': true,
              }),
              200,
            )
          : h.response(r);
      final before = h.controller.displayMessages
          .map((message) => message.id)
          .toList();
      h.transport.receive('resumed', {
        'session_id': 'history-1',
        'isWorking': false,
        'messages': messages(5, 6),
        'messageLoadedCount': 2,
        'messageTotal': 6,
        'hasMoreBefore': true,
      });
      expect(h.controller.displayMessages.map((message) => message.id), before);
      expect(h.controller.timeline.messages.last.id, '6');
      expect(h.controller.hasNewerMessages, true);
      expect(h.controller.draft.scrollOffset, 300);
      final count = h.requests
          .where((request) => request.url.path.endsWith('/messages/paginated'))
          .length;
      await h.controller.showLatestHistory();
      expect(
        h.requests
            .where(
              (request) => request.url.path.endsWith('/messages/paginated'),
            )
            .length,
        count + 1,
      );
      expect(h.controller.displayMessages.map((message) => message.id), [
        '5',
        '6',
      ]);
      expect(h.controller.readingOlderWindow, false);
      expect(h.controller.hasNewerMessages, false);
      expect(h.controller.draft.text, 'typing is preserved');
      expect(h.transport.emitted.where((event) => event.$1 == 'run'), isEmpty);
    },
  );
  test(
    'authoritative empty history invalidates the old window, late pages and replayed terminal run content',
    () async {
      final h = await opened();
      addTearDown(h.dispose);
      h.transport.receive('run.started', {
        'session_id': 'history-1',
        'run_id': 'finished',
      });
      h.transport.receive('run.completed', {
        'session_id': 'history-1',
        'run_id': 'finished',
      });
      final page = Completer<http.Response>();
      h.override = (r) async => r.url.path.endsWith('/messages/paginated')
          ? page.future
          : h.response(r);
      h.controller.hasMoreMessages = true;
      final pending = h.controller.loadHistory(more: true);
      await Future<void>.delayed(Duration.zero);
      h.transport.receive('resumed', {
        'session_id': 'history-1',
        'isWorking': false,
        'messages': [],
        'messageTotal': 0,
        'messageLoadedCount': 0,
        'events': [
          {
            'event': 'message.delta',
            'data': {'run_id': 'finished', 'delta': 'must not return'},
          },
        ],
      });
      expect(h.controller.displayMessages, isEmpty);
      expect(h.controller.readingOlderWindow, false);
      expect(h.controller.draft.text, 'typing is preserved');
      page.complete(
        http.Response(
          jsonEncode({
            'messages': messages(1, 2),
            'offset': 4,
            'total': 4,
            'hasMore': false,
          }),
          200,
        ),
      );
      await pending;
      h.transport.receive('message.delta', {
        'session_id': 'history-1',
        'run_id': 'finished',
        'delta': 'late old reply',
      });
      expect(h.controller.displayMessages, isEmpty);
      expect(h.controller.draft.scrollOffset, 0);
    },
  );
  test(
    'missing message fields, empty observer snapshots and list omissions do not clear history or draft',
    () async {
      final h = await opened();
      addTearDown(h.dispose);
      h.transport.receive('resumed', {
        'session_id': 'history-1',
        'isWorking': false,
      });
      h.sessionSync.receive('sessions.state.snapshot', {'sessions': []});
      h.override = (r) async => r.url.path == '/api/studio/sessions'
          ? http.Response('{"sessions":[],"hasMore":false}', 200)
          : h.response(r);
      await h.controller.refreshSessions();
      expect(h.controller.displayMessages.map((message) => message.id), [
        '1',
        '2',
        '3',
        '4',
      ]);
      expect(h.controller.sessionId, 'history-1');
      expect(h.controller.draft.text, 'typing is preserved');
    },
  );
}
