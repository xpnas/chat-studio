import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ekko_app/main.dart';
import 'package:ekko_app/data/models.dart';
import 'support.dart';

// Optional deterministic UI previews, not screenshots of a physical phone.
// Load a user-supplied CJK font locally; never redistribute the font itself.
void main() {
  final font = Platform.environment['EKKO_PREVIEW_FONT'];
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
          child: EkkoApp(controller: h.controller, initialize: false),
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
      await tester.pumpAndSettle();
      await capture('home');
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

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = previousShadows;
    }
  }, skip: font == null);
}
