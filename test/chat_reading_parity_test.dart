import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/person_models.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/state/group_chat_controller.dart';
import 'package:chatstudio/state/person_controller.dart';
import 'package:chatstudio/ui/group_chat_screen.dart';
import 'package:chatstudio/ui/person_screens.dart';
import 'package:chatstudio/ui/widgets/chat_history_list.dart';
import 'package:chatstudio/ui/widgets/chat_reading_view.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'package:chatstudio/ui/widgets/reading_handle.dart';
import 'group_chat_unification_test.dart'
    show FakeGroupTransport, room, agents, message;
import 'person_widgets_test.dart' show widgetPerson;
import 'person_protocol_test.dart' show personPage;
import 'session_tasks_test.dart' show jsonResponse;
import 'support.dart';

enum ChatKind { single, bot, group }

class ReadingFixture {
  ReadingFixture(this.h, this.kind);
  final TestHarness h;
  final ChatKind kind;
  PersonController? bot;
  GroupChatController? group;
  FakeGroupTransport? groupTransport;
  final rows = [
    for (var i = 1; i <= 70; i++)
      {
        'id': i,
        'role': i.isOdd ? 'user' : 'assistant',
        'content': 'History row $i\nReading paragraphs with a retained draft.',
        'timestamp': i,
      },
  ];

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    if (bot?.syncing == true) {
      bot!.onEvent('app.resumed', {
        ...personPage(id: 'parity-page', messages: rows),
        'session_id': bot!.sessionId,
        'isWorking': false,
      });
    }
    await tester.pumpAndSettle();
  }

  void stream() {
    const output = 'A fresh reply while reading older paragraphs';
    if (bot != null) {
      bot!.onEvent('run.started', {
        'session_id': bot!.sessionId,
        'run_id': 'live',
      });
      bot!.onEvent('message.delta', {
        'session_id': bot!.sessionId,
        'run_id': 'live',
        'delta': output,
      });
    } else if (group != null) {
      groupTransport!.receive('message_stream_start', {
        ...message('fresh', 'a', output, streaming: true),
        'timestamp': 1000,
      });
    } else {
      h.transport.receive('run.started', {
        'session_id': h.controller.sessionId,
        'run_id': 'live',
      });
      h.transport.receive('message.delta', {
        'session_id': h.controller.sessionId,
        'run_id': 'live',
        'delta': output,
      });
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    bot?.dispose();
    group?.dispose();
    if (kind != ChatKind.single) h.dispose();
  }
}

Future<ReadingFixture> mount(WidgetTester tester, ChatKind kind) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  final h = TestHarness();
  await h.login();
  final f = ReadingFixture(h, kind);
  h.override = (r) async {
    if (r.url.path.endsWith('/messages/paginated')) {
      return jsonResponse({
        'messages': f.rows,
        'offset': 0,
        'total': f.rows.length,
        'hasMore': false,
      });
    }
    if (r.url.path == '/api/studio/group-chat/rooms/${room.id}') {
      return jsonResponse({
        'room': {'id': room.id, 'name': room.name},
        'agents': agents,
        'messages': [
          for (final row in f.rows)
            {
              ...message('${row['id']}', 'a', '${row['content']}'),
              ...row,
              'id': '${row['id']}',
              'senderType': row['role'] == 'user' ? 'user' : 'agent',
            },
        ],
        'hasMore': false,
        'total': f.rows.length,
      });
    }
    return h.response(r);
  };
  late Widget app;
  switch (kind) {
    case ChatKind.single:
      h.controller.sessionId = 'parity-single';
      h.controller.timeline.replace(f.rows.map(ChatMessage.fromJson).toList());
      h.controller.dismissError();
      app = ChatStudioApp(controller: h.controller, initialize: false);
    case ChatKind.bot:
      f.bot = widgetPerson(cards: false);
      f.bot!.timeline.applyLatest(
        PersonTimelinePage.fromJson(
          personPage(id: 'parity-page', messages: f.rows),
        ),
      );
      app = MaterialApp(
        home: PersonScreen(
          app: h.controller,
          sessionId: f.bot!.sessionId,
          controller: f.bot,
        ),
      );
    case ChatKind.group:
      f.groupTransport = FakeGroupTransport();
      f.group = GroupChatController(
        api: h.controller.api!,
        room: room,
        transport: f.groupTransport,
      );
      app = MaterialApp(
        home: GroupChatScreen(
          api: h.controller.api!,
          room: room,
          appController: h.controller,
          controller: f.group,
        ),
      );
  }
  await tester.pumpWidget(app);
  await f.settle(tester);
  if (kind == ChatKind.group) {
    f.groupTransport!.receive('connected', {});
    await f.settle(tester);
  }
  return f;
}

