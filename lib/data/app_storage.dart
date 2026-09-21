import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

abstract class AppStorage {
  Future<Map<String, dynamic>?> readSession();
  Future<void> saveSession(Map<String, dynamic> session);
  Future<void> clearSession();
  Future<List<Map<String, dynamic>>> readServers();
  Future<void> saveServers(List<Map<String, dynamic>> servers);
  Future<String> readLanguage();
  Future<void> saveLanguage(String language);
  Future<String> readTheme();
  Future<void> saveTheme(String theme);
  Future<Map<String, dynamic>?> readChoice(String scope);
  Future<void> saveChoice(String scope, Map<String, dynamic> choice);

  /// Legacy compatibility storage for local conversation preferences.
  /// Categories are server-backed and are not persisted through this API.
  Future<Map<String, dynamic>> readConversationOrganization(
    String scope,
  ) async {
    final key =
        'chatstudio.conversation-organization.v1.${base64Url.encode(utf8.encode(scope))}';
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return <String, dynamic>{};
    try {
      return asMap(jsonDecode(raw));
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  Future<void> saveConversationOrganization(
    String scope,
    Map<String, dynamic> organization,
  ) async {
    final key =
        'chatstudio.conversation-organization.v1.${base64Url.encode(utf8.encode(scope))}';
    await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(organization),
    );
  }

  Future<bool> readReadingHintSeen();
  Future<void> markReadingHintSeen();
}

class SecureAppStorage extends AppStorage {
  final _secure = const FlutterSecureStorage();
  @override
  Future<String> readLanguage() async =>
      (await SharedPreferences.getInstance()).getString('language') ?? 'zh';
  @override
  Future<void> saveLanguage(String language) async {
    await (await SharedPreferences.getInstance()).setString(
      'language',
      language,
    );
  }

  static const _session = 'chatstudio.session.v1';
  @override
  Future<List<Map<String, dynamic>>> readServers() async {
    final raw = await _secure.read(key: 'chatstudio.servers.v1');
    if (raw == null) return [];
    try {
      return asList(
        jsonDecode(raw),
      ).map(asMap).where((s) => text(s['server']).isNotEmpty).toList();
    } on FormatException {
      return [];
    }
  }

  @override
  Future<void> saveServers(List<Map<String, dynamic>> servers) =>
      _secure.write(key: 'chatstudio.servers.v1', value: jsonEncode(servers));
  String _choiceKey(String scope) =>
      'chatstudio.choice.v1.${base64Url.encode(utf8.encode(scope))}';
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
  Future<String> readTheme() async =>
      (await SharedPreferences.getInstance()).getString('theme') ?? 'system';
  @override
  Future<void> saveTheme(String theme) async =>
      (await SharedPreferences.getInstance()).setString('theme', theme);
}
