import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/main.dart';
import 'support.dart';

void seed(TestHarness h, {int count = 30}) {
  h.controller.sessionId = 'scroll-history';
  h.transport.receive('resumed', {
    'session_id': 'scroll-history',
    'isWorking': false,
    'messageLoadedCount': count,
    'hasMoreBefore': true,
    'messages': [
      for (var i = 0; i < count; i++)
        {'id': '$i', 'role': 'user', 'content': '消息 $i\n阅读已有内容，保持滚动位置。'},
    ],
    'events': [],
  });
}

http.Response page(
  int offset, {
  bool more = true,
  bool empty = false,
  int? next,
}) => http.Response(
  jsonEncode({
    'messages': empty
        ? []
        : [
            for (var i = 0; i < 20; i++)
              {
                'id': 'old:$offset:$i',
                'role': 'user',
                'content': 'Earlier message $offset-$i',
              },
          ],
    'offset': next == null ? offset : next - (empty ? 0 : 20),
    'hasMore': more,
    'total': 200,
  }),
  200,
);
ScrollController scroll(WidgetTester tester) =>
    tester.widget<ListView>(find.byKey(const Key('message-list'))).controller!;
void main() {
  testWidgets(
    'near older edge auto-loads once, keeps visible anchor, stops after final page',
    (tester) async {
      final h = TestHarness();
      await h.login();
      seed(h);
      final pending = Completer<http.Response>();
      var requests = 0;
      h.override = (r) async {
        if (!r.url.path.endsWith('/messages/paginated')) return h.response(r);
        requests++;
        expect(r.url.queryParameters['offset'], '30');
        return pending.future;
      };
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      expect(requests, 0);
      final controller = scroll(tester);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(requests, 1);
      expect(find.text('加载更早的消息'), findsNothing);
      final visible = find.text('消息 0\n阅读已有内容，保持滚动位置。');
      for (var i = 0; i < 5; i++) {
        controller.jumpTo(controller.position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(requests, 1);
      await tester.pump(const Duration(milliseconds: 300));
      final before = tester.getTopLeft(visible).dy;
      pending.complete(page(30, more: false));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(visible).dy, closeTo(before, 1));
      expect(h.controller.timeline.messages.first.id, 'old:30:0');
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'failed auto page does not retry in a loop and can be retried inline',
    (tester) async {
      final h = TestHarness();
      await h.login();
      seed(h, count: 1);
      var requests = 0;
      h.override = (r) async {
        if (!r.url.path.endsWith('/messages/paginated')) return h.response(r);
        requests++;
        return requests == 1
            ? http.Response('{"error":"offline"}', 503)
            : page(1, more: false);
      };
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      expect(requests, 1);
      for (var i = 0; i < 4; i++) {
        h.controller.dismissError();
        await tester.pumpAndSettle();
      }
      expect(requests, 1);
      expect(h.controller.error, isNull);
      await tester.tap(find.byKey(const Key('retry-earlier-history')));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(h.controller.historyPageError, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'short and hidden-only pages continue until viewport filled or exhausted',
    (tester) async {
      final h = TestHarness();
      await h.login();
      seed(h, count: 1);
      final offsets = <String>[];
      h.override = (r) async {
        if (!r.url.path.endsWith('/messages/paginated')) return h.response(r);
        offsets.add(r.url.queryParameters['offset']!);
        if (offsets.length == 1) {
          return http.Response(
            jsonEncode({
              'messages': [
                {'id': 'tool', 'role': 'tool', 'content': 'hidden'},
              ],
              'offset': 1,
              'hasMore': true,
              'total': 22,
            }),
            200,
          );
        }
        return page(2, more: false);
      };
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      expect(offsets, ['1', '2']);
      expect(
        h.controller.timeline.messages.any((m) => m.role == 'tool'),
        false,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'no progress page stops and pending page cannot populate new chat',
    (tester) async {
      final h = TestHarness();
      await h.login();
      seed(h, count: 1);
      var requests = 0;
      h.override = (r) async {
        if (!r.url.path.endsWith('/messages/paginated')) return h.response(r);
        requests++;
        return page(1, empty: true);
      };
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(h.controller.historyPageError, isNotNull);
      final pending = Completer<http.Response>();
      h.override = (r) => pending.future;
      final retry = h.controller.retryEarlierHistory();
      await tester.pump();
      h.controller.newChat();
      await tester.pump();
      pending.complete(page(1, more: false));
      await retry;
      await tester.pumpAndSettle();
      expect(h.controller.sessionId, isNull);
      expect(h.controller.timeline.messages, isEmpty);
      expect(h.controller.historyPageError, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('offline and syncing views never auto-request earlier pages', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    seed(h, count: 1);
    var requests = 0;
    h.override = (r) async {
      requests++;
      return page(1, more: false);
    };
    h.transport.receive('disconnected', {});
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
    h.controller.connected = true;
    h.controller.syncing = true;
    h.controller.dismissError();
    await tester.pumpAndSettle();
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
