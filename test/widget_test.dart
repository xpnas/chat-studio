import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/main.dart';
import 'support.dart';

void main() {
  testWidgets('login displays required fields and validates empty input', (
    tester,
  ) async {
    final h = TestHarness();
    await h.controller.initialize();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    expect(find.text('你的灵感，\n随时接续。'), findsOneWidget);
    expect(find.text('Chat Studio'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('login-button')));
    await tester.tap(find.byKey(const Key('login-button')));
    await tester.pump();
    expect(find.text('请输入服务地址'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'home sends once, streams text, and shows native history drawer',
    (tester) async {
      final h = TestHarness();
      await h.login();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pump();
      expect(find.text('今天，想聊些什么？'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('message-input')), '你好');
      await tester.pump();
      await tester.tap(find.byKey(const Key('send-button')));
      await tester.pump();
      h.transport.receive('run.started', {
        'session_id': h.controller.sessionId,
        'run_id': 'r',
      });
      h.transport.receive('message.delta', {
        'session_id': h.controller.sessionId,
        'run_id': 'r',
        'delta': '你好，世界！',
      });
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('你好，世界！'), findsOneWidget);
      expect(find.byKey(const Key('stop-button')), findsOneWidget);
      h.transport.receive('abort.completed', {
        'session_id': h.controller.sessionId,
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('对话记录'));
      await tester.pumpAndSettle();
      expect(find.text('探索新的可能'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('small viewport and large text have no render overflow', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
