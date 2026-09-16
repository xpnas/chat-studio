import 'package:chatstudio/ui/widgets/chat_swipe_region.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/server_workspace.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/ui/home_screen.dart';
import 'package:chatstudio/ui/widgets/chat_text_style.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'support.dart';

http.Response json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> listing(String root, {String path = ''}) => {
  'absolutePath': path.isEmpty ? root : '$root/$path',
  'path': path,
  'entries': [
    {'name': 'src', 'path': 'src', 'isDir': true},
    {'name': 'README.md', 'path': 'README.md', 'isDir': false},
  ],
};
void serverFiles(TestHarness h) {
  h.override = (r) async {
    if (r.url.path.endsWith('/workspace-files/list')) {
      return json(
        listing(
          '/srv/agent/project',
          path: r.url.queryParameters['path'] ?? '',
        ),
      );
    }
    if (r.url.path == '/api/studio/workspace/folders') {
      return json({
        'base': '/srv/agent',
        'current': '',
        'folders': [
          {
            'name': 'project',
            'path': 'project',
            'fullPath': '/srv/agent/project',
          },
        ],
      });
    }
    return h.response(r);
  };
}

Future<TestHarness> mount(WidgetTester tester, {bool chat = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final h = TestHarness();
  await h.login();
  serverFiles(h);
  if (chat) {
    h.controller.sessionId = 'workspace-session';
    h.controller.timeline.replace(const [
      ChatMessage(id: 'u', role: 'user', content: '用户正文'),
      ChatMessage(id: 'a', role: 'assistant', content: '助手正文'),
    ]);
  }
  await tester.pumpWidget(
    ChatStudioApp(controller: h.controller, initialize: false),
  );
  await tester.pumpAndSettle();
  return h;
}

ScaffoldState home(WidgetTester tester) => tester.state<ScaffoldState>(
  find
      .descendant(of: find.byType(HomeScreen), matching: find.byType(Scaffold))
      .first,
);

void main() {
  for (final chat in [false, true]) {
    testWidgets(
      'center right swipe opens history, including slow drag: chat=$chat',
      (tester) async {
        await mount(tester, chat: chat);
        final stage = tester.getRect(find.byKey(const Key('reading-stage')));
        // Start well away from the edge: changing edge width alone fails this.
        await tester.timedDragFrom(
          Offset(170, stage.top + 95),
          const Offset(170, 0),
          const Duration(seconds: 1),
        );
        await tester.pumpAndSettle();
        expect(home(tester).isDrawerOpen, true);
        expect(find.text('探索新的可能'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('swipe over assistant selectable text opens history', (
    tester,
  ) async {
    await mount(tester, chat: true);
    await tester.timedDragFrom(
      tester.getCenter(find.text('助手正文')),
      const Offset(180, 0),
      const Duration(milliseconds: 650),
    );
    await tester.pumpAndSettle();
    expect(home(tester).isDrawerOpen, true);
  });
  testWidgets(
    'left swipe opens remote workspace; selecting uses fullPath, browsing uses path',
    (tester) async {
      final h = await mount(tester, chat: true);
      final stage = tester.getRect(find.byKey(const Key('reading-stage')));
      await tester.timedDragFrom(
        Offset(230, stage.top + 95),
        const Offset(-160, 0),
        const Duration(milliseconds: 650),
      );
      await tester.pumpAndSettle();
      expect(home(tester).isEndDrawerOpen, true);
      expect(find.text('/srv/agent/project'), findsOneWidget);
      await tester.tap(find.byKey(const Key('choose-server-workspace')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-folder:project')));
      await tester.pumpAndSettle();
      expect(
        h.requests
            .lastWhere((r) => r.url.path.endsWith('/workspace/folders'))
            .url
            .queryParameters['path'],
        'project',
      );
      await tester.tap(find.text('使用此目录'));
      await tester.pumpAndSettle();
      final saved = h.requests.lastWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/workspace'),
      );
      expect(jsonDecode(saved.body)['workspace'], '/srv/agent/project');
      expect(saved.headers['Authorization'], 'Bearer device-token');
      expect(h.controller.error, isNull);
      await tester.tap(find.byKey(const ValueKey('workspace-file:src')));
      await tester.pumpAndSettle();
      expect(h.controller.workspacePath, '/srv/agent/project/src');
      await tester.tap(find.text('返回工作区根目录'));
      await tester.pumpAndSettle();
      expect(h.controller.workspacePath, '/srv/agent/project');
    },
  );
  testWidgets(
    'vertical and short horizontal drags do not open drawers; composer excluded',
    (tester) async {
      await mount(tester, chat: true);
      final stage = tester.getRect(find.byKey(const Key('reading-stage')));
      await tester.timedDragFrom(
        Offset(170, stage.top + 95),
        const Offset(0, 160),
        const Duration(milliseconds: 650),
      );
      await tester.pumpAndSettle();
      expect(home(tester).isDrawerOpen, false);
      await tester.timedDragFrom(
        Offset(170, stage.top + 95),
        const Offset(24, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(home(tester).isDrawerOpen, false);
      await tester.enterText(find.byKey(const Key('message-input')), '草稿仍可编辑');
      await tester.timedDragFrom(
        tester.getCenter(find.byKey(const Key('message-input'))),
        const Offset(110, 0),
        const Duration(milliseconds: 650),
      );
      await tester.pumpAndSettle();
      expect(home(tester).isDrawerOpen, false);
      expect(home(tester).isEndDrawerOpen, false);
    },
  );
  test(
    'server absolute paths are platform independent and relative paths never POST',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      for (final path in [
        '/srv/agent/project',
        r'D:\work\agent',
        r'\\host\share\project',
      ]) {
        expect(isAbsoluteServerPath(path), true);
        await h.controller.api!.setWorkspace('s', path);
        expect(jsonDecode(h.requests.last.body)['workspace'], path);
      }
      final count = h.requests.length;
      for (final path in [
        '',
        'project',
        '../project',
        'C:project',
        '/foo\u0000bar',
      ]) {
        await expectLater(
          h.controller.api!.setWorkspace('s', path),
          throwsA(isA<ApiException>()),
        );
      }
      expect(h.requests.length, count);
    },
  );
  test(
    'remote ENOENT is scoped to workspace and refresh reads absolutePath, not current',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.sessionId = 's';
      serverFiles(h);
      await h.controller.refreshWorkspaceFiles();
      expect(h.controller.workspacePath, '/srv/agent/project');
      h.override = (r) async => r.url.path.endsWith('/workspace-files/list')
          ? json({'error': 'ENOENT: no such file or directory'}, 404)
          : h.response(r);
      await h.controller.refreshWorkspaceFiles();
      expect(h.controller.workspaceError, contains('服务器工作目录不存在'));
      expect(h.controller.error, isNull);
      expect(h.controller.workspaceFiles, isEmpty);
      serverFiles(h);
      await h.controller.refreshWorkspaceFiles();
      expect(h.controller.workspaceError, isNull);
      expect(h.controller.workspaceFiles.length, 2);
    },
  );
  test(
    'workspace late reads cannot cross chats; new chats have no stale directory',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.sessionId = 'old';
      final pending = Completer<http.Response>();
      h.override = (r) async => r.url.path.endsWith('/workspace-files/list')
          ? pending.future
          : h.response(r);
      final request = h.controller.refreshWorkspaceFiles();
      h.controller.newChat();
      expect(h.controller.workspacePath, '');
      pending.complete(json(listing('/private/old')));
      await request;
      expect(h.controller.workspacePath, '');
      expect(h.controller.workspaceFiles, isEmpty);
      expect(h.controller.workspaceLoading, false);
    },
  );
  test(
    'newer listing wins, active run prevents switching server folder',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.sessionId = 's';
      final first = Completer<http.Response>();
      var count = 0;
      h.override = (r) async {
        if (r.url.path.endsWith('/workspace-files/list')) {
          return ++count == 1 ? first.future : json(listing('/new'));
        }
        return h.response(r);
      };
      final stale = h.controller.refreshWorkspaceFiles();
      await h.controller.refreshWorkspaceFiles();
      first.complete(json(listing('/old')));
      await stale;
      expect(h.controller.workspacePath, '/new');
      h.controller.timeline.working = true;
      expect(await h.controller.chooseWorkspace('/other'), false);
      expect(
        h.requests.where(
          (r) => r.method == 'POST' && r.url.path.endsWith('/workspace'),
        ),
        isEmpty,
      );
    },
  );
  testWidgets(
    'missing fullPath disabled; folder load failure is local, retry works at 1.8x',
    (tester) async {
      final h = await mount(tester, chat: true);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.physicalSize = const Size(320, 900);
      var fail = true;
      h.override = (r) async {
        if (r.url.path.endsWith('/workspace/folders')) {
          return fail
              ? json({'error': 'Access denied'}, 403)
              : json({
                  'base': '/srv',
                  'folders': [
                    {'name': 'broken', 'path': 'broken'},
                  ],
                });
        }
        return h.response(r);
      };
      home(tester).openEndDrawer();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose-server-workspace')));
      await tester.pumpAndSettle();
      expect(find.textContaining('没有访问此服务器目录'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('重试目录读取'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(
              find.byKey(const ValueKey('server-folder:broken')),
            )
            .onTap,
        isNull,
      );
      expect(h.controller.error, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'long press and multi-touch do not navigate; horizontal content keeps its gesture',
    (tester) async {
      var navigations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatSwipeRegion(
              onSwipe: (_) => navigations++,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      final held = await tester.startGesture(const Offset(150, 200));
      await tester.pump(const Duration(milliseconds: 600));
      await held.moveBy(
        const Offset(150, 0),
        timeStamp: const Duration(milliseconds: 650),
      );
      await held.up();
      expect(navigations, 0);
      final one = await tester.startGesture(const Offset(150, 200));
      final two = await tester.startGesture(const Offset(160, 210));
      await one.moveBy(const Offset(150, 0));
      await two.up();
      await one.up();
      expect(navigations, 0);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatSwipeRegion(
              onSwipe: (_) => navigations++,
              child: const SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1800,
                  height: 500,
                  child: Text('wide code/table'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.dragFrom(const Offset(300, 200), const Offset(-170, 0));
      await tester.pumpAndSettle();
      expect(navigations, 0);
    },
  );
  testWidgets('folder sheet opened for old chat cannot change new chat', (
    tester,
  ) async {
    final h = await mount(tester, chat: true);
    home(tester).openEndDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose-server-workspace')));
    await tester.pumpAndSettle();
    h.controller.newChat();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('使用 project'));
    await tester.pumpAndSettle();
    expect(
      h.requests.where(
        (r) => r.method == 'POST' && r.url.path.endsWith('/workspace'),
      ),
      isEmpty,
    );
    expect(h.controller.workspacePath, '');
  });
  test(
    'late folder save never populates another chat or fetches its files',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.sessionId = 'old';
      final pending = Completer<http.Response>();
      h.override = (r) async =>
          r.method == 'POST' && r.url.path.endsWith('/workspace')
          ? pending.future
          : h.response(r);
      final save = h.controller.chooseWorkspace('/srv/old');
      expect(h.controller.canSend, false);
      h.controller.newChat();
      pending.complete(json({'ok': true}));
      expect(await save, false);
      expect(h.controller.workspacePath, '');
      expect(
        h.requests.where((r) => r.url.path.endsWith('/workspace-files/list')),
        isEmpty,
      );
    },
  );
  test('logout isolates pending workspace response and error', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    h.controller.sessionId = 's';
    final pending = Completer<http.Response>();
    h.override = (r) async => r.url.path.endsWith('/workspace-files/list')
        ? pending.future
        : h.response(r);
    final read = h.controller.refreshWorkspaceFiles();
    await h.controller.logout();
    pending.complete(json({'error': 'ENOENT: old private path'}, 404));
    await read;
    expect(h.controller.workspaceError, isNull);
    expect(h.controller.workspacePath, '');
    expect(h.controller.error, isNull);
  });
  testWidgets(
    'user and AI paragraphs share exact font and line height in both themes',
    (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const Scaffold(
              body: Column(
                children: [
                  MessageBubble(
                    message: ChatMessage(
                      id: 'u',
                      role: 'user',
                      content: '用户正文',
                    ),
                  ),
                  MessageBubble(
                    message: ChatMessage(
                      id: 'a',
                      role: 'assistant',
                      content: '助手正文',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final user = tester.widget<SelectableText>(
          find.byWidgetPredicate(
            (w) => w is SelectableText && w.data == '用户正文',
          ),
        );
        final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
        expect(user.style!.fontSize, chatBodyStyle.fontSize);
        expect(markdown.styleSheet!.p!.fontSize, user.style!.fontSize);
        expect(markdown.styleSheet!.p!.height, user.style!.height);
        expect(markdown.styleSheet!.tableBody!.fontSize, user.style!.fontSize);
      }
    },
  );
}
