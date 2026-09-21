import 'dart:async';
import 'dart:convert';
import 'package:chatstudio/data/hermes_channels.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/l10n.dart';
import 'package:chatstudio/l10n_catalog.dart';
import 'package:chatstudio/ui/agent_capabilities_screen.dart';
import 'package:chatstudio/ui/agent_configuration_screen.dart';
import 'package:chatstudio/ui/hermes_channel_screen.dart';
import 'package:chatstudio/ui/management_screen.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, dynamic> fixture() => {
  'telegram': {
    'require_mention': true,
    'reactions': true,
    'mention_patterns': ['hello'],
    'future': 'preserve',
  },
  'matrix': {'auto_thread': true},
  'platforms': {
    'telegram': {'token': 'never-echo-secret', 'proxy': 'socks5://server:1080'},
    'matrix': {
      'token': 'matrix-secret',
      'extra': {
        'homeserver': 'https://matrix.example',
        'user_id': '@bot:example',
      },
    },
    'whatsapp': {'enabled': true},
    'dingtalk': {
      'allow_all_users': true,
      'allowed_users': 'alice,bob',
      'extra': {'client_secret': 'private', 'client_id': 'ding123'},
    },
  },
  'platformCredentialStatus': {
    'telegram': true,
    'matrix': true,
    'dingtalk': true,
  },
};
void merge(Map<String, dynamic> target, Map<String, dynamic> values) {
  for (final entry in values.entries) {
    if (entry.value is Map) {
      final child = asMap(target[entry.key]);
      merge(child, asMap(entry.value));
      target[entry.key] = child;
    } else {
      target[entry.key] = entry.value;
    }
  }
}

