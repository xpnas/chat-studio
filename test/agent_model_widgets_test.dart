import 'dart:convert';
import 'package:chatstudio/data/slash_commands.dart';
import 'package:chatstudio/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'agent_discovery_test.dart' show descriptor;
import 'support.dart';

TestHarness nativeHarness({String agent = 'cursor', bool efforts = false}) {
  final h = TestHarness();
  h.override = (r) async {
    if (r.url.path == '/api/studio/agents') {
      return http.Response(
        jsonEncode({
          'agents': [descriptor(agent), descriptor('qwen', surfaces: [])],
        }),
        200,
      );
    }
    if (r.url.path.endsWith('/models') &&
        r.url.path.startsWith('/api/studio/agents/')) {
      return http.Response(
        jsonEncode({
          'status': 'ready',
          'scope': 'available',
          'models': [
            {
              'id': 'opus',
              'name': 'Alias',
              'resolvedModel': 'Concrete native model',
              if (efforts) 'reasoningEfforts': ['high'],
            },
          ],
        }),
        200,
      );
    }
    return h.response(r);
  };
  return h;
}

void main() {
  testWidgets(
    'cancelling protocol override preserves the saved model and API mode',
    (tester) async {
      final h = TestHarness();
      await h.login();
      final before = h.controller.selectedModel;
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('model:${before!.key}')));
      await tester.pumpAndSettle();
      expect(find.text('选择 API 协议'), findsOneWidget);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(h.controller.selectedModel, same(before));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'global-only Agent exposes native defaults and aliases without invented effort levels',
    (tester) async {
      final h = nativeHarness();
      await h.login();
      await h.controller.chooseEngine('cursor');
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('model-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agent-mode:global')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-mode:scoped')), findsNothing);
      // Native default is an empty execution selector, distinct from the alias.
      expect(h.controller.selectableModels.first.id, '');
      final provider = find.byKey(const ValueKey('provider:'));
      if (find.byKey(const ValueKey('model:::opus')).evaluate().isEmpty) {
        await tester.tap(provider);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Concrete native model'));
      await tester.pumpAndSettle();
      expect(h.controller.selectedModel!.id, 'opus');
      expect(h.controller.selectedModel!.provider, '');
      await tester.tap(find.byKey(const Key('reasoning-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reasoning:high')), findsNothing);
      expect(find.byKey(const ValueKey('reasoning:')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('unavailable Agent reason is translated in the picker', (
    tester,
  ) async {
    final h = nativeHarness();
    await h.login();
    h.controller.language = 'en';
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-picker')));
    await tester.pumpAndSettle();
    expect(find.text('This Agent does not support chat'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const ValueKey('agent-option:qwen')))
          .enabled,
      false,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('management metadata does not invent compact or context commands', () {
    expect(
      commandsForEngine('qwen').map((command) => command.name),
      isNot(contains('compact')),
    );
    expect(
      commandsForEngine('qwen').map((command) => command.name),
      isNot(contains('context')),
    );
    expect(
      commandsForEngine('opencode').map((command) => command.name),
      isNot(contains('compact')),
    );
  });
}
