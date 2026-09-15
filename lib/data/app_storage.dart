import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';

abstract class AppStorage {
  Future<Map<String, dynamic>?> readSession();
  Future<void> saveSession(Map<String, dynamic> session);
  Future<void> clearSession();
  Future<String> deviceId();
  Future<String> readTheme();
  Future<void> saveTheme(String theme);
  Future<Map<String, dynamic>?> readChoice(String scope);
  Future<void> saveChoice(String scope, Map<String, dynamic> choice);
  Future<bool> readReadingHintSeen();
  Future<void> markReadingHintSeen();
}

class SecureAppStorage implements AppStorage {
  final _secure = const FlutterSecureStorage();
  static const _session = 'ekko.session.v1';
  String _choiceKey(String scope) =>
      'ekko.choice.v1.${base64Url.encode(utf8.encode(scope))}';
  @override
  Future<Map<String, dynamic>?> readChoice(String scope) async {
    final value = await _secure.read(key: _choiceKey(scope));
    if (value == null) return null;
    try {
      return asMap(jsonDecode(value));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveChoice(String scope, Map<String, dynamic> choice) =>
      _secure.write(key: _choiceKey(scope), value: jsonEncode(choice));
  @override
  Future<bool> readReadingHintSeen() async =>
      (await SharedPreferences.getInstance()).getBool('readingHintSeen') ??
      false;
  @override
  Future<void> markReadingHintSeen() async {
    await (await SharedPreferences.getInstance()).setBool(
      'readingHintSeen',
      true,
    );
  }

  @override
  Future<Map<String, dynamic>?> readSession() async {
    final value = await _secure.read(key: _session);
    if (value == null) return null;
    try {
      return asMap(jsonDecode(value));
    } on FormatException {
      await clearSession();
      return null;
    }
  }

  @override
  Future<void> saveSession(Map<String, dynamic> session) =>
      _secure.write(key: _session, value: jsonEncode(session));
  @override
  Future<void> clearSession() => _secure.delete(key: _session);
  @override
  Future<String> deviceId() async {
    // Stable installation UUID, not an IMEI, advertising ID or hardware identifier.
    var value = await _secure.read(key: 'ekko.device.v1');
    value ??= const Uuid().v4();
    await _secure.write(key: 'ekko.device.v1', value: value);
    return value;
  }

  @override
  Future<String> readTheme() async =>
      (await SharedPreferences.getInstance()).getString('theme') ?? 'system';
  @override
  Future<void> saveTheme(String theme) async =>
      (await SharedPreferences.getInstance()).setString('theme', theme);
}
