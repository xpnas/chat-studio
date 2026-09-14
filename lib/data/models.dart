import 'dart:convert';

Map<String, dynamic> asMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<dynamic> asList(dynamic value) => value is List ? value : const [];
String text(dynamic value) => value is String ? value : '';
int integer(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
bool flag(dynamic value) => value == true || value == 1;

String messageText(dynamic value) {
  if (value is String) {
    // Some persisted messages serialize content blocks instead of plain text.
    if (value.trimLeft().startsWith('[')) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return messageText(decoded);
      } on FormatException {
        /* Ordinary text, not JSON. */
      }
    }
    return value;
  }
  if (value is List) {
    return value
        .map((block) {
          final data = asMap(block);
          if (data['type'] == 'text' || data['type'] == 'input_text') {
            return text(data['text']);
          }
          if (data['type'] == 'image' || data['type'] == 'image_url') {
            return '[图片]';
          }
          return '';
        })
        .where((part) => part.isNotEmpty)
        .join('\n');
  }
  return '';
}

class Account {
  const Account({
    required this.id,
    required this.username,
    required this.role,
    this.createdAt = 0,
    this.requiresCredentialChange = false,
  });
  final int id;
  final String username, role;
  final int createdAt;
  final bool requiresCredentialChange;
  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: integer(json['id']),
    username: text(json['username']),
    role: text(json['role']),
    createdAt: integer(json['created_at']),
    requiresCredentialChange: flag(json['requiresCredentialChange']),
  );
}

class ModelChoice {
  const ModelChoice({
    required this.id,
    required this.provider,
    required this.label,
    this.providerLabel = '',
    this.apiMode = '',
  });
  final String id, provider, label, providerLabel, apiMode;
  String get key => '$provider::$id';
  static List<ModelChoice> parseGroups(dynamic raw) => asList(raw).expand((
    rawGroup,
  ) {
    final group = asMap(rawGroup);
    final metadata = asMap(group['model_meta']);
    return asList(group['models'])
        .whereType<String>()
        .where((id) => !flag(asMap(metadata[id])['disabled']))
        .map(
          (id) => ModelChoice(
            id: id,
            provider: text(group['provider']),
            label: text(asMap(metadata[id])['alias']).isEmpty
                ? id
                : text(asMap(metadata[id])['alias']),
            providerLabel: text(group['label']),
            apiMode: text(group['api_mode']),
          ),
        );
    // Deliberately never retain server provider credentials (api_key/base_url).
  }).toList();
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    this.preview = '',
    this.profile = 'default',
    this.agent = '',
    this.source = '',
    this.model = '',
    this.provider = '',
    this.updatedAt = 0,
  });
  final String id, title, preview, profile, agent, source, model, provider;
  final int updatedAt;
  bool get canContinue =>
      (agent.isEmpty || agent == 'hermes' || agent == 'ekko-agent') &&
      !['workflow', 'group_chat', 'global_agent'].contains(source);
  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: text(json['id']),
    title: text(json['title']).isEmpty ? '未命名对话' : text(json['title']),
    preview: text(json['preview']),
    profile: text(json['profile']).isEmpty ? 'default' : text(json['profile']),
    agent: text(json['agent']),
    source: text(json['source']),
    model: text(json['model']),
    provider: text(json['provider']),
    updatedAt: integer(json['last_active'] ?? json['started_at']),
  );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.reasoning = '',
    this.pending = false,
  });
  final String id, role, content, reasoning;
  final bool pending;
  bool get visible => role == 'user' || role == 'assistant';
  ChatMessage copyWith({
    String? id,
    String? content,
    String? reasoning,
    bool? pending,
  }) => ChatMessage(
    id: id ?? this.id,
    role: role,
    content: content ?? this.content,
    reasoning: reasoning ?? this.reasoning,
    pending: pending ?? this.pending,
  );
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: '${json['id'] ?? json['message_id'] ?? ''}',
    role: text(json['display_role']).isNotEmpty
        ? text(json['display_role'])
        : text(json['role']),
    content: messageText(json['display_content'] ?? json['content']),
    reasoning: messageText(json['reasoning_content'] ?? json['reasoning']),
  );
}

class MessagePage {
  const MessagePage(this.messages, this.offset, this.total, this.hasMore);
  final List<ChatMessage> messages;
  final int offset, total;
  final bool hasMore;
}

class ApiException implements Exception {
  const ApiException(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}
