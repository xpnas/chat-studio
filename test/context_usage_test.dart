import 'dart:async';
import 'dart:convert';
import 'package:chatstudio/data/context_usage.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/state/chat_timeline.dart';
import 'package:chatstudio/ui/widgets/composer_context_info.dart';
import 'package:chatstudio/ui/widgets/chat_composer.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:chatstudio/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

http.Response json(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'matches Web context-first, zero fallback, formatting and invalid values',
    () {
      var usage = const ContextUsage().merge({
        'input_tokens': 2300,
        'output_tokens': 700,
      });
      expect(usage.used, 3000);
      usage = usage.merge({'contextTokens': 1500});
      expect(usage.used, 1500);
      expect(usage.merge({'contextTokens': 0}).used, 3000);
      expect(
        usage.merge({'contextTokens': double.nan, 'inputTokens': -1}).used,
        1500,
      );
      expect(ContextUsage.format(999), '999');
      expect(ContextUsage.format(256000), '256.0k');
      expect(ContextUsage.format(1200000), '1.2M');
      expect(
        Conversation.fromJson({
          'id': 'a',
          'input_tokens': 20,
          'output_tokens': 10,
        }).contextUsage.used,
        30,
      );
    },
  );

  test(
    'usage is absolute, compression can decrease it, late run is ignored',
    () {
      final t = ChatTimeline()..sessionId = 'a';
      t.apply('run.started', {'run_id': 'r'});
      t.apply('usage.updated', {'run_id': 'r', 'contextTokens': 12000});
      t.apply('usage.updated', {'run_id': 'r', 'contextTokens': 12000});
      expect(t.contextUsage.used, 12000);
      t.apply('compression.completed', {'run_id': 'r', 'contextTokens': 4000});
      expect(t.contextUsage.used, 4000);
      t.apply('usage.updated', {'run_id': 'old', 'contextTokens': 1});
      expect(t.contextUsage.used, 4000);
      t.apply('run.completed', {'run_id': 'r', 'contextTokens': 5000});
      t.apply('usage.updated', {'run_id': 'r', 'contextTokens': 9000});
      expect(t.contextUsage.used, 5000);
      t.sessionId = 'b';
      expect(t.contextUsage.used, 0);
    },
  );

  test('resume snapshot overrides replay and clear accepts explicit zeros', () {
    final t = ChatTimeline()..sessionId = 'a';
    t.resume({
      'isWorking': false,
      'messages': [],
      'contextTokens': 500,
      'events': [
        {
          'event': 'usage.updated',
          'data': {'contextTokens': 2000},
        },
      ],
    });
    expect(t.contextUsage.used, 500);
    t.resume({'isWorking': false, 'messages': [], 'events': []});
    expect(t.contextUsage.used, 500);
    t.apply('session.command', {
      'ok': true,
      'action': 'usage',
      'contextTokens': 200,
    });
    expect(t.contextUsage.used, 200);
    t.apply('session.command', {
      'ok': true,
      'action': 'clear',
      'command': 'clear',
      'inputTokens': 0,
      'outputTokens': 0,
      'contextTokens': 0,
    });
    expect(t.contextUsage.used, 0);
  });

  testWidgets(
    'composer context is inside surface, hides on any text and returns on clear',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.transport.receive('disconnected', {});
      h.override = (r) async => r.url.path.endsWith('/context-length')
          ? json({'context_length': 128000})
          : h.response(r);
      await h.controller.openConversation(
        Conversation.fromJson({
          'id': 'a',
          'model': 'model-a',
          'provider': 'test',
          'contextTokens': 32000,
        }),
      );
      final input = TextEditingController();
      addTearDown(input.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: chatstudioTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposer(controller: h.controller, input: input),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final info = find.byKey(const Key('composer-context-info'));
      expect(
        find.descendant(
          of: find.byKey(const Key('composer-surface')),
          matching: info,
        ),
        findsOneWidget,
      );
      expect(find.text('32.0k / 128.0k · 剩余 96.0k'), findsOneWidget);
      final request = h.requests.lastWhere(
        (r) => r.url.path.endsWith('/context-length'),
      );
      expect(request.url.queryParameters, {
        'profile': 'default',
        'provider': 'test',
        'model': 'model-a',
      });
      await tester.enterText(find.byKey(const Key('message-input')), ' ');
      await tester.pump();
      expect(info, findsNothing);
      await tester.enterText(find.byKey(const Key('message-input')), 'hello');
      await tester.pump();
      expect(info, findsNothing);
      await tester.enterText(find.byKey(const Key('message-input')), '');
      await tester.pump();
      expect(info, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late capacity response cannot leak across sessions; narrow English layout',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.transport.receive('disconnected', {});
      final slow = Completer<http.Response>();
      h.override = (r) async => r.url.path.endsWith('/context-length')
          ? r.url.queryParameters['model'] == 'model-a'
                ? slow.future
                : json({'context_length': 64000})
          : h.response(r);
      await h.controller.openConversation(
        Conversation.fromJson({
          'id': 'a',
          'model': 'model-a',
          'contextTokens': 1000,
        }),
      );
      final input = TextEditingController();
      addTearDown(input.dispose);
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          locale: const Locale('en'),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: ComposerContextInfo(controller: h.controller, input: input),
            ),
          ),
        ),
      );
      await tester.pump();
      await h.controller.openConversation(
        Conversation.fromJson({
          'id': 'b',
          'model': 'model-b',
          'contextTokens': 2000,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('2.0k / 64.0k · 62.0k left'), findsOneWidget);
      slow.complete(json({'context_length': 128000}));
      await tester.pumpAndSettle();
      expect(find.textContaining('128.0k'), findsNothing);
      expect(tester.takeException(), isNull);
      h.controller.newChat();
      await tester.pump();
      expect(find.byKey(const Key('composer-context-info')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