void main() {
  Future<TestHarness> harness() async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    h.requests.clear();
    return h;
  }

  Future<void> show(
    WidgetTester tester,
    Widget page, {
    bool english = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: chatstudioTheme(Brightness.light),
        locale: Locale(english ? 'en' : 'zh'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder field(String key) => find.byKey(ValueKey('channel-field:$key'));
  Future<void> edit(WidgetTester tester, String key, String value) async {
    await tester.ensureVisible(field(key));
    await tester.enterText(field(key), value);
    await tester.pump();
  }

  Future<void> toggle(WidgetTester tester, String key) async {
    await tester.ensureVisible(field(key));
    await tester.tap(field(key));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('save-channel')));
    await tester.pumpAndSettle();
  }

  test(
    'channel status matches Web, not behavior maps or credential-clear status',
    () {
      final config = fixture();
      for (final p in ['telegram', 'matrix', 'whatsapp', 'dingtalk']) {
        expect(channelConfigured(config, p), true, reason: p);
      }
      config['discord'] = {'require_mention': false};
      expect(channelConfigured(config, 'discord'), false);
      config['platforms']['matrix'] = {'proxy': 'socks5://proxy'};
      config['platformCredentialStatus']['matrix'] = true;
      expect(channelCredentialsStored(config, 'matrix'), true);
      expect(channelConfigured(config, 'matrix'), false);
      config['platforms']['matrix'] = {
        'extra': {
          'homeserver': 'https://m',
          'user_id': '@b:m',
          'password': 'secret',
        },
      };
      expect(channelConfigured(config, 'matrix'), true);
      expect(channelCredentialsStored(config, 'whatsapp'), false);
    },
  );

  test(
    'all channel field names have English translations and correct nesting',
    () {
      for (final p in hermesChannelNames.keys) {
        final fields = channelFields(p);
        expect(fields.map((f) => f.path).toSet().length, fields.length);
        for (final f in fields) {
          if (RegExp(r'[\u4e00-\u9fff]').hasMatch(f.label)) {
            expect(
              appEnglishCatalog.containsKey(f.label),
              true,
              reason: f.label,
            );
          }
        }
      }
      expect(
        nestedChannelPatch({
          'extra.app_id': 'a',
          'extra.client_secret': 's',
          'allow_all_users': false,
        }),
        {
          'extra': {'app_id': 'a', 'client_secret': 's'},
          'allow_all_users': false,
        },
      );
      expect(
        channelFields('qqbot').any((f) => f.path == 'extra.client_secret'),
        true,
      );
      expect(channelFields('whatsapp').first.credential, true);
    },
  );

  testWidgets(
    'credentials and non-secret metadata load from platforms without echoing secrets',
    (tester) async {
      final h = await harness();
      await show(
        tester,
        HermesChannelScreen(
          api: h.controller.api!,
          platform: 'telegram',
          initialConfig: fixture(),
        ),
        english: true,
      );
      expect(tester.widget<TextField>(field('token')).controller!.text, '');
      expect(tester.widget<TextField>(field('token')).obscureText, true);
      expect(
        tester.widget<TextField>(field('proxy')).controller!.text,
        'socks5://server:1080',
      );
      expect(find.text('never-echo-secret'), findsNothing);
      expect(
        tester.widget<SwitchListTile>(field('require_mention')).value,
        true,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('save-channel')))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join();
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(texts), false, reason: texts);
    },
  );

  testWidgets(
    'behavior-only save requests restart and preserves unrelated settings',
    (tester) async {
      final h = await harness();
      final config = fixture();
      h.override = (r) async {
        if (r.method == 'GET') return json(config);
        final body = asMap(jsonDecode(r.body));
        merge(config['telegram'], asMap(body['values']));
        return json({'success': true});
      };
      await show(
        tester,
        HermesChannelScreen(
          api: h.controller.api!,
          platform: 'telegram',
          initialConfig: config,
        ),
      );
      await toggle(tester, 'require_mention');
      await save(tester);
      final writes = h.requests.where((r) => r.method == 'PUT').toList();
      expect(writes.length, 1);
      expect(jsonDecode(writes.single.body), {
        'section': 'telegram',
        'values': {'require_mention': false},
        'restart': true,
      });
      expect(config['telegram']['future'], 'preserve');
      expect(config['platforms']['telegram']['token'], 'never-echo-secret');
      expect(
        tester.widget<SwitchListTile>(field('require_mention')).value,
        false,
      );
    },
  );

  testWidgets(
    'combined save uses Web endpoint sequence and only one gateway restart',
    (tester) async {
      final h = await harness();
      final config = fixture();
      h.controller.api!.profile = 'work';
      h.override = (r) async {
        if (r.method == 'GET') return json(config);
        return json({'success': true});
      };
      await show(
        tester,
        HermesChannelScreen(
          api: h.controller.api!,
          platform: 'telegram',
          initialConfig: config,
        ),
      );
      await edit(tester, 'token', 'new-secret');
      await toggle(tester, 'require_mention');
      await edit(tester, 'mention_patterns', 'hello, studio');
      await save(tester);
      final writes = h.requests.where((r) => r.method == 'PUT').toList();
      expect(writes.map((r) => r.url.path), [
        '/api/hermes/config',
        '/api/hermes/config/credentials',
      ]);
      expect(jsonDecode(writes.first.body), {
        'section': 'telegram',
        'values': {
          'require_mention': false,
          'mention_patterns': ['hello', 'studio'],
        },
        'restart': false,
      });
      expect(jsonDecode(writes.last.body), {
        'platform': 'telegram',
        'values': {'token': 'new-secret'},
      });
      expect(
        writes.every((r) => r.headers['X-Hermes-Profile'] == 'work'),
        true,
      );
      await tester.ensureVisible(field('token'));
      expect(tester.widget<TextField>(field('token')).controller!.text, '');
    },
  );

  testWidgets(
    'credential failure retains draft and retry skips saved behavior',
    (tester) async {
      final h = await harness();
      var fail = true;
      h.override = (r) async {
        if (r.method == 'GET') return json(fixture());
        if (r.url.path.endsWith('/credentials') && fail) {
          return json({'error': 'gateway restart failed'}, 500);
        }
        return json({'success': true});
      };
      await show(
        tester,
        HermesChannelScreen(
          api: h.controller.api!,
          platform: 'telegram',
          initialConfig: fixture(),
        ),
      );
      await edit(tester, 'token', 'retry-secret');
      await toggle(tester, 'require_mention');
      await save(tester);
      await tester.ensureVisible(field('token'));
      expect(
        tester.widget<TextField>(field('token')).controller!.text,
        'retry-secret',
      );
      expect(find.byType(HermesChannelScreen), findsOneWidget);
      fail = false;
      h.requests.clear();
      await save(tester);
      expect(
        h.requests.where((r) => r.method == 'PUT').map((r) => r.url.path),
        ['/api/hermes/config/credentials'],
      );
    },
  );

  testWidgets(
    'clear uses DELETE and surfaces server restart warning after refresh',
    (tester) async {
      final h = await harness();
      var config = fixture();
      h.override = (r) async {
        if (r.method == 'DELETE') {
          config = {};
          return json({
            'success': true,
            'warning': {
              'code': 'gateway_restart_disabled',
              'message': 'disabled',
            },
          });
        }
        return json(config);
      };
      await show(
        tester,
        HermesChannelScreen(
          api: h.controller.api!,
          platform: 'telegram',
          initialConfig: config,
        ),
      );
      final clear = find.byKey(const Key('clear-channel-credentials'));
      await tester.ensureVisible(clear);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(
        h.requests.where((r) => r.method == 'DELETE').single.url.path,
        '/api/hermes/config/credentials/telegram',
      );
      await tester.drag(find.byType(ListView), const Offset(0, 1600));
      await tester.pumpAndSettle();
      expect(find.text('凭据已清除；自动重启已禁用，请手动重启网关。'), findsOneWidget);
      expect(find.byKey(const Key('clear-channel-credentials')), findsNothing);
    },
  );

  testWidgets(
    'WhatsApp enablement reads and writes credentials, never behavior',
    (tester) async {
      final h = await harness();
      h.override = (r) async =>
          json(r.method == 'GET' ? fixture() : {'success': true});
      await show(
        tester,
        HermesChannelScreen(
          api: h.controller.api!,
          platform: 'whatsapp',
          initialConfig: fixture(),
        ),
      );
      expect(tester.widget<SwitchListTile>(field('enabled')).value, true);
      expect(find.byKey(const Key('clear-channel-credentials')), findsNothing);
      await toggle(tester, 'enabled');
      await save(tester);
      expect(jsonDecode(h.requests.first.body), {
        'platform': 'whatsapp',
        'values': {'enabled': false},
      });
    },
  );

  testWidgets(
    'nested credentials, access controls and optional values retain Web values',
    (tester) async {
      final h = await harness();
      h.override = (r) async =>
          json(r.method == 'GET' ? fixture() : {'success': true});
      await show(
        tester,
        HermesChannelScreen(
          api: h.controller.api!,
          platform: 'dingtalk',
          initialConfig: fixture(),
        ),
      );
      expect(
        tester.widget<TextField>(field('extra.client_id')).controller!.text,
        'ding123',
      );
      await edit(tester, 'extra.client_secret', 'replacement');
      await tester.ensureVisible(field('allow_all_users'));
      expect(
        tester.widget<SwitchListTile>(field('allow_all_users')).value,
        true,
      );
      await toggle(tester, 'allow_all_users');
      await edit(tester, 'allowed_users', '');
      await save(tester);
      expect(jsonDecode(h.requests.first.body), {
        'platform': 'dingtalk',
        'values': {
          'extra': {'client_secret': 'replacement'},
          'allow_all_users': false,
          'allowed_users': '',
        },
      });
    },
  );

  testWidgets(
    'Profile switch during first save cannot write credentials into another profile',
    (tester) async {
      final h = await harness();
      final pending = Completer<http.Response>();
      h.override = (r) async =>
          r.method == 'PUT' ? pending.future : json(fixture());
      await show(
        tester,
        HermesChannelScreen(
          api: h.controller.api!,
          platform: 'telegram',
          initialConfig: fixture(),
        ),
      );
      await edit(tester, 'token', 'secret');
      await toggle(tester, 'require_mention');
      await tester.tap(find.byKey(const Key('save-channel')));
      await tester.pump();
      h.controller.api!.profile = 'other';
      pending.complete(json({'success': true}));
      await tester.pumpAndSettle();
      expect(h.requests.where((r) => r.method == 'PUT').length, 1);
      expect(h.requests.any((r) => r.url.path.endsWith('/credentials')), false);
    },
  );

  testWidgets('Weixin QR uses channel APIs and saves once after confirmation', (
    tester,
  ) async {
    final h = await harness();
    final opened = <Uri>[];
    h.override = (r) async {
      if (r.url.path.endsWith('/qrcode')) {
        return json({
          'qrcode': 'code&123',
          'qrcode_url': 'https://example.test/qr',
        });
      }
      if (r.url.path.endsWith('/status')) {
        return json({
          'status': 'confirmed',
          'account_id': 'account',
          'token': 'qr-secret',
          'base_url': 'https://example.test',
        });
      }
      if (r.url.path.endsWith('/save')) return json({'success': true});
      return json({});
    };
    await show(
      tester,
      HermesChannelScreen(
        api: h.controller.api!,
        platform: 'weixin',
        initialConfig: {},
        openQrUrl: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );
    await tester.tap(find.byKey(const Key('weixin-qr-login')));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'example.test');
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final post = h.requests.singleWhere((r) => r.method == 'POST');
    expect(post.url.path, '/api/hermes/weixin/save');
    expect(jsonDecode(post.body)['token'], 'qr-secret');
    expect(
      h.requests
          .singleWhere((r) => r.url.path.endsWith('/status'))
          .url
          .queryParameters['qrcode'],
      'code&123',
    );
    await tester.pump(const Duration(seconds: 10));
    expect(h.requests.where((r) => r.method == 'POST').length, 1);
    expect(find.text('扫码登录成功，频道凭据已保存'), findsOneWidget);
  });

  testWidgets('leaving QR page cancels polling', (tester) async {
    final h = await harness();
    h.override = (r) async =>
        json({'qrcode': 'code', 'qrcode_url': 'https://example.test/qr'});
    await show(
      tester,
      HermesChannelScreen(
        api: h.controller.api!,
        platform: 'weixin',
        initialConfig: {},
        openQrUrl: (_) async => true,
      ),
    );
    await tester.tap(find.byKey(const Key('weixin-qr-login')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    expect(h.requests.where((r) => r.url.path.endsWith('/status')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel list uses real config and opens full screen forms', (
    tester,
  ) async {
    final h = await harness();
    h.override = (_) async => json(fixture());
    await show(
      tester,
      AgentCapabilityDetailScreen(
        api: h.controller.api!,
        controller: h.controller,
        hermes: true,
        capability: 'channels',
        title: '频道',
      ),
      english: true,
    );
    expect(find.text('Channels'), findsOneWidget);
    final telegram = find.byKey(const ValueKey('channel:telegram'));
    expect(
      find.descendant(of: telegram, matching: find.text('Configured')),
      findsOneWidget,
    );
    final discord = find.byKey(const ValueKey('channel:discord'));
    expect(
      find.descendant(of: discord, matching: find.text('Not configured')),
      findsOneWidget,
    );
    await tester.tap(telegram);
    await tester.pumpAndSettle();
    expect(find.byType(HermesChannelScreen), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'unified management keeps Coding Agents and routes Hermes capabilities correctly',
    (tester) async {
      final h = await harness();
      h.override = (r) async {
        if (r.url.path == '/api/auth/me') {
          return json({
            'user': {'id': 1, 'username': 'Alex', 'role': 'super_admin'},
          });
        }
        if (r.url.path == '/api/coding-agents') {
          return json({
            'tools': [
              {'id': 'codex', 'installed': true},
            ],
          });
        }
        if (r.url.path == '/api/hermes/config') return json(fixture());
        return h.response(r);
      };
      await h.login();
      await show(tester, ManagementScreen(controller: h.controller));
      expect(find.text('打开 Agent 能力管理'), findsNothing);
      expect(find.text('Hermes Runtime'), findsOneWidget);
      expect(find.text('Codex'), findsOneWidget);
      await tester.tap(find.text('Hermes Runtime'));
      await tester.pumpAndSettle();
      expect(find.byType(HermesAgentSettingsScreen), findsOneWidget);
      await tester.tap(find.text('能力管理'));
      await tester.pumpAndSettle();
      expect(find.text('频道'), findsOneWidget);
      expect(find.byType(SegmentedButton<bool>), findsNothing);
    },
  );

  testWidgets(
    'channel QR long poll does not time out at the normal REST limit',
    (tester) async {
      final h = await harness();
      h.override = (_) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return json({'status': 'wait'});
      };
      Map<String, dynamic>? result;
      Object? error;
      final pending = h.controller.api!
          .hermesWeixinQrStatus('poll')
          .then(
            (value) {
              result = value;
            },
            onError: (Object e) {
              error = e;
            },
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 26));
      expect(error, isNull);
      expect(result, isNull);
      await tester.pump(const Duration(seconds: 5));
      await pending;
      expect(result, {'status': 'wait'});
    },
  );

  testWidgets(
    'refresh updates local channel fields without replacing the screen',
    (tester) async {
      final h = await harness();
      final pending = Completer<http.Response>();
      h.override = (_) async => pending.future;
      await show(
        tester,
        HermesChannelScreen(
          api: h.controller.api!,
          platform: 'telegram',
          initialConfig: fixture(),
        ),
      );
      await tester.tap(find.byTooltip('刷新'));
      await tester.pump();
      expect(field('proxy'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final config = fixture();
      config['platforms']['telegram']['proxy'] = 'https://new-proxy';
      pending.complete(json(config));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('proxy')).controller!.text,
        'https://new-proxy',
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('back confirms unsaved changes and cancel never saves', (
    tester,
  ) async {
    final h = await harness();
    await show(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => HermesChannelScreen(
                  api: h.controller.api!,
                  platform: 'telegram',
                  initialConfig: fixture(),
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await edit(tester, 'token', 'unsaved');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的更改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('token')).controller!.text,
      'unsaved',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(find.byType(HermesChannelScreen), findsNothing);
    expect(h.requests, isEmpty);
  });

  testWidgets(
    'all channel forms fit a small phone with large text in both themes',
    (tester) async {
      final h = await harness();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        for (final platform in hermesChannelNames.keys) {
          await tester.pumpWidget(
            MaterialApp(
              theme: chatstudioTheme(brightness),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.8),
                  viewInsets: const EdgeInsets.only(bottom: 200),
                ),
                child: child!,
              ),
              home: HermesChannelScreen(
                key: ValueKey('$platform-$brightness'),
                api: h.controller.api!,
                platform: platform,
                initialConfig: fixture(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.drag(find.byType(ListView), const Offset(0, -1500));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$platform / $brightness',
          );
        }
      }
    },
  );
}