Finder history() => find.byType(ChatHistoryList);
ScrollController scroll(WidgetTester tester) =>
    tester.widget<ChatHistoryList>(history()).controller;

Future<void> browseOlder(WidgetTester tester) async {
  final stage = tester.getRect(find.byKey(const Key('reading-stage')));
  await tester.timedDragFrom(
    Offset(stage.center.dx, stage.top + 70),
    Offset(0, stage.height - 140),
    const Duration(milliseconds: 650),
  );
}

void main() {
  for (final kind in ChatKind.values) {
    testWidgets(
      '$kind shares progress, overlay layout, latest animation and draft restoration',
      (tester) async {
        final f = await mount(tester, kind);
        expect(find.byType(ChatBody), findsOneWidget);
        expect(find.byType(ChatReadingLayout), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('message-input')),
          'Keep this draft',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await f.settle(tester);
        final editor = tester.state(find.byKey(const Key('message-input')));
        final fullHeight = tester.getSize(history()).height;
        scroll(tester).jumpTo(300);
        await f.settle(tester);
        expect(find.byKey(const Key('collapsed-composer')), findsNothing);
        scroll(tester).jumpTo(0);
        await f.settle(tester);
        await browseOlder(tester);
        await f.settle(tester);
        expect(find.byKey(const Key('collapsed-composer')), findsOneWidget);
        expect(tester.getSize(history()).height, greaterThan(fullHeight + 30));
        final paint =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const Key('reading-progress-lines')),
                    )
                    .painter!
                as ReadingHandlePainter;
        expect(
          paint.progress,
          closeTo(historyReadProgress(scroll(tester).position), .001),
        );
        final stage = tester.getRect(find.byKey(const Key('reading-stage')));
        final handle = tester.getRect(find.byKey(const Key('expand-composer')));
        final latest = tester.getRect(find.byTooltip('回到最新消息'));
        expect(tester.getRect(history()).bottom, closeTo(stage.bottom, 1));
        expect(handle.bottom, lessThanOrEqualTo(666));
        expect(handle.overlaps(latest), false);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.text('返回最新'), findsNothing);
        await tester.tap(find.byTooltip('回到最新消息'));
        await f.settle(tester);
        expect(scroll(tester).offset, closeTo(0, 1));
        expect(find.byKey(const Key('collapsed-composer')), findsNothing);
        expect(
          tester.state(find.byKey(const Key('message-input'))),
          same(editor),
        );
        expect(find.text('Keep this draft'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await f.dispose(tester);
      },
    );

    testWidgets(
      '$kind pins older text, badges live content and preserves its own folded stop action',
      (tester) async {
        final f = await mount(tester, kind);
        await browseOlder(tester);
        await f.settle(tester);
        final stage = tester.getRect(find.byKey(const Key('reading-stage')));
        final visible = find.byType(MessageBubble).evaluate().firstWhere((e) {
          final box = e.renderObject! as RenderBox;
          final top = box.localToGlobal(Offset.zero).dy;
          return top > stage.top + 50 && top < stage.bottom - 100;
        });
        final anchor = find.byKey(visible.widget.key!);
        final top = tester.getTopLeft(anchor).dy;
        f.stream();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(scroll(tester).offset, greaterThan(220));
        expect(tester.getTopLeft(anchor).dy, closeTo(top, 2));
        expect(find.text('新'), findsOneWidget);
        final stop = find.byKey(const Key('collapsed-stop-button'));
        expect(stop, findsOneWidget);
        final handleBounds = tester.getRect(
          find.byKey(const Key('expand-composer')),
        );
        final latestBounds = tester.getRect(find.byTooltip('回到最新消息'));
        expect(tester.getRect(stop).overlaps(handleBounds), false);
        expect(tester.getRect(stop).overlaps(latestBounds), false);
        await tester.tap(stop);
        await tester.pump();
        if (kind == ChatKind.group) {
          expect(
            f.groupTransport!.sent
                .where((e) => e.$1 == 'interrupt_agent')
                .single
                .$2['roomId'],
            room.id,
          );
          expect(ordinaryExecutions(f.h), isEmpty);
        } else {
          final transport = kind == ChatKind.bot
              ? f.bot!.transport as FakeTransport
              : f.h.transport;
          expect(
            transport.emitted
                .where((e) => e.$1 == 'abort')
                .single
                .$2['session_id'],
            kind == ChatKind.bot ? f.bot!.sessionId : f.h.controller.sessionId,
          );
          if (kind == ChatKind.bot) expect(ordinaryExecutions(f.h), isEmpty);
        }
        expect(tester.takeException(), isNull);
        await f.dispose(tester);
      },
    );
  }
}

Iterable<(String, Map<String, dynamic>)> ordinaryExecutions(TestHarness h) =>
    h.transport.emitted.where((e) => e.$1 == 'run' || e.$1 == 'abort');
