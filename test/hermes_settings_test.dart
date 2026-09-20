import 'dart:convert';
import 'package:chatstudio/data/agent_settings.dart';
import 'package:chatstudio/ui/agent_configuration_screen.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:chatstudio/l10n_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

http.Response reply(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test(
    'Hermes settings cover Web server-backed fields with limits and localization',
    () {
      final fields = hermesSettingsSections.values.expand((v) => v).toList();
      expect(fields.length, 16);
      for (final field in fields) {
        expect(
          appEnglishCatalog.containsKey(field.label),
          isTrue,
          reason: field.label,
        );
        if (field.max != null) {
          expect(field.validate('${field.max! + 1}'), isNotNull);
          expect(field.validate('${field.max}'), isNull);
        }
      }
      final config = <String, dynamic>{};
      fields.first.write(config, 42);
      expect(config, {
        'agent': {'max_turns': 42},
      });
    },
  );

  testWidgets(
    'Hermes patches only edits; partial failure retains unsaved sections for retry',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      var fail = true;
      h.override = (r) async {
        if (r.url.path == '/api/hermes/config') {
          if (r.method == 'GET') {
            return reply({
              'agent': {'max_turns': 20, 'future': 'keep'},
              'memory': {'memory_enabled': false},
            });
          }
          if (jsonDecode(r.body)['section'] == 'memory' && fail) {
            return reply({'error': 'save failed'}, 500);
          }
          return reply({'success': true});
        }
        return h.response(r);
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: chatstudioTheme(Brightness.light),
          home: HermesAgentSettingsScreen(api: h.controller.api!),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('运行时版本管理'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agent.max_turns')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('agent-setting-input')),
        '40',
      );
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '记忆'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('memory.memory_enabled')));
      await tester.tap(find.byKey(const Key('save-agent-settings')));
      await tester.pumpAndSettle();
      expect(find.textContaining('save failed'), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const Key('save-agent-settings')));
      await tester.pumpAndSettle();
      final writes = h.requests
          .where((r) => r.method == 'PUT' && r.url.path == '/api/hermes/config')
          .toList();
      expect(writes.length, 3);
      expect(jsonDecode(writes.first.body), {
        'section': 'agent',
        'values': {'max_turns': 40},
        'restart': false,
      });
      expect(writes.skip(1).map((r) => jsonDecode(r.body)['section']), [
        'memory',
        'memory',
      ]);
      expect(
        writes.every(
          (r) => r.headers['X-Hermes-Profile'] == h.controller.api!.profile,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'gateway Profile picker uses server options and preserves include/exclude semantics',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.override = (r) async {
        if (r.url.path == '/api/hermes/config') {
          return reply({
            'gatewayAutoStart': {
              'enabled': true,
              'exclude': ['other'],
            },
          });
        }
        if (r.url.path == '/api/app/profiles') {
          return reply({
            'profiles': [
              {'name': 'default'},
              {'name': 'work'},
            ],
          });
        }
        return h.response(r);
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: chatstudioTheme(Brightness.dark),
          home: HermesAgentSettingsScreen(api: h.controller.api!),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '网关'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gateway-include-mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gatewayAutoStart.include')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'default'), findsOneWidget);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'work'));
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-agent-settings')));
      await tester.pumpAndSettle();
      final write = h.requests.lastWhere((r) => r.method == 'PUT');
      expect(jsonDecode(write.body), {
        'section': 'gatewayAutoStart',
        'values': {
          'include': ['work'],
          'exclude': null,
        },
        'restart': false,
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'disabling Hermes approvals requires confirmation; failed loads do not offer fake config',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      var forbidden = true;
      h.override = (r) async {
        if (r.url.path == '/api/hermes/config') {
          return forbidden
              ? reply({'error': 'forbidden'}, 403)
              : reply({
                  'approvals': {'mode': 'manual'},
                });
        }
        return h.response(r);
      };
      await tester.pumpWidget(
        MaterialApp(home: HermesAgentSettingsScreen(api: h.controller.api!)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('forbidden'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      forbidden = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approvals.mode')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('关闭工具审批？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('手动审批\n关闭审批会允许工具无需确认执行'), findsOneWidget);
      expect(h.requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
