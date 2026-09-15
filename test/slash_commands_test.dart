import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/data/slash_commands.dart';
import 'package:ekko_app/main.dart';
import 'package:ekko_app/state/chat_timeline.dart';
import 'package:ekko_app/ui/widgets/chat_composer.dart';
import 'support.dart';

void main() {
  test('official engine catalog, aliases and exact boundaries', () {
    expect(commandsForEngine('codex').map((c) => c.name), [
      'usage',
      'context',
      'status',
      'compact',
    ]);
    expect(commandsForEngine('ekko-agent').length, 4);
    expect(commandsForEngine('hermes').length, 29);
    expect(readCommandName('  /RELOAD_SKILLS  '), 'reload-skills');
    expect(readCommandName('/title 中文标题\n第二行'), 'title');
    expect(readCommandName('/status-extra'), isNull);
    expect(readCommandName('/status/file'), isNull);
    expect(readCommandName('请执行 /status'), isNull);
    expect(skillCommandName(' My_ New\tSkill! '), 'my-new-skill');
  });

  test(
    'commands stay on run channel and can control a live Hermes run',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final c = h.controller;
      c.chooseEngine('hermes');
      expect(c.send('/status'), isTrue);
      final sid = c.sessionId;
      expect(h.transport.emitted.last.$1, 'run');
      expect(h.transport.emitted.last.$2['input'], '/status');
      expect(c.timeline.messages.last.role, 'command');
      expect(c.working, isFalse);
      h.transport.receive('session.command', {
        'session_id': sid,
        'command': 'status',
        'action': 'status',
        'message': 'Idle',
        'terminal': true,
      });
      expect(c.timeline.messages.last.content, 'Idle');
      expect(c.canSend, isTrue);
      expect(c.send('work'), isTrue);
      expect(c.canSend, isFalse);
      expect(c.canSubmit('/steer change direction'), isTrue);
      expect(c.send('/steer change direction'), isTrue);
      h.transport.receive('session.command', {
        'session_id': sid,
        'command': 'steer',
        'action': 'steer',
        'message': 'Steered',
        'terminal': false,
      });
      expect(c.working, isTrue);
      expect(c.send('ordinary message'), isTrue);
      expect(c.timeline.queue.last.content, 'ordinary message');
      expect(
        c.send(
          '/status',
          attachments: [
            {'type': 'file', 'path': '/x'},
          ],
        ),
        isFalse,
      );
      h.transport.receive('disconnected', {});
      expect(c.send('/abort'), isFalse);
    },
  );

  test(
    'coding agents keep official passthrough and terminal command settles run',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.chooseEngine('codex');
      expect(h.controller.send('/compact'), isTrue);
      expect(h.transport.emitted.last.$2['agent_id'], 'codex');
      expect(h.transport.emitted.last.$2['input'], '/compact');
      h.transport.receive('session.command', {
        'session_id': h.controller.sessionId,
        'command': 'compact',
        'message': 'Compacted',
        'terminal': true,
      });
      expect(h.controller.working, isFalse);
      expect(h.controller.canSend, isTrue);
      expect(h.controller.timeline.messages.last.role, 'command');
    },
  );

  test(
    'clear failure preserves history; display clear and destructive clear differ',
    () {
      final t = ChatTimeline()
        ..messages = [
          const ChatMessage(id: '1', role: 'user', content: 'keep'),
        ];
      t.apply('session.command', {
        'action': 'clear',
        'command': 'clear',
        'ok': false,
        'message': 'Cannot clear while running',
        'terminal': false,
      });
      expect(t.messages.first.content, 'keep');
      expect(t.messages.last.failure, isNotEmpty);
      t.apply('session.command', {
        'action': 'clear',
        'command': 'clear',
        'ok': true,
        'message': 'Display cleared',
      });
      expect(t.messages, isEmpty);
      t.apply('session.command', {
        'action': 'clear',
        'command': 'clear',
        'ok': true,
        'clearHistory': true,
        'message': 'Deleted 2 messages',
      });
      expect(t.messages.single.content, 'Deleted 2 messages');
      expect(t.messages.single.visible, isTrue);
    },
  );

  test(
    'command titles target their own session, including background views',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      final c = h.controller;
      c.chooseEngine('hermes');
      c.send('/title 原标题');
      final sid = c.sessionId;
      c.newChat();
      h.transport.receive('session.command', {
        'session_id': sid,
        'command': 'title',
        'action': 'title',
        'title': '新标题',
        'ok': true,
      });
      expect(c.title, '新对话');
      expect(c.conversations.firstWhere((s) => s.id == sid).title, '新标题');
      h.transport.receive('session.command', {
        'session_id': sid,
        'command': 'title',
        'action': 'title',
        'title': '失败标题',
        'ok': false,
      });
      expect(c.conversations.firstWhere((s) => s.id == sid).title, '新标题');
    },
  );

  test(
    'resource pickers use profile scoped official contracts, filter disabled skills',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.override = (r) async {
        if (r.url.path == '/api/hermes/skills') {
          return http.Response(
            jsonEncode({
              'categories': [
                {
                  'skills': [
                    {'name': 'enabled'},
                    {'name': 'disabled', 'enabled': false},
                    {'name': 'enabled'},
                  ],
                },
              ],
            }),
            200,
          );
        }
        if (r.url.path == '/api/hermes/bundles') {
          return http.Response(
            jsonEncode(
              r.method == 'POST'
                  ? {
                      'bundle': {'name': 'Example', 'commandName': 'example'},
                    }
                  : {
                      'bundles': [
                        {'name': 'Example', 'commandName': 'example'},
                      ],
                    },
            ),
            200,
          );
        }
        return h.response(r);
      };
      final api = h.controller.api!;
      expect((await api.commandSkills()).single['name'], 'enabled');
      expect((await api.commandBundles()).single['commandName'], 'example');
      await api.createCommandBundle('Example', 'description', ['enabled']);
      expect(h.requests.last.url.queryParameters['profile'], 'default');
      expect(jsonDecode(h.requests.last.body), {
        'name': 'Example',
        'description': 'description',
        'skills': ['enabled'],
      });
    },
  );

  testWidgets(
    'chat title in header, model inside composer and completion never auto sends',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('新对话')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ChatComposer),
          matching: find.byKey(const Key('model-button')),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('model-button')));
      await tester.pumpAndSettle();
      expect(find.text('选择模型'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('model:test::model-b')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('message-input')), '/co');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slash-commands')), findsOneWidget);
      expect(find.byKey(const ValueKey('command:context')), findsOneWidget);
      final before = h.transport.emitted.length;
      await tester.tap(find.byKey(const ValueKey('command:context')));
      await tester.pumpAndSettle();
      expect(h.controller.draft.text, '/context ');
      expect(h.transport.emitted.length, before);
      expect(find.byKey(const Key('slash-commands')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('message-input')),
        '普通文字 /co',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slash-commands')), findsNothing);
      await tester.enterText(find.byKey(const Key('message-input')), '/');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const Key('slash-commands')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    '320px composer with keyboard supports scrolling full Hermes catalog',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.chooseEngine('hermes');
      final input = TextEditingController();
      addTearDown(input.dispose);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              viewInsets: EdgeInsets.only(bottom: 240),
            ),
            child: Scaffold(
              body: Column(
                children: [
                  const Spacer(),
                  ChatComposer(controller: h.controller, input: input),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('message-input')), '/');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slash-commands')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('message-input')), '/goal');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(input.text, '/goal status ');
      expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'skill selection fills command and model sheet cannot change another draft',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.controller.chooseEngine('hermes');
      h.override = (r) async => r.url.path == '/api/hermes/skills'
          ? http.Response(
              jsonEncode({
                'categories': [
                  {
                    'skills': [
                      {'name': 'My Skill', 'description': 'Test skill'},
                    ],
                  },
                ],
              }),
              200,
            )
          : h.response(r);
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('message-input')), '/skill');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('command:skill')));
      await tester.pumpAndSettle();
      expect(find.text('选择技能'), findsOneWidget);
      await tester.tap(find.text('My Skill'));
      await tester.pumpAndSettle();
      expect(h.controller.draft.text, '/skill my-skill ');
      expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
      await tester.tap(find.byKey(const Key('model-button')));
      await tester.pumpAndSettle();
      h.controller.newChat();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('model:test::model-b')));
      await tester.pumpAndSettle();
      expect(h.controller.selectedModel?.id, 'model-a');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
