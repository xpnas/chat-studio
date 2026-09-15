import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/main.dart';
import 'package:ekko_app/ui/widgets/stable_markdown.dart';
import 'support.dart';

// Structural performance gates, not a replacement for profile-mode device timing.
void main() {
  testWidgets(
    'stream batches and typing preserve app shell and historical markdown',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.controller.timeline.messages = List.generate(
        1000,
        (i) => ChatMessage(
          id: 'history:$i',
          role: i.isEven ? 'user' : 'assistant',
          content: 'Message $i\n\nA stable paragraph with **markdown**.',
        ),
      );
      await tester.pumpWidget(
        EkkoApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      final shell = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final theme = shell.theme;
      final oldMarkdown = find.byType(StableMarkdown).first;
      final oldElement = tester.element(oldMarkdown);
      await tester.enterText(find.byKey(const Key('message-input')), 'work');
      await tester.pump();
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)), same(shell));
      expect(
        tester.element(find.byType(StableMarkdown).first),
        same(oldElement),
      );
      expect(find.byType(StableMarkdown).evaluate().length, lessThan(30));
      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pump();
      final sid = h.controller.sessionId;
      h.transport.receive('run.started', {
        'session_id': sid,
        'run_id': 'burst',
      });
      await tester.pump();
      for (var i = 0; i < 120; i++) {
        h.transport.receive('message.delta', {
          'session_id': sid,
          'run_id': 'burst',
          'delta': 'x',
        });
        if (i % 8 == 0) await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)), same(shell));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme,
        same(theme),
      );
      expect(h.controller.timeline.messages.last.content, 'x' * 120);
      expect(find.byType(StableMarkdown).evaluate().length, lessThan(30));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
