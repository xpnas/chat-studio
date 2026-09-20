import 'dart:async';
import 'dart:convert';
import 'package:chatstudio/data/agent_settings.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/ui/agent_configuration_screen.dart';
import 'package:chatstudio/ui/runtime_manager_screen.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:chatstudio/l10n_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

http.Response json(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> configFixture() {
  final config = <String, dynamic>{
    'compression': {'threshold': .75},
    'future': {'keep': true},
  };
  for (final field in builtInSettingsSections.values.expand((v) => v)) {
    var parent = config;
    final keys = field.path.split('.');
    for (final key in keys.take(keys.length - 1)) {
      parent =
          parent.putIfAbsent(key, () => <String, dynamic>{})
              as Map<String, dynamic>;
    }
    parent[keys.last] = switch (field.kind) {
      AgentSettingKind.toggle => true,
      AgentSettingKind.languages => ['node'],
      AgentSettingKind.profiles => ['default'],
      AgentSettingKind.lines => ['test'],
      AgentSettingKind.choice => field.options.first,
      AgentSettingKind.number => field.nullable ? null : 10,
    };
  }
  return config;
}

Map<String, dynamic> runtimeFixture() => {
  'platform': 'linux-x64',
  'active': {},
  'hermes': {
    'source': 'managed-runtime',
    'activeVersion': '0.19.0',
    'agentVersion': '1.2.0',
    'activeDirectory': '/opt/runtime/0.19.0',
    'storageDirectory': '/opt/runtime',
    'defaultStorageDirectory': '/opt/runtime',
    'remoteVersions': ['0.20.0', '0.19.0'],
    'installed': [
      {
        'version': '0.19.0',
        'platform': 'linux-x64',
        'active': true,
        'directory': '/opt/runtime/0.19.0',
      },
      {
        'version': '0.18.0',
        'platform': 'linux-x64',
        'active': false,
        'directory': '/opt/runtime/0.18.0',
      },
      {'version': '0.17.0', 'platform': 'win32-x64', 'active': false},
    ],
  },
};

void main() {
  test('typed settings preserve hidden fields and match all five Web tabs', () {
    final config = configFixture();
    expect(builtInSettingsSections.keys.toList(), [
      '运行',
      '模型',
      '工具',
      '模块',
      '高级',
    ]);
    final fields = builtInSettingsSections.values.expand((v) => v).toList();
    expect(fields.length, 32);
    for (final field in fields) {
      expect(field.exists(config), isTrue);
      expect(
        appEnglishCatalog.containsKey(field.label),
        isTrue,
        reason: field.label,
      );
      if (field.kind == AgentSettingKind.number) {
        expect(field.validate('-1'), isNotNull);
        expect(field.validate('NaN'), isNotNull);
        expect(field.validate('Infinity'), isNotNull);
        expect(field.validate(''), field.nullable ? null : isNotNull);
        if (!field.decimal) expect(field.validate('1.2'), isNotNull);
      }
    }
    fields.first.write(config, 42);
    expect(asMap(config['runtime'])['maxSteps'], 42);
    expect(config['compression'], {'threshold': .75});
    expect(config['future'], {'keep': true});
  });

  testWidgets(
    'mobile settings edit locally, save once, preserve unknown config and survive save error',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      var config = configFixture();
      var fail = true;
      final writes = <Map<String, dynamic>>[];
      h.override = (r) async {
        if (r.url.path == '/api/ekko/config') {
          if (r.method == 'PUT') {
            final body = asMap(jsonDecode(r.body));
            writes.add(body);
            if (fail) return json({'error': 'save failed'}, 500);
            config = asMap(body['config']);
          }
          return json({
            'config': config,
            'schemaVersion': 2,
            'configPath': '/server/config.json',
            'runtimeRefresh': {'deferred': 1},
          });
        }
        return h.response(r);
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: chatstudioTheme(Brightness.light),
          home: BuiltInAgentSettingsScreen(api: h.controller.api!),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('runtime.maxSteps')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('agent-setting-input')), '0');
      await tester.tap(find.text('确认'));
      await tester.pump();
      expect(find.text('请输入有效数值'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('agent-setting-input')),
        '42',
      );
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.byKey(const Key('save-agent-settings')));
      await tester.pumpAndSettle();
      expect(find.text('save failed'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const Key('save-agent-settings')));
      await tester.pumpAndSettle();
      expect(writes.length, 2);
      expect(writes.last['config']['runtime']['maxSteps'], 42);
      expect(writes.last['config']['compression'], {'threshold': .75});
      expect(find.text('设置已保存，运行中的任务结束后生效'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'setting tabs fit narrow large-text screen and choices use bottom sheet',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.override = (r) async => r.url.path == '/api/ekko/config'
          ? json({'config': configFixture()})
          : h.response(r);
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: chatstudioTheme(Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 720),
              textScaler: TextScaler.linear(1.6),
            ),
            child: BuiltInAgentSettingsScreen(api: h.controller.api!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '模型'));
      await tester.pumpAndSettle();
      final choice = find.byKey(const ValueKey('model.reasoningEffort'));
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.text('高'));
      await tester.pumpAndSettle();
      expect(find.text('高'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'runtime refresh retains content; active delete is absent and cancel is safe',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      Completer<http.Response>? pending;
      h.override = (r) async {
        if (r.url.path == '/api/hermes/runtime-versions') {
          return pending?.future ?? json(runtimeFixture());
        }
        if (r.url.path.endsWith('/runtime-versions/jobs')) {
          return json({'jobs': []});
        }
        return h.response(r);
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: chatstudioTheme(Brightness.light),
          home: RuntimeManagerScreen(api: h.controller.api!),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0.17.0'), findsNothing);
      pending = Completer<http.Response>();
      await tester.tap(find.byTooltip('检查更新'));
      await tester.pump();
      expect(find.text('/opt/runtime'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.complete(json(runtimeFixture()));
      pending = null;
      await tester.pumpAndSettle();
      final remove = find.widgetWithText(TextButton, '删除');
      await tester.scrollUntilVisible(
        remove,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(remove, findsOneWidget);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(h.requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(
        h.requests.where((r) => r.method == 'DELETE').single.url.path,
        '/api/hermes/runtime-versions/runtime/0.18.0',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'runtime API sends server contract bodies, methods, boolean query and encoded versions',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.requests.clear();
      final api = h.controller.api!;
      await api.runtimeVersions(remote: true);
      await api.downloadRuntime('0.20.0', 'cf');
      await api.activateRuntime('0.20.0');
      await api.deleteRuntime('0.20.0+local');
      await api.setRuntimeDirectory('/opt/runtimes');
      await api.restartRuntimeService();
      expect(h.requests[0].url.queryParameters['remote'], 'true');
      expect(jsonDecode(h.requests[1].body), {
        'version': '0.20.0',
        'source': 'cf',
      });
      expect(jsonDecode(h.requests[2].body), {'version': '0.20.0'});
      expect(h.requests[3].method, 'DELETE');
      expect(jsonDecode(h.requests[4].body), {'directory': '/opt/runtimes'});
      expect(h.requests[5].method, 'POST');
    },
  );
  testWidgets(
    'runtime polling pauses in background and stops after a network error',
    (tester) async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      var jobReads = 0;
      var fail = false;
      h.override = (r) async {
        if (r.url.path == '/api/hermes/runtime-versions') {
          return json(runtimeFixture());
        }
        if (r.url.path.endsWith('/runtime-versions/jobs')) {
          jobReads++;
          if (fail) return json({'error': 'offline'}, 503);
          return json({
            'jobs': [
              {
                'id': 'job-1',
                'kind': 'runtime',
                'version': '0.20.0',
                'status': 'running',
                'stage': 'verify',
                'percent': 50,
              },
            ],
          });
        }
        return h.response(r);
      };
      await tester.pumpWidget(
        MaterialApp(home: RuntimeManagerScreen(api: h.controller.api!)),
      );
      await tester.pumpAndSettle();
      expect(jobReads, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(jobReads, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 10));
      expect(jobReads, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(jobReads, 3);
      fail = true;
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(jobReads, 4);
      await tester.pump(const Duration(seconds: 10));
      expect(jobReads, 4);
      expect(find.textContaining('offline'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
