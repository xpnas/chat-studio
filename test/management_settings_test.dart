import 'dart:convert';
import 'package:chatstudio/data/compression_settings.dart';
import 'package:chatstudio/ui/management_screen.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:chatstudio/ui/widgets/settings_editors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

http.Response json(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('compression defaults and normalization match pinned server rules', () {
    final defaults = CompressionSettings.fromConfig({});
    expect(defaults.enabled, true);
    expect(defaults.percent, '50');
    expect(defaults.summary, contains('服务端默认'));
    for (final (raw, expected) in [
      (0.125, 12.5),
      (1, 95),
      (0, 5),
      ('0.7', 50),
      (double.nan, 50),
    ]) {
      final settings = CompressionSettings.fromConfig({
        'compression': {'enabled': false, 'threshold': raw},
      });
      expect(settings.enabled, false);
      expect(settings.threshold * 100, expected);
    }
  });

  Future<TestHarness> screen(
    WidgetTester tester, {
    bool failConfig = false,
  }) async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    h.requests.clear();
    h.override = (r) async {
      if (r.url.path == '/api/hermes/config') {
        if (failConfig) return json({'error': '配置无权限'}, 403);
        return json({
          'agent': {'max_turns': 60},
        });
      }
      if (r.url.path == '/api/coding-agents') {
        return json({
          'tools': [
            {
              'id': 'codex',
              'installed': true,
              'version': 'fixture',
              'source': 'user-cli',
            },
          ],
        });
      }
      if (r.url.path == '/api/agents/availability') {
        return json({
          'agents': [
            {'id': 'hermes', 'installed': false, 'source': 'not-installed'},
            {'id': 'ekko-agent', 'installed': true, 'source': 'built-in'},
          ],
        });
      }
      if (r.url.path == '/api/studio/logs') {
        return json({
          'files': [
            {'name': 'agent.log', 'path': '/var/log/agent.log'},
            {'name': 'server.log', 'path': '/var/log/server.log'},
          ],
        });
      }
      if (r.url.path.startsWith('/api/studio/logs/')) {
        return json({
          'entries': [
            {
              'level': 'INFO',
              'message': 'fixture log entry',
              'timestamp': '2026-09-18 03:29:44',
            },
          ],
        });
      }
      if (r.url.path.contains('/config-files/')) {
        return json({'content': 'model = "fixture"', 'path': 'config.toml'});
      }
      return h.response(r);
    };
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: chatstudioTheme(Brightness.light),
        home: ManagementScreen(controller: h.controller),
      ),
    );
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> settings(WidgetTester tester) async {
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('compression-settings')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'runtime availability is separate from CLI management and never invents Hermes operations',
    (tester) async {
      final h = await screen(tester);
      expect(find.text('Hermes Runtime'), findsOneWidget);
      expect(find.textContaining('未安装或不可用'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑配置'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.getSize(find.byType(Dialog)), const Size(390, 844));
      expect(find.byKey(const Key('settings-text-input')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('settings-text-input')),
        'updated',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final request = h.requests.lastWhere((r) => r.method == 'PUT');
      expect(request.url.path, endsWith('/codex/config-files/config'));
      expect(jsonDecode(request.body)['content'], 'updated');
      expect(
        h.requests.any((r) => r.url.path.contains('/coding-agents/hermes/')),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'diagnostic log selector keeps its label visible and switches files',
    (tester) async {
      final h = await screen(tester);
      await tester.tap(find.text('诊断'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await tester.pumpAndSettle();

      expect(find.text('服务日志'), findsOneWidget);
      expect(find.text('日志文件'), findsOneWidget);
      expect(find.text('agent.log'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('agent.log'));
      await tester.pumpAndSettle();
      expect(find.text('server.log'), findsOneWidget);
      await tester.tap(find.text('server.log'));
      await tester.pumpAndSettle();
      expect(find.text('fixture log entry'), findsOneWidget);
      expect(
        h.requests.any((r) => r.url.path.endsWith('/logs/server.log')),
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compression uses a sheet, validates percentages and writes a decimal ratio with enabled',
    (tester) async {
      final h = await screen(tester);
      await settings(tester);
      expect(find.textContaining('已启用（服务端默认）'), findsOneWidget);
      await tester.tap(find.byKey(const Key('compression-settings')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('compression-threshold')))
            .controller!
            .text,
        '50',
      );
      await tester.enterText(
        find.byKey(const Key('compression-threshold')),
        '1',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请输入 5–95 之间的百分比'), findsOneWidget);
      expect(h.requests.where((r) => r.method == 'PUT'), isEmpty);
      await tester.enterText(
        find.byKey(const Key('compression-threshold')),
        '62.5',
      );
      await tester.ensureVisible(find.text('启用自动压缩'));
      await tester.tap(find.text('启用自动压缩'));
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final request = h.requests.lastWhere((r) => r.method == 'PUT');
      expect(jsonDecode(request.body), {
        'section': 'compression',
        'values': {'enabled': false, 'threshold': .625},
        'restart': false,
      });
      expect(request.headers['x-hermes-profile'], 'default');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed config read is unknown not disabled or default enabled', (
    tester,
  ) async {
    final h = await screen(tester, failConfig: true);
    await settings(tester);
    expect(find.text('状态未知 · 配置读取失败'), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('compression-settings')))
          .onTap,
      isNull,
    );
    expect(h.requests.where((r) => r.method == 'PUT'), isEmpty);
  });

  testWidgets(
    'JSON editor is fullscreen, retains invalid text and cancel never writes',
    (tester) async {
      final h = await screen(tester);
      await tester.tap(find.text('模型'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('编辑辅助模型配置'));
      await tester.tap(find.text('编辑辅助模型配置'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(Dialog)), const Size(390, 844));
      await tester.enterText(
        find.byKey(const Key('settings-text-input')),
        '[]',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('配置必须是 JSON 对象'), findsOneWidget);
      await tester.tap(find.byTooltip('取消编辑'));
      await tester.pumpAndSettle();
      expect(
        h.requests.where((r) => ['PUT', 'POST', 'PATCH'].contains(r.method)),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'provider forms use scrollable sheets at small sizes with keyboard in both themes',
    (tester) async {
      await screen(tester);
      tester.view.physicalSize = const Size(360, 640);
      for (final brightness in Brightness.values) {
        final h = TestHarness();
        await h.login();
        await tester.pumpWidget(
          MaterialApp(
            theme: chatstudioTheme(brightness),
            home: ManagementScreen(controller: h.controller),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('模型'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('添加 Provider'));
        await tester.tap(find.text('添加 Provider'));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 260);
        await tester.pumpAndSettle();
        expect(find.byType(SettingsSheet), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          tester.getRect(find.widgetWithText(FilledButton, '保存')).bottom,
          lessThanOrEqualTo(380),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox.shrink());
        h.dispose();
      }
    },
  );
}
