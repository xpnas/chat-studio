import 'studio_protocol.dart';

/// Metadata is the pinned server's icon/routing contract, NOT an installed list.
/// Availability always comes from /api/agents/availability (non-admin endpoint).
class AgentChoice {
  const AgentChoice(this.id, this.name, this.icon, {required this.installed});
  final String id, name;
  final String? icon;
  final bool installed;
  bool get supported => supportedIds.contains(id);
  bool get selectable => installed && supported;
  static const supportedIds = {
    StudioProtocol.builtInAgentId,
    'hermes',
    'claude-code',
    'codex',
    'pi',
    'grok',
    'opencode',
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
