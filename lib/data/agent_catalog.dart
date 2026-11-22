import 'studio_protocol.dart';

/// Metadata is the pinned server's icon/routing contract, NOT an installed list.
/// Availability always comes from /api/agents/availability (non-admin endpoint).
class AgentChoice {
  static const coreIds = {StudioProtocol.builtInAgentId, 'hermes'};
  const AgentChoice(
    this.id,
    this.name,
    this.icon, {
    required this.installed,
    this.declaredModes,
    this.hasChatSurface = true,
    this.pluginEnabled = false,
  });
  final String id, name;
  final String? icon;
  final bool installed;
  final List<String>? declaredModes;
  final bool hasChatSurface, pluginEnabled;
  bool get supported =>
      supportedIds.contains(id) || (pluginEnabled && isPluginId(id));
  bool get selectable =>
      installed && supported && hasChatSurface && modes.isNotEmpty;
  List<String> get modes =>
      declaredModes ??
      switch (id) {
        StudioProtocol.builtInAgentId || 'hermes' => const ['scoped'],
        'cursor' || 'qoder' => const ['global'],
        _ => supported ? const ['scoped', 'global'] : const [],
      };
  String get sessionAgentId => id == 'claude-code' ? 'claude' : id;
  bool get supportsContext => const {
    StudioProtocol.builtInAgentId,
    'hermes',
    'claude-code',
    'codex',
    'pi',
    'grok',
    'opencode',
    'dsh',
  }.contains(id);
  static bool isPluginId(String id) {
    if (!id.startsWith('plugin:')) return false;
    final parts = id.substring(7).split('/');
    return parts.length == 2 &&
        parts.every(
          (part) =>
              RegExp(r'^[a-z][a-z0-9._-]{0,79}$').hasMatch(part) &&
              !part.contains('..') &&
              !const {'constructor', 'prototype', '__proto__'}.contains(part),
        );
  }

  String get encodedRouteId => Uri.encodeComponent(id);

  static List<AgentChoice> parseDescriptors(
    dynamic rows, {
    bool enablePlugins = false,
  }) {
    if (rows is! List) throw const FormatException('Invalid Agent descriptors');
    final result = <String, AgentChoice>{};
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          row['status'] is! Map ||
          row['modes'] is! List ||
          row['surfaces'] is! List) {
        continue;
      }
      final rawId = row['id'] as String;
      final id = rawId.startsWith('plugin:') ? rawId : canonicalId(rawId);
      if (!RegExp(r'^[a-z0-9_-]{1,100}$').hasMatch(id) && !isPluginId(id)) {
        continue;
      }
      final status = row['status'] as Map;
      if (status['installed'] is! bool) continue;
      final modes = (row['modes'] as List)
          .whereType<String>()
          .where((mode) => mode == 'scoped' || mode == 'global')
          .toSet()
          .toList();
      final meta = metadata(id);
      final choice = AgentChoice(
        id,
        row['name'] is String && (row['name'] as String).trim().isNotEmpty
            ? row['name'] as String
            : meta.name,
        meta.icon,
        installed:
            status['installed'] == true && status['source'] != 'not-installed',
        declaredModes: List.unmodifiable(modes),
        hasChatSurface: (row['surfaces'] as List).contains('chat'),
        pluginEnabled: enablePlugins,
      );
      final old = result[id];
      if (old == null) {
        result[id] = choice;
      } else {
        // Conflicting descriptions must never broaden routing or privileges.
        result[id] = AgentChoice(
          id,
          old.name,
          old.icon,
          installed: old.installed && choice.installed,
          declaredModes: List.unmodifiable(
            old.modes.where(choice.modes.contains),
          ),
          hasChatSurface: old.hasChatSurface && choice.hasChatSurface,
          pluginEnabled: enablePlugins,
        );
      }
    }
    return List.unmodifiable(result.values);
  }

  bool get supportsCompact => const {
    StudioProtocol.builtInAgentId,
    'hermes',
    'claude-code',
    'codex',
    'pi',
    'grok',
  }.contains(id);
  static const supportedIds = {
    StudioProtocol.builtInAgentId,
    'hermes',
    'claude-code',
    'codex',
    'pi',
    'grok',
    'opencode',
    'dsh',
    'qwen',
    'kimi',
    'codebuddy',
    'copilot',
    'cursor',
    'qoder',
    'antigravity',
    'zcode',
  };
  static String canonicalId(String id) => switch (id.trim().toLowerCase()) {
    StudioProtocol.builtInAgentAlias ||
    StudioProtocol.builtInAgentLegacyAlias => StudioProtocol.builtInAgentId,
    'claude' => 'claude-code',
    _ => id.trim().toLowerCase(),
  };
  static AgentChoice metadata(String input, {bool installed = false}) {
    final id = canonicalId(input);
    final (name, icon) = switch (id) {
      StudioProtocol.builtInAgentId => (
        StudioProtocol.builtInAgentName,
        StudioProtocol.builtInAgentIcon,
      ),
      'hermes' => ('Hermes', 'hermes.png'),
      'claude-code' => ('Claude', 'claude-code.svg'),
      'codex' => ('Codex', 'codex-openai.png'),
      'pi' => ('Pi', 'pi.svg'),
      'grok' => ('Grok', 'grok.svg'),
      'opencode' => ('OpenCode', 'opencode.png'),
      'dsh' => ('DSH', null),
      'qwen' => ('Qwen Code', null),
      'kimi' => ('Kimi Code', null),
      'codebuddy' => ('CodeBuddy', null),
      'copilot' => ('GitHub Copilot', null),
      'cursor' => ('Cursor', null),
      'qoder' => ('Qoder', null),
      'antigravity' => ('Antigravity', null),
      'zcode' => ('ZCode', null),
      _ => (input.trim(), null),
    };
    return AgentChoice(id, name, icon, installed: installed);
  }

  static List<AgentChoice> parse(dynamic rows) {
    if (rows is! List) {
      throw const FormatException('Invalid Agent availability');
    }
    final result = <String, AgentChoice>{};
    for (final row in rows) {
      if (row is! Map || row['id'] is! String || row['installed'] is! bool) {
        continue;
      }
      final id = canonicalId(row['id'] as String);
      if (id.isEmpty ||
          id.length > 100 ||
          !RegExp(r'^[a-z0-9_-]+$').hasMatch(id)) {
        continue;
      }
      final meta = metadata(
        id,
        installed: row['installed'] == true && row['source'] != 'not-installed',
      );
      // Conflicting duplicates cannot turn an unavailable agent into a choice.
      final old = result[id];
      if (old == null || !meta.installed) result[id] = meta;
    }
    return List.unmodifiable(result.values);
  }
}
