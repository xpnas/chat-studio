import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/state/group_chat_controller.dart';
import 'package:chatstudio/ui/group_chat_screen.dart';
import 'package:chatstudio/ui/widgets/agent_avatar.dart';
import 'package:chatstudio/ui/widgets/chat_title.dart';
import 'group_chat_unification_test.dart'
    show FakeGroupTransport, room, agents, message;
import 'support.dart';

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  testWidgets(
    'group title shares single layout; swipes open history and room server files',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = TestHarness();
      await h.login();
      var forbidden = false;
      h.override = (r) async {
        if (r.url.path == '/api/studio/group-chat/rooms/${room.id}') {
          return json({
            'room': {'id': room.id, 'name': room.name},
            'agents': agents,
            'messages': [message('1', 'a', 'Shared response')],
            'hasMore': false,
          });
        }
        if (r.url.path.endsWith('/workspace-files/list')) {
          expect(
            r.url.path,
            '/api/studio/group-chat/rooms/room-1/workspace-files/list',
          );
          return forbidden
              ? json({'error': 'Forbidden'}, 403)
              : json({
                  'path': '',
                  'absolutePath': '/srv/groups/project',
                  'entries': [
                    {'name': 'README.md', 'path': 'README.md', 'isDir': false},
                  ],
                });
        }
        if (r.url.path.endsWith('/workspace-file/read')) {
          expect(
            r.url.path,
            '/api/studio/group-chat/rooms/room-1/workspace-file/read',
          );
          return json({'content': 'Remote group file'});
        }
        return h.response(r);
      };
      final c = GroupChatController(
        api: h.controller.api!,
        room: room,
        transport: FakeGroupTransport(),
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
      expect(find.byType(ChatTitle), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatTitle),
          matching: find.byType(AgentAvatar),
        ),
        findsNWidgets(2),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('chat-title'))).data,
        room.name,
      );
      final stage = tester.getRect(find.byKey(const Key('reading-stage')));
      await tester.timedDragFrom(
        Offset(160, stage.top + 100),
        const Offset(170, 0),
        const Duration(milliseconds: 650),
      );
      await tester.pumpAndSettle();
      final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      expect(scaffold.isDrawerOpen, true);
      expect(find.text('单聊'), findsOneWidget);
      expect(find.text('群聊'), findsNWidgets(2));
      expect(find.text('历史'), findsOneWidget);
      scaffold.closeDrawer();
      await tester.pumpAndSettle();
      await tester.timedDragFrom(
        Offset(230, stage.top + 100),
        const Offset(-160, 0),
        const Duration(milliseconds: 650),
      );
      await tester.pumpAndSettle();
      expect(scaffold.isEndDrawerOpen, true);
      expect(find.text('/srv/groups/project'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('server-workspace-drawer'))).width,
        390,
      );
      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();
      final editor = tester.widget<TextField>(find.byType(TextField).last);
      expect(editor.readOnly, true);
      expect(editor.controller!.text, 'Remote group file');
      expect(find.byTooltip('保存'), findsNothing);
      expect(tester.getSize(find.byType(Dialog)).width, 390);
      await tester.tap(find.byTooltip('关闭').last);
      await tester.pumpAndSettle();
      forbidden = true;
      await tester.tap(find.byTooltip('刷新文件'));
      await tester.pumpAndSettle();
      expect(find.text('当前账号没有此群聊工作区的访问权限'), findsOneWidget);
      expect(
        h.requests.where(
          (r) =>
              r.url.path.contains('workspace') &&
              !r.url.path.contains('/group-chat/'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      h.dispose();
    },
  );

  testWidgets('many agents stay bounded at narrow widths and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final h = TestHarness();
    await h.login();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            leading: const Icon(Icons.menu),
            titleSpacing: 0,
            title: ChatTitle(
              controller: h.controller,
              title: 'A very long group title',
              agents: [
                for (var i = 0; i < 12; i++)
                  GroupAgentSummary.fromJson({
                    'id': '$i',
                    'agent': 'hermes',
                    'name': 'Agent $i',
                  }),
              ],
            ),
            actions: const [
              IconButton(onPressed: null, icon: Icon(Icons.folder)),
              IconButton(onPressed: null, icon: Icon(Icons.edit)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AgentAvatar), findsNWidgets(12));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    h.dispose();
  });

  test(
    'Hermes-sized PNG is accepted; oversized, redirect and invalid assets rejected',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      var size = 991343;
      var status = 200;
      var valid = true;
      h.override = (r) async {
        expect(
          r.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
        expect(r.followRedirects, false);
        final bytes = Uint8List(size);
        if (valid) bytes.setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);
        return http.Response.bytes(bytes, status);
      };
      final api = h.controller.api!;
      expect((await api.agentIcon('hermes.png'))!.length, size);
      size = 2 * 1024 * 1024 + 1;
      expect(await api.agentIcon('too-big.png'), isNull);
      size = 20;
      status = 302;
      expect(await api.agentIcon('redirect.png'), isNull);
      status = 200;
      valid = false;
      expect(await api.agentIcon('invalid.png'), isNull);
    },
  );

  test(
    'group image preview uses authenticated group binary endpoint',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.override = (r) async {
        expect(
          r.url.path,
          '/api/studio/group-chat/rooms/room-1/workspace-file/content',
        );
        expect(r.url.queryParameters['path'], 'images/a b.png');
        expect(r.headers['Authorization'], 'Bearer device-token');
        return http.Response.bytes([1, 2, 3], 200);
      };
      expect(
        await h.controller.api!.groupWorkspaceBytes('room-1', 'images/a b.png'),
        [1, 2, 3],
      );
    },
  );
}
