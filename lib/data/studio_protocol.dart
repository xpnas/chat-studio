/// External Studio v1.0.3 protocol values, NOT client branding.
/// Keep these exact values: the server stores them in conversations and uses
/// the icon filename on its Agent Manager. Renaming them breaks compatibility.
abstract final class StudioProtocol {
  static const builtInAgentId = 'ekko-agent';
  static const builtInAgentName = 'Ekko';
  static const builtInAgentLabel = '$builtInAgentName Agent';
  static const builtInAgentIcon = 'ekko-agent.png';
  static const builtInAgentAlias = 'ekko';
  static const builtInAgentLegacyAlias = 'ekko_agent';
}
