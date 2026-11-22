import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'agent_catalog.dart';

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
  Future<Map<String, dynamic>?> readActiveAgentChoice(String scope) =>
      readChoice('v2:active:$scope');
  final _agentChoiceOperations = <String, Future<void>>{};
  String _agentChoiceKey(String scope, String agent, String mode) =>
      'v2:${jsonEncode([scope, AgentChoice.canonicalId(agent), mode])}';
  Future<T> _agentChoiceOperation<T>(String key, Future<T> Function() action) {
    final next = (_agentChoiceOperations[key] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final settled = next.then<void>((_) {}, onError: (Object _) {});
    _agentChoiceOperations[key] = settled;
    return next.whenComplete(() {
      if (identical(_agentChoiceOperations[key], settled)) {
        _agentChoiceOperations.remove(key);
      }
    });
  }

  Map<String, dynamic> _selectionFields(Map<String, dynamic> choice) => {
    for (final key in const [
      'model',
      'provider',
      'engine',
      'reasoning_effort',
      'api_mode',
      'agent_mode',
    ])
      if (choice[key] is String) key: choice[key],
  };
  Future<Map<String, dynamic>?> readAgentChoice(
    String scope,
    String agent,
    String mode,
  ) {
    final key = _agentChoiceKey(scope, agent, mode);
    return _agentChoiceOperation(key, () async {
      final saved = await readChoice(key);
      if (saved != null) return _selectionFields(saved);
      if (mode != 'scoped') return null;
      final legacy = await readChoice(scope);
      if (legacy == null ||
          AgentChoice.canonicalId(text(legacy['engine'])) !=
              AgentChoice.canonicalId(agent)) {
        return null;
      }
      final migrated = _selectionFields({
        ...legacy,
        'engine': AgentChoice.canonicalId(agent),
        'agent_mode': 'scoped',
      });
      await saveChoice(key, migrated);
      return migrated;
    });
  }

  Future<void> saveAgentChoice(
    String scope,
    String agent,
    String mode,
    Map<String, dynamic> choice,
  ) {
    final key = _agentChoiceKey(scope, agent, mode);
    return _agentChoiceOperation(key, () async {
      await saveChoice(
        key,
        _selectionFields({
          ...choice,
          'engine': AgentChoice.canonicalId(agent),
          'agent_mode': mode,
        }),
      );
      await saveChoice('v2:active:$scope', {
        'engine': AgentChoice.canonicalId(agent),
        'agent_mode': mode,
      });
    });
  }

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
