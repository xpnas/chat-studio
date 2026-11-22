import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/person_models.dart';
import 'package:chatstudio/l10n.dart';
import 'package:chatstudio/l10n_catalog.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/state/group_chat_controller.dart';
import 'package:chatstudio/ui/group_chat_screen.dart';
import 'package:chatstudio/ui/person_screens.dart';
import 'package:chatstudio/ui/widgets/chat_interaction_card.dart';
import 'package:chatstudio/ui/widgets/conversation_drawer.dart';
import 'package:chatstudio/ui/widgets/structured_interaction_card.dart';
import 'group_chat_unification_test.dart'
    show FakeGroupTransport, room, agents, message;
import 'person_model_settings_test.dart' show ModelFixture;
import 'person_protocol_test.dart' show personPage;
import 'person_widgets_test.dart' show widgetPerson;
import 'session_tasks_test.dart' show jsonResponse;
import 'support.dart';

class _RecordingGroupTransport extends FakeGroupTransport {
  final emitted = <(String, Map<String, dynamic>)>[];
  @override
  void emit(String event, Map<String, dynamic> data) {
    emitted.add((event, data));
  }
}

void main() {
  testWidgets(
    'BOT structured question parses questions/question without rendering raw JSON',
    (tester) async {
      final rawJson = jsonEncode([
        {
          'qid': 'q1',
          'question': 'Choose an option',
          'choices': ['Alpha', 'Beta'],
          'choices_offered': ['Alpha', 'Beta'],
          'multi_select': false,
        },
      ]);
      final answers = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonQuestion(
              event: {
                'kind': 'clarify.requested',
                'question': rawJson,
                'durable': true,
              },
              enabled: true,
              submitting: false,
              onAnswer: answers.add,
            ),
          ),
        ),
      );
      expect(find.byType(StructuredInteractionCard), findsOneWidget);
      expect(find.text(rawJson), findsNothing);
      expect(find.textContaining('"qid"'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonQuestion(
              event: {
                'kind': 'clarify.requested',
                'questions': [
                  {
                    'qid': 'q2',
                    'question': 'From questions field',
                    'choices': ['Yes', 'No'],
                    'choices_offered': ['Yes', 'No'],
                    'multi_select': false,
                  },
                ],
                'durable': true,
              },
              enabled: true,
              submitting: false,
              onAnswer: answers.add,
            ),
          ),
        ),
      );
      expect(find.byType(StructuredInteractionCard), findsOneWidget);
      expect(find.textContaining('From questions field'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'group approval renders description, command and localized buttons instead of raw protocol choices',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.override = (r) async {
        if (r.url.path == '/api/studio/group-chat/rooms/${room.id}') {
          return jsonResponse({
            'room': {'id': room.id, 'name': room.name},
            'agents': agents,
            'messages': [message('1', 'a', 'Initial message')],
            'hasMore': false,
          });
        }
        return h.response(r);
      };
      final transport = _RecordingGroupTransport();
      final group = GroupChatController(
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
            controller: group,
          ),
        ),
      );
      await tester.pumpAndSettle();
      transport.receive('connected', {});
      await tester.pumpAndSettle();
      group.timeline.apply('approval.requested', {
        'approval_id': 'apr-1',
        'description': 'Run build script',
        'command': 'npm run build',
        'choices': ['once', 'deny'],
        'allow_permanent': false,
      });
      group.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.byType(ChatInteractionCard), findsOneWidget);
      expect(find.text('Run build script'), findsOneWidget);
      expect(find.text('npm run build'), findsOneWidget);
      expect(find.text('仅允许本次'), findsOneWidget);
      expect(find.text('拒绝'), findsOneWidget);
      expect(find.text('once'), findsNothing);
      expect(find.text('deny'), findsNothing);
      expect(find.text('永久允许'), findsNothing);

      await tester.tap(find.text('仅允许本次'));
      await tester.pump();
      expect(
        transport.emitted.where((e) => e.$1 == 'approval.respond').single.$2,
        {'roomId': room.id, 'approval_id': 'apr-1', 'choice': 'once'},
      );
      await tester.pumpWidget(const SizedBox());
      group.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'free clarify card clears input after submitting and keeps composer unfolded on pending BOT interaction',
    (tester) async {
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInteractionCard(
              data: const {
                'kind': 'clarify.requested',
                'question': 'Tell me more',
              },
              enabled: true,
              submitting: false,
              onRespond: submitted.add,
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.enterText(field, 'Extra detail');
      await tester.pump();
      await tester.tap(find.byTooltip('提交说明'));
      await tester.pump();
      expect(submitted, ['Extra detail']);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);

      // Verify BOT composer stays unfolded when there is a pending interaction.
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = TestHarness();
      await h.login();
      final bot = widgetPerson(cards: false);
      final rows = [
        for (var i = 1; i <= 50; i++)
          {'id': i, 'role': 'assistant', 'content': 'Line $i\nParagraph body'},
      ];
      bot.timeline.applyLatest(
        PersonTimelinePage.fromJson(personPage(messages: rows)),
      );
      bot.live.apply('clarify.requested', {
        'clarify_id': 'c1',
        'question': 'Need confirmation',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PersonScreen(
            app: h.controller,
            sessionId: bot.sessionId,
            controller: bot,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stage = tester.getRect(find.byKey(const Key('reading-stage')));
      await tester.timedDragFrom(
        Offset(stage.center.dx, stage.top + 60),
        Offset(0, stage.height - 120),
        const Duration(milliseconds: 500),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      bot.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'PersonFlowForm caps added stage group at 12 without DropdownButton assertion failure',
    (tester) async {
      final c = widgetPerson();
      await tester.pumpWidget(MaterialApp(home: PersonFlowForm(person: c)));
      await tester.pumpAndSettle();
      final groupDropdown = find.byType(DropdownButton<int>);
      await tester.scrollUntilVisible(
        groupDropdown,
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(groupDropdown);
      await tester.pumpAndSettle();
      // 1-based label '13' corresponds to internal group index 12.
      await tester.scrollUntilVisible(
        find.text('13'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('13').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('添加阶段'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('添加阶段'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<int>), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'ConversationDrawer preserves search text on reopen and keeps TabBar Y position stable across tabs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = TestHarness();
      await h.login();
      h.controller.search = 'saved query';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: ConversationDrawer(
              controller: h.controller,
              onNewChat: () {},
              onOpenConversation: (_) {},
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
      final searchField = tester.widget<TextField>(
        find.byKey(const ValueKey('conversation-search:0')),
      );
      expect(searchField.controller!.text, 'saved query');

      final tabTop0 = tester.getRect(find.byType(TabBar)).top;
      await tester.tap(find.text('群聊'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TabBar)).top, closeTo(tabTop0, 0.5));
      expect(find.text('新建单聊'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bot-tab')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TabBar)).top, closeTo(tabTop0, 0.5));

      await tester.tap(find.text('历史'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TabBar)).top, closeTo(tabTop0, 0.5));

      await tester.pumpWidget(const SizedBox());
      h.dispose();
    },
  );

  testWidgets(
    'existing single session disables mode chips without redundant single-mode notice',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.controller.sessionId = 'existing-1';
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-button')));
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('agent-mode:scoped')),
      );
      expect(chip.onSelected, isNull);
      // Single-mode default Agent does not show redundant mode-locked banner.
      expect(find.text('已有会话的模式不可修改，请新建会话选择另一模式。'), findsNothing);
      Navigator.of(tester.element(find.byType(ChoiceChip))).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('English BOT model write error is translated inside composer', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    final f = ModelFixture()..reject = 409;
    final bot = await f.controller();
    h.controller.language = 'en';
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        home: PersonScreen(
          app: h.controller,
          sessionId: bot.sessionId,
          controller: bot,
        ),
      ),
    );
    await tester.pumpAndSettle();
    bot.syncing = false;
    bot.changed();
    await tester.pump();
    await tester.tap(find.byKey(const Key('model-button')));
    await tester.pumpAndSettle();
    final key = jsonEncode(['work', 'shared', 'beta']);
    await tester.tap(find.byKey(ValueKey('model:$key')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('The BOT configuration changed or a reply is running.'),
      findsOneWidget,
    );
    expect(find.textContaining('BOT 配置已变化'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    bot.dispose();
    h.dispose();
  });

  test('all audited UI copy keys exist in appEnglishCatalog', () {
    for (final key in const [
      '发消息，输入 @ 选择 Agent',
      '加载更早的消息',
      '加载更早消息',
      '确认删除',
      '刷新',
      '全部',
      '请补充信息',
      '未分类',
      '创建',
      'BOT',
      '新建单聊',
      '历史记录暂不支持搜索',
      ' · 点击切换 API 协议',
      '并行分组（从 1 连续）',
      '移除阶段',
    ]) {
      expect(appEnglishCatalog.containsKey(key), isTrue, reason: 'Missing $key');
    }
  });
}
