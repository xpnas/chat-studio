import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/data/models.dart';
import 'support.dart';
import 'package:chatstudio/ui/server_screen.dart';
import 'package:chatstudio/ui/widgets/attachment_tile.dart';

// Optional deterministic UI previews, not screenshots of a physical phone.
// Load a user-supplied CJK font locally; never redistribute the font itself.
void main() {
  final font = Platform.environment['CHATSTUDIO_PREVIEW_FONT'];
  testWidgets('render localized design previews', (tester) async {
    final previousShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await tester.runAsync(() async {
        final bytes = await File(font!).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        await (FontLoader(
          'Roboto',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      final h = TestHarness();
      await h.controller.initialize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ChatStudioApp(controller: h.controller, initialize: false),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/screenshots/$name.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('login');
      await h.login();
      h.controller.models = const [
        ModelChoice(
          id: 'gpt-5',
          provider: 'custom:openai',
          providerLabel: 'OpenAI',
          label: 'GPT-5',
        ),
        ModelChoice(
          id: 'gpt-5-mini',
          provider: 'custom:openai',
          providerLabel: 'OpenAI',
          label: 'GPT-5 mini',
        ),
        ModelChoice(
          id: 'claude-sonnet',
          provider: 'custom:anthropic',
          providerLabel: 'Anthropic',
          label: 'Claude Sonnet',
        ),
        ModelChoice(
          id: 'deepseek-chat',
          provider: 'custom:deepseek',
          providerLabel: 'DeepSeek',
          label: 'DeepSeek Chat',
        ),
      ];
      h.controller.selectedModel = h.controller.models.first;
      await tester.pumpAndSettle();
      await capture('home');
      h.override = (r) async => r.url.path == '/api/agents/availability'
          ? http.Response(
              jsonEncode({
                'agents': [
                  for (final id in [
                    'ekko-agent',
                    'hermes',
                    'claude-code',
                    'codex',
                    'pi',
                    'grok',
                    'opencode',
                  ])
                    {'id': id, 'installed': true},
                ],
              }),
              200,
            )
          : h.response(r);
      await tester.tap(find.byKey(const ValueKey('agent-picker')));
      await tester.pumpAndSettle();
      await capture('agents');
      h.override = null;
      Navigator.of(tester.element(find.text('选择 Agent'))).pop();
      await tester.pumpAndSettle();

      h.controller.sessionId = 'preview';
      h.controller.current = const Conversation(
        id: 'preview',
        title: '把灵感变成行动',
        profile: 'default',
        agent: 'ekko-agent',
      );
      h.controller.timeline.replace(const [
        ChatMessage(id: 'u1', role: 'user', content: '帮我规划一个轻松、专注的早晨。'),
        ChatMessage(
          id: 'a1',
          role: 'assistant',
          content:
              '当然。让早晨从一件小事开始，不必一开始就填满日程。\n\n### 你的 30 分钟晨间计划\n\n1. **5 分钟 · 慢慢醒来**\n   喝杯水，拉开窗帘，让自然光进来。\n2. **10 分钟 · 给身体一点空间**\n   伸展或散步，先不用看手机。\n3. **15 分钟 · 只选一件重要的事**\n   写下今天最想完成的目标，再拆成一个小步骤。\n\n你通常几点开始工作？我可以再帮你调整节奏。',
        ),
      ]);
      h.controller.dismissError();
      await tester.pumpAndSettle();
      await capture('chat');
      h.override = (r) async {
        if (r.url.path.endsWith('/workspace-files/list')) {
          return http.Response(
            jsonEncode({
              'absolutePath': '/srv/agents/chat-studio',
              'path': '',
              'entries': [
                {'name': 'src', 'path': 'src', 'isDir': true},
                {'name': 'docs', 'path': 'docs', 'isDir': true},
                {'name': 'README.md', 'path': 'README.md', 'isDir': false},
                {
                  'name': 'package.json',
                  'path': 'package.json',
                  'isDir': false,
                },
              ],
            }),
            200,
          );
        }
        if (r.url.path.endsWith('/workspace/folders')) {
          return http.Response(
            jsonEncode({
              'base': '/srv/agents',
              'current': '',
              'folders': [
                {
                  'name': 'chat-studio',
                  'path': 'chat-studio',
                  'fullPath': '/srv/agents/chat-studio',
                },
                {
                  'name': 'website',
                  'path': 'website',
                  'fullPath': '/srv/agents/website',
                },
              ],
            }),
            200,
          );
        }
        return h.response(r);
      };
      await tester.tap(find.byTooltip('工作区'));
      await tester.pumpAndSettle();
      await capture('workspace');
      await tester.tap(find.byKey(const Key('choose-server-workspace')));
      await tester.pumpAndSettle();
      await capture('workspace-folders');
      Navigator.of(tester.element(find.text('使用此目录'))).pop();
      await tester.pumpAndSettle();
      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeEndDrawer();
      await tester.pumpAndSettle();
      h.override = null;

      h.controller.dismissError();
      await tester.pumpAndSettle();
      await tester.tap(find.text('GPT-5'));
      await tester.pumpAndSettle();
      await capture('models');
      await tester.tap(
        find.byKey(const ValueKey('model:custom:openai::gpt-5')),
      );
      await tester.pumpAndSettle();

      await h.controller.setTheme('dark');
      await tester.pumpAndSettle();
      await capture('chat-dark');
      await h.controller.setTheme('light');
      h.controller.timeline.replace([
        for (var i = 0; i < 8; i++) ...[
          ChatMessage(id: 'reader-u$i', role: 'user', content: '如何让阅读长对话更轻松？'),
          ChatMessage(
            id: 'reader-a$i',
            role: 'assistant',
            content:
                '向上翻看历史时，输入框会自动折叠，为正文腾出更多空间。\n\n草稿会保留，也不会因为折叠而丢失附件。底部双线随回看进度舒展，轻点即可继续编辑。回到最新消息时，输入框会自动展开。',
          ),
        ],
      ]);
      h.controller.dismissError();
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const Key('message-list')),
        const Offset(0, 400),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('collapsed-composer')), findsOneWidget);
      final history = tester
          .widget<ListView>(find.byKey(const Key('message-list')))
          .controller!;
      history.jumpTo(history.position.maxScrollExtent * .52);
      await tester.pumpAndSettle();
      await capture('reading');
      await h.controller.setTheme('dark');
      await tester.pumpAndSettle();
      await capture('reading-dark');
      await h.controller.setTheme('light');
      h.controller.newChat();
      final imageBytes = await tester.runAsync(
        () => File('docs/app-icon.png').readAsBytes(),
      );
      h.override = (request) async =>
          request.url.path == '/api/studio/files/download'
          ? http.Response.bytes(
              imageBytes!,
              200,
              headers: {'content-type': 'image/png'},
            )
          : h.response(request);
      h.controller.sessionId = 'attachment-preview';
      h.controller.timeline.replace(const [
        ChatMessage(
          id: 'attachment-user',
          role: 'user',
          content: '帮我看一下这个图标和需求。',
          attachments: [
            MessageAttachment(
              name: '图标方案.png',
              path: '/fixture/icon.png',
              mimeType: 'image/png',
              size: 39553,
            ),
            MessageAttachment(
              name: '产品需求.pdf',
              path: '/fixture/requirements.pdf',
              mimeType: 'application/pdf',
              size: 246784,
            ),
          ],
        ),
        ChatMessage(
          id: 'attachment-answer',
          role: 'assistant',
          content:
              '### 我的建议\n\n保留青绿色的轻盈感，让标识在小尺寸下也有足够辨识度。\n\n- 减少复杂装饰\n- 保持浅深主题一致\n- 正文始终是视觉重点',
          reasoning: '先检查图形层次，再考虑移动端的实际尺寸。',
          tools: [
            ToolActivity(id: 'read', name: '读取附件', status: 'done'),
            ToolActivity(id: 'inspect', name: '检查图像', status: 'done'),
          ],
        ),
      ]);
      h.controller.dismissError();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      });
      await tester.pumpAndSettle();
      await capture('attachments');
      await tester.tap(find.byType(AttachmentTile).first);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AttachmentViewer),
          matching: find.byType(RawImage),
        ),
        findsOneWidget,
      );
      await capture('image-preview');
      await tester.tap(find.byKey(const Key('dismiss-image-preview')));
      await tester.pumpAndSettle();
      h.controller.timeline.replace(const [
        ChatMessage(
          id: 'failed-user',
          role: 'user',
          content: '请继续分析这份需求。',
          delivery: 'failed',
          failure: '模型服务暂时不可用，本次生成失败。',
        ),
      ]);
      h.controller.dismissError();
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到最新消息'), findsNothing);
      await capture('message-status');
      h.controller.newChat();
      await h.controller.chooseReasoningEffort('high');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reasoning-button')));
      await tester.pumpAndSettle();
      await capture('reasoning');
      await tester.tap(find.byKey(const ValueKey('reasoning:high')));
      await tester.pumpAndSettle();
      h.controller.conversations = const [
        Conversation(
          id: 'preview-running',
          title: '分析项目结构与重构建议',
          preview: 'Codex · 正在检查代码与依赖',
          agent: 'codex',
          model: 'gpt-5',
        ),
        Conversation(
          id: 'preview-waiting',
          title: '整理产品文档',
          preview: '需要确认读取工作区文件',
          agent: 'ekko-agent',
          model: 'gpt-5',
        ),
        Conversation(
          id: 'preview-done',
          title: '设计一套轻量的晨间计划',
          preview: '计划已整理完成',
          agent: 'ekko-agent',
        ),
        Conversation(
          id: 'preview-note',
          title: '周末的阅读清单',
          preview: '关于专注、设计和日常灵感',
        ),
        Conversation(
          id: 'preview-idea',
          title: '移动端交互细节',
          preview: '让正文始终成为视觉重点',
        ),
      ];
      h.transport.receive('session.activity.snapshot', {
        'profile': 'default',
        'timestamp': 1,
        'sessions': [
          {'session_id': 'preview-running', 'status': 'running'},
        ],
      });
      h.transport.receive('approval.requested', {
        'session_id': 'preview-waiting',
        'approval_id': 'preview-approval',
        'remaining_timeout_ms': 60000,
      });
      h.transport.receive('session.activity', {
        'session_id': 'preview-done',
        'status': 'completed',
        'timestamp': 2,
      });
      await tester.pump();
      await tester.tap(find.byTooltip('对话记录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Chat Studio'), findsOneWidget);
      await capture('history-tasks');
      await h.controller.setTheme('dark');
      await tester.pump(); // Start the theme transition before advancing time.
      // Nested ListTile/DefaultTextStyle transitions start after Theme settles.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 350));
      }
      await capture('history-tasks-dark');
      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await h.controller.setTheme('light');
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 350));
      }
      h.controller.servers = [
        {
          'server': 'https://example.com',
          'profile': 'work',
          'token': 'fixture',
        },
        {
          'server': 'http://192.168.1.8:8641',
          'profile': 'default',
          'token': 'fixture',
          'allowLocalHttp': true,
        },
        {
          'server': 'https://lab.example.com',
          'profile': 'default',
          'token': '',
        },
      ];
      final context = tester.element(find.byType(Scaffold).first);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ServerScreen(controller: h.controller),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 350));
      }
      await capture('servers');

      Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
      await tester.pumpAndSettle();
      h.controller.timeline.clear();
      h.controller.sessionId = 'preview';
      h.controller.current = const Conversation(
        id: 'preview',
        title: '让任务进度一目了然',
      );
      h.controller.timeline.replace(const [
        ChatMessage(
          id: 'plan-user',
          role: 'user',
          content: '请分析服务端的任务计划协议，并在手机端实现进度展示。',
        ),
        ChatMessage(
          id: 'plan-answer',
          role: 'assistant',
          runMarker: 'plan-preview',
          content: '已经确认服务端提供结构化的任务计划。\n\n我会把步骤和进度放进轻量卡片中，默认折叠，聊天正文仍是阅读重点。',
        ),
      ]);
      Map<String, dynamic> previewPlan(
        int revision,
        String state,
        bool complete,
      ) => {
        'session_id': 'preview',
        'run_id': 'plan-preview',
        'plan_id': 'mobile-plan',
        'revision': revision,
        'execution_state': state,
        'created_at': 2000,
        'updated_at': 2000 + revision,
        'explanation': '只依据服务端已确认的进度更新，不把运行结束当作全部完成。',
        'plan': [
          {'id': 'inspect', 'step': '梳理事件与历史记录协议', 'status': 'completed'},
          {
            'id': 'build',
            'step': '实现移动端计划卡片与状态同步',
            'status': complete ? 'completed' : 'in_progress',
          },
          {
            'id': 'test',
            'step': '验证断线恢复与历史记录',
            'status': complete ? 'completed' : 'pending',
          },
        ],
      };
      h.controller.timeline.apply(
        'plan.updated',
        previewPlan(1, 'running', false),
      );
      h.controller.dismissError();
      await tester.pumpAndSettle();
      await capture('task-plan');
      await tester.tap(find.text('任务计划'));
      await tester.pumpAndSettle();
      await capture('task-plan-expanded');
      await h.controller.setTheme('dark');
      await tester.pumpAndSettle();
      await capture('task-plan-dark');
      h.controller.timeline.apply(
        'plan.updated',
        previewPlan(2, 'ended', true),
      );
      await h.controller.setTheme('light');
      await tester.pumpAndSettle();
      await capture('task-plan-completed');

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = previousShadows;
    }
  }, skip: font == null);
}
