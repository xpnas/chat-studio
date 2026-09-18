import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/group_chat_transport.dart';
import 'package:chatstudio/data/mobile_media.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/state/chat_timeline.dart';
import 'package:chatstudio/state/group_chat_controller.dart';
import 'package:chatstudio/ui/group_chat_screen.dart';
import 'package:chatstudio/ui/widgets/chat_composer.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'package:chatstudio/ui/widgets/stable_markdown.dart';
import 'support.dart';

class FakeGroupTransport extends GroupChatTransport {
  void Function(String, Map<String, dynamic>)? listener;
  Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)? ack;
  final sent = <(String, Map<String, dynamic>)>[];
  @override
  void connect(
    StudioApi api,
    void Function(String, Map<String, dynamic>) onEvent,
  ) {
    listener = onEvent;
  }

  void receive(String event, Map<String, dynamic> data) =>
      listener?.call(event, data);
  @override
  Future<Map<String, dynamic>> emitAck(
    String event,
    Map<String, dynamic> data,
  ) async {
    sent.add((event, data));
    return ack == null ? {} : await ack!(event, data);
  }

  @override
  void dispose() {
    listener = null;
  }
}

const room = GroupRoom(id: 'room-1', name: '研发群', canMentionAll: true);
final agents = [
  {'id': 'a', 'agentId': 'agent-a', 'agent': 'codex', 'name': 'Code Agent'},
  {'id': 'b', 'agentId': 'agent-b', 'agent': 'hermes', 'name': 'Hermes'},
];
Map<String, dynamic> message(
  String id,
  String agent,
  String content, {
  bool streaming = false,
}) => {
  'id': id,
  'roomId': room.id,
  'senderId': 'agent-$agent',
  'senderAgentRecordId': agent,
  'senderName': agent == 'a' ? 'Code Agent' : 'Hermes',
  'role': 'assistant',
  'content': content,
  'timestamp': 100,
  'finish_reason': streaming ? 'streaming' : 'stop',
  'run_id': 'run-$id',
};
void groupResponses(
  TestHarness h, {
  List<Map<String, dynamic>> messages = const [],
}) {
  h.override = (r) async {
    if (r.url.path == '/api/studio/group-chat/rooms/${room.id}') {
      return http.Response(
        jsonEncode({
          'room': {'id': room.id, 'name': room.name, 'canMentionAll': true},
          'agents': agents,
          'messages': messages,
          'hasMore': false,
          'total': messages.length,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return h.response(r);
  };
}

void main() {
  test(
    'REST history is visible without socket acknowledgement; join times out',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      groupResponses(h, messages: [message('1', 'a', '**正文**')]);
      final transport = FakeGroupTransport()
        ..ack = (_, _) => Completer<Map<String, dynamic>>().future;
      final c = GroupChatController(
        api: h.controller.api!,
        room: room,
        transport: transport,
        ackTimeout: const Duration(milliseconds: 15),
      );
      addTearDown(c.dispose);
      await c.start();
      expect(c.loading, false);
      expect(c.displayMessages.single.content, '**正文**');
      transport.receive('connected', {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(c.loading, false);
      expect(c.canSend, false);
      expect(c.error, contains('TimeoutException'));
    },
  );

  test(
    'reconnect replaces partial text and ignores late deltas and other rooms',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      groupResponses(h);
      final transport = FakeGroupTransport();
      final c = GroupChatController(
        api: h.controller.api!,
        room: room,
        transport: transport,
      );
      addTearDown(c.dispose);
      await c.start();
      transport.receive('connected', {});
      await Future<void>.delayed(Duration.zero);
      transport.receive('message_stream_start', message('1', 'a', ''));
      transport.receive('message_stream_delta', {
        'roomId': room.id,
        'id': '1',
        'delta': 'Hello',
      });
      transport.receive('disconnected', {});
      transport.ack = (_, _) async => {
        'messages': [message('1', 'a', 'Hello world')],
      };
      transport.receive('connected', {});
      await Future<void>.delayed(Duration.zero);
      transport.receive('message_stream_delta', {
        'roomId': room.id,
        'id': '1',
        'delta': ' world',
      });
      transport.receive('message', {
        ...message('2', 'b', 'wrong room'),
        'roomId': 'other',
      });
      expect(c.messages.single.content, 'Hello world');
      expect(c.working, false);
      expect(c.displayMessages.single.agentType, 'codex');
    },
  );

  test(
    'shared timeline keeps different agents separate and normalizes attachments',
    () {
      final first = GroupChatMessage.fromJson({
        ...message('1', 'a', ''),
        'content': [
          {'type': 'text', 'text': '**正文**'},
          {'type': 'image', 'name': 'image.png', 'path': '/uploads/image.png'},
        ],
      }).toChatMessage();
      final second = GroupChatMessage.fromJson(
        message('2', 'b', 'other'),
      ).toChatMessage();
      final timeline = ChatTimeline()..messages = [first, second];
      expect(timeline.displayMessages.length, 2);
      expect(first.attachments.single.groupRoomId, room.id);
      expect(first.bodyText, contains('**正文**'));
      final hidden = GroupChatMessage.fromJson({
        'id': 'system',
        'role': 'system',
        'content': 'internal',
      }).toChatMessage();
      expect(hidden.visible, false);
    },
  );

  test(
    'mentions respect names, token boundaries and room permissions',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      groupResponses(h);
      final c = GroupChatController(
        api: h.controller.api!,
        room: room,
        transport: FakeGroupTransport(),
      );
      addTearDown(c.dispose);
      await c.start();
      expect(c.mentionsFor('@Code Agent please @Hermes, @all').length, 3);
      expect(c.mentionsFor('mail@Hermes @HermesExtra @codex'), isEmpty);
      c.room = const GroupRoom(id: 'room-1', name: 'read-only mentions');
      expect(c.mentionsFor('@all'), isEmpty);
    },
  );

  test(
    'group attachments use authenticated room routes, not single-chat files',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final directory = await Directory.systemTemp.createTemp(
        'chatstudio-group-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final source = File('${directory.path}/test.txt');
      await source.writeAsString('group attachment');
      h.override = (request) async {
        expect(request.headers['authorization'], isNotEmpty);
        expect(request.headers['x-hermes-profile'], isNotEmpty);
        expect(request.followRedirects, false);
        if (request.method == 'POST') {
          expect(
            request.url.path,
            '/api/studio/group-chat/rooms/room-1/attachments',
          );
          return http.Response(
            '{"files":[{"name":"test.txt","path":"/private/abc.txt"}]}',
            200,
          );
        }
        expect(
          request.url.path,
          '/api/studio/group-chat/rooms/room-1/attachments/abc.txt',
        );
        expect(request.url.queryParameters['name'], 'test.txt');
        return http.Response.bytes([1, 2, 3], 200);
      };
      final blocks = await h.controller.api!.uploadAttachments([
        await LocalAttachment.fromPath(source.path, 'test.txt'),
      ], groupRoomId: room.id);
      final file = MessageAttachment.parse(blocks).single.inGroup(room.id);
      expect(await h.controller.api!.attachmentBytes(file), [1, 2, 3]);
      final downloaded = await h.controller.api!.downloadAttachment(
        file,
        directory,
      );
      expect(await downloaded.readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'stale join acknowledgement cannot overwrite a newer connection',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      groupResponses(h);
      final oldJoin = Completer<Map<String, dynamic>>();
      final transport = FakeGroupTransport()..ack = (_, _) => oldJoin.future;
      final c = GroupChatController(
        api: h.controller.api!,
        room: room,
        transport: transport,
      );
      addTearDown(c.dispose);
      await c.start();
      transport.receive('connected', {});
      transport.receive('disconnected', {});
      transport.ack = (_, _) async => {
        'messages': [message('1', 'a', 'complete')],
      };
      transport.receive('connected', {});
      await Future<void>.delayed(Duration.zero);
      oldJoin.complete({
        'messages': [message('1', 'a', 'outdated')],
      });
      await Future<void>.delayed(Duration.zero);
      expect(c.displayMessages.single.content, 'complete');
      expect(c.canSend, true);
    },
  );

  testWidgets(
    'group opens at latest and does not jump to bottom while reading',
    (tester) async {
      final h = TestHarness();
      await h.login();
      groupResponses(
        h,
        messages: [
          for (var i = 0; i < 30; i++)
            {
              ...message(
                '$i',
                i.isEven ? 'a' : 'b',
                'Message $i\n\nShared paragraph',
              ),
              'timestamp': i,
            },
        ],
      );
      final transport = FakeGroupTransport();
      final c = GroupChatController(
        api: h.controller.api!,
        room: room,
        transport: transport,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(
            api: h.controller.api!,
            room: room,
            appController: h.controller,
            controller: c,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView).first);
      expect(list.reverse, true);
      expect(list.controller!.offset, 0);
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(160));
      expect(
        tester.widget<ChatComposer>(find.byType(ChatComposer)).collapsed,
        true,
      );
      transport.receive('message', {
        ...message('new', 'b', 'New reply'),
        'timestamp': 1000,
      });
      await tester.pumpAndSettle();
      expect(list.controller!.offset, greaterThan(160));
      await tester.tap(find.byTooltip('回到最新消息'));
      await tester.pumpAndSettle();
      expect(list.controller!.offset, 0);
      expect(
        tester.widget<ChatComposer>(find.byType(ChatComposer)).collapsed,
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'group uses shared renderer and composer; failed send retains isolated draft',
    (tester) async {
      final h = TestHarness();
      await h.login();
      groupResponses(h, messages: [message('1', 'a', '**共享格式**')]);
      h.controller.draft.text = 'single draft';
      final transport = FakeGroupTransport();
      final c = GroupChatController(
        api: h.controller.api!,
        room: room,
        transport: transport,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GroupChatScreen(
            api: h.controller.api!,
            room: room,
            appController: h.controller,
            controller: c,
          ),
        ),
      );
      await tester.pumpAndSettle();
      transport.receive('connected', {});
      await tester.pumpAndSettle();
      expect(find.byType(MessageBubble), findsOneWidget);
      expect(find.byType(StableMarkdown), findsOneWidget);
      expect(find.byType(ChatComposer), findsOneWidget);
      final composer = tester.widget<ChatComposer>(find.byType(ChatComposer));
      composer.input.value = const TextEditingValue(
        text: '@Code suffix',
        selection: TextSelection.collapsed(offset: 5),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('@Code Agent'));
      await tester.pumpAndSettle();
      expect(composer.input.text, '@Code Agent  suffix');
      transport.ack = (_, _) async => {'error': 'send failed'};
      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pumpAndSettle();
      expect(composer.input.text, '@Code Agent  suffix');
      expect(h.controller.draft.text, 'single draft');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'history without archived sessions settles and refresh is explicit',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('对话记录'));
      await tester.pumpAndSettle();
      h.requests.clear();
      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();
      final requests = h.requests
          .where((r) => r.url.path == '/api/studio/sessions')
          .toList();
      expect(requests.length, 1);
      expect(requests.single.url.queryParameters['includeArchived'], 'true');
      expect(h.controller.loadingSessions, false);
      await tester.pump(const Duration(seconds: 2));
      expect(
        h.requests.where((r) => r.url.path == '/api/studio/sessions').length,
        1,
      );
      await tester.tap(find.byTooltip('刷新记录'));
      await tester.pumpAndSettle();
      expect(
        h.requests.where((r) => r.url.path == '/api/studio/sessions').length,
        2,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
