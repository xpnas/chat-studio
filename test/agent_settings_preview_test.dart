import 'dart:io';
import 'dart:ui' as ui;
import 'package:chatstudio/ui/agent_configuration_screen.dart';
import 'package:chatstudio/ui/runtime_manager_screen.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'agent_settings_test.dart' show configFixture, runtimeFixture, json;
import 'support.dart';

// Optional widget-rendered previews, not physical-device screenshots.
// Fonts remain local and are never bundled or redistributed.
void main() {
  final font = Platform.environment['CHATSTUDIO_SETTINGS_PREVIEW_FONT'];
  testWidgets('render native Agent settings previews', (tester) async {
    await tester.runAsync(() async {
      final bytes = await File(font!).readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    h.override = (r) async {
      if (r.url.path == '/api/ekko/config') {
        return json({'config': configFixture()});
      }
      if (r.url.path == '/api/hermes/runtime-versions') {
        return json(runtimeFixture());
      }
      if (r.url.path.endsWith('/runtime-versions/jobs')) {
        return json({'jobs': []});
      }
      if (r.url.path == '/api/hermes/config') {
        return json({
          'agent': {
            'max_turns': 60,
            'gateway_timeout': 600,
            'restart_drain_timeout': 60,
            'tool_use_enforcement': 'auto',
          },
          'memory': {
            'memory_enabled': true,
            'user_profile_enabled': true,
            'memory_char_limit': 2200,
            'user_char_limit': 1375,
          },
          'gatewayAutoStart': {'enabled': true, 'management': 'unified'},
        });
      }
      return h.response(r);
    };
    final key = GlobalKey();
    Future<void> show(Widget screen, Brightness brightness) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: chatstudioTheme(brightness),
            home: screen,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        await Directory('.local/settings-previews').create(recursive: true);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '.local/settings-previews/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await show(
      HermesAgentSettingsScreen(api: h.controller.api!),
      Brightness.light,
    );
    await capture('hermes');
    await tester.tap(find.widgetWithText(ChoiceChip, '网关'));
    await tester.pumpAndSettle();
    await capture('gateway');
    await show(
      BuiltInAgentSettingsScreen(api: h.controller.api!),
      Brightness.dark,
    );
    await capture('builtin');
    await show(RuntimeManagerScreen(api: h.controller.api!), Brightness.light);
    await capture('runtime');
    await tester.pumpWidget(const SizedBox());
  }, skip: font == null);
}
