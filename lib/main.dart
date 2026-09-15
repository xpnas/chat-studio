import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'data/app_storage.dart';
import 'state/app_controller.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(EkkoApp(controller: AppController(storage: SecureAppStorage())));
}

class EkkoApp extends StatefulWidget {
  const EkkoApp({super.key, required this.controller, this.initialize = true});
  final AppController controller;
  final bool initialize;
  @override
  State<EkkoApp> createState() => _EkkoAppState();
}

class _EkkoAppState extends State<EkkoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shellState = _readShellState();
    widget.controller.addListener(_controllerChanged);
    if (widget.initialize) unawaited(widget.controller.initialize());
  }

  late (bool, bool, String) _shellState;
  (bool, bool, String) _readShellState() => (
    widget.controller.booting,
    widget.controller.authenticated,
    widget.controller.theme,
  );

  void _controllerChanged() {
    final next = _readShellState();
    // Streaming is a page concern. Do not recreate MaterialApp, themes and
    // inherited theme dependencies at every token batch.
    if (next != _shellState || !next.$2) {
      _shellState = next;
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.controller.onForeground();
    if (state == AppLifecycleState.paused) {
      widget.controller.onBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_controllerChanged);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chat Studio',
    debugShowCheckedModeBanner: false,
    theme: ekkoTheme(Brightness.light),
    darkTheme: ekkoTheme(Brightness.dark),
    themeMode: switch (widget.controller.theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    },
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: widget.controller.booting
        ? const Scaffold(body: Center(child: EkkoMark(size: 64)))
        : widget.controller.authenticated
        ? HomeScreen(controller: widget.controller)
        : LoginScreen(controller: widget.controller),
  );
}
