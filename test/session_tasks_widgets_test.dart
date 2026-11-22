import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/ui/session_tasks_screen.dart';
import 'support.dart';
import 'session_tasks_test.dart' show goal, jsonResponse;

void main() {
  testWidgets(
    'task filters and exact evidence navigation preserve the list without sending a run',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.override = (r) async {
        if (r.url.path == '/api/studio/session-tasks') {
          return jsonResponse({
            'tasks': [goal('mobile')],
            'total': 1,
            'has_more': false,
          });
        }
        if (r.url.path.endsWith('/messages/paginated') &&
            r.url.path.contains('/s/')) {
          return jsonResponse({
            'messages': [
              {
                'id': 9,
                'role': 'assistant',
                'content': 'Exact mobile evidence',
                'timestamp': 1,
              },
            ],
            'total': 1,
            'hasMore': false,
          });
        }
        return h.response(r);
      };
      await tester.pumpWidget(
        MaterialApp(home: SessionTasksScreen(app: h.controller)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('已完成').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'mobile');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final request = h.requests.lastWhere(
        (r) => r.url.path == '/api/studio/session-tasks',
      );
      expect(request.url.queryParameters['status'], 'completed');
      expect(request.url.queryParameters['search'], 'mobile');
      await tester.scrollUntilVisible(
        find.text('查看完成证据'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('查看完成证据'));
      await tester.pumpAndSettle();
      expect(find.text('Exact mobile evidence'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Goal mobile'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'mobile',
      );
      expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    },
  );
}
