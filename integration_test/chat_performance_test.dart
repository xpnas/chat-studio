import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/main.dart';
import '../test/support.dart';

// Run on physical hardware in profile mode. Model/network latency is deliberately
// excluded: this measures the real mobile rendering pipeline under a repeatable load.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'long history, scroll, slash completion and streaming frame timings',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.controller.timeline.messages = List.generate(
        1000,
        (i) => ChatMessage(
          id: 'history:$i',
          role: i.isEven ? 'user' : 'assistant',
          content:
              '第 $i 条消息\n\n这是用于性能测量的 **Markdown** 段落。\n\n```dart\nfinal index = $i;\n```',
        ),
      );
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await binding.watchPerformance(() async {
        for (var i = 0; i < 8; i++) {
          await tester.fling(
            find.byKey(const Key('message-list')),
            const Offset(0, 380),
            1800,
          );
          await tester.pumpAndSettle();
        }
      }, reportKey: 'history_scroll');
      h.controller.newChat();
      await tester.pumpAndSettle();
      await binding.watchPerformance(() async {
        for (final input in [
          '/',
          '/c',
          '/co',
          '/con',
          '/context',
          '/context ',
          '测试流式输出',
        ]) {
          await tester.enterText(find.byKey(const Key('message-input')), input);
          await tester.pump(const Duration(milliseconds: 80));
        }
        await tester.tap(find.byKey(const Key('send-button')));
        await tester.pump();
        final sid = h.controller.sessionId;
        h.transport.receive('run.started', {
          'session_id': sid,
          'run_id': 'perf',
        });
        for (var i = 0; i < 240; i++) {
          h.transport.receive('message.delta', {
            'session_id': sid,
            'run_id': 'perf',
            'delta': i % 20 == 0 ? '\n\n段落 $i：' : '流式内容。',
          });
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 60));
      }, reportKey: 'composer_stream');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
