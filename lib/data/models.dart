import 'agent_catalog.dart';
import 'task_plan.dart';
import 'package:mime/mime.dart';
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
            return '[图片：${text(data['name']).isEmpty ? '附件' : text(data['name'])}]';
          }
          if (data['type'] == 'file' || data['type'] == 'audio') {
            return '[文件：${text(data['name'])}]';
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

class ConversationCategory {
  const ConversationCategory({
    required this.id,
    required this.name,
    this.createdAt = 0,
    this.updatedAt = 0,
  });
  final int id;
  final String name;
  final int createdAt, updatedAt;

  factory ConversationCategory.fromJson(Map<String, dynamic> json) =>
      ConversationCategory(
        id: integer(json['id']),
        name: text(json['name']),
        createdAt: integer(json['created_at']),
        updatedAt: integer(json['updated_at']),
      );
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
    this.reasoningEffort = '',
    this.categoryId,
    this.isPinned = false,
    this.isArchived = false,
  });
  final String reasoningEffort;
  final String id, title, preview, profile, agent, source, model, provider;
  final int updatedAt;
  final int? categoryId;
  final bool isPinned, isArchived;
  bool get canContinue =>
      (agent.isEmpty ||
          AgentChoice.supportedIds.contains(AgentChoice.canonicalId(agent))) &&
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
    reasoningEffort: text(json['reasoning_effort']),
    updatedAt: integer(json['last_active'] ?? json['started_at']),
    categoryId: json['category_id'] == null
        ? null
        : integer(json['category_id']),
    isPinned: flag(json['is_pinned']),
    isArchived: flag(json['is_archived']),
  );
}

class MessageAttachment {
  const MessageAttachment({
    required this.name,
    required this.path,
    required this.mimeType,
    this.size = 0,
  });
  final String name, path, mimeType;
  final int size;
  bool get isImage => mimeType.startsWith('image/');
  String get audioMime =>
      mimeType.toLowerCase().startsWith('audio/') && mimeType != 'audio/*'
      ? mimeType
      : lookupMimeType(path) ?? lookupMimeType(name) ?? mimeType;
  bool get isAudio =>
      mimeType.toLowerCase().startsWith('audio/') ||
      ((mimeType.isEmpty || mimeType == 'application/octet-stream') &&
          audioMime.startsWith('audio/'));

  String get sizeLabel => size <= 0
      ? '大小未知'
      : size < 1024 * 1024
      ? '${(size / 1024).ceil()} KB'
      : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  Map<String, dynamic> toBlock() => {
    'type': isImage ? 'image' : 'file',
    'name': name,
    'path': path,
    'media_type': mimeType,
    if (size > 0) 'size': size,
  };
  static List<MessageAttachment> parse(dynamic value) {
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return [];
      }
    }
    return asList(value)
        .map(asMap)
        .where(
          (b) =>
              ['image', 'file', 'audio'].contains(b['type']) &&
              text(b['path']).isNotEmpty,
        )
        .map(
          (b) => MessageAttachment(
            name: text(b['name']).isEmpty ? '附件' : text(b['name']),
            path: text(b['path']),
            mimeType: text(b['media_type']).isEmpty
                ? (b['type'] == 'image'
                      ? 'image/*'
                      : b['type'] == 'audio'
                      ? (lookupMimeType(text(b['path'])) ?? 'audio/*')
                      : 'application/octet-stream')
                : text(b['media_type']),
            size: integer(b['size']),
          ),
        )
        .toList();
  }
}

class ToolActivity {
  const ToolActivity({
    required this.id,
    required this.name,
    this.status = 'running',
  });
  final String id, name, status;
  String get label =>
      '$name · ${status == 'done'
          ? '已完成'
          : status == 'failed'
          ? '失败'
          : status == 'recorded'
          ? '已调用'
          : status == 'stopped'
          ? '已结束'
          : '执行中'}';
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.reasoning = '',
    this.pending = false,
    this.attachments = const [],
    this.tools = const [],
    this.delivery = '',
    this.failure = '',
    this.localKey,
    this.runMarker = '',
    this.finishReason,
    this.hasFinishReason = false,
    this.timestamp = 0,
    this.taskPlan,
  });
  final String id, role, content, reasoning;
  final bool pending;
  final List<MessageAttachment> attachments;
  final List<ToolActivity> tools;
  final String delivery, failure;
  final String? localKey;
  final String runMarker;
  final String? finishReason;
  final bool hasFinishReason;
  final num timestamp;
  final TaskPlan? taskPlan;
  String get renderKey => localKey ?? id;
  String get bodyText {
    var value = content;
    for (final file in attachments) {
      value = value.replaceAll(
        '[${file.isImage ? '图片' : '文件'}：${file.name}]',
        '',
      );
    }
    return value.trim();
  }

  bool get visible =>
      taskPlan != null ||
      (role == 'user' || role == 'assistant' || role == 'command') &&
          (content.trim().isNotEmpty ||
              reasoning.trim().isNotEmpty ||
              attachments.isNotEmpty ||
              tools.isNotEmpty ||
              failure.isNotEmpty ||
              delivery.isNotEmpty);
  ChatMessage copyWith({
    String? id,
    String? content,
    String? reasoning,
    bool? pending,
    List<MessageAttachment>? attachments,
    List<ToolActivity>? tools,
    String? delivery,
    String? failure,
    String? localKey,
    String? runMarker,
  }) => ChatMessage(
    id: id ?? this.id,
    role: role,
    content: content ?? this.content,
    reasoning: reasoning ?? this.reasoning,
    pending: pending ?? this.pending,
    attachments: attachments ?? this.attachments,
    tools: tools ?? this.tools,
    delivery: delivery ?? this.delivery,
    failure: failure ?? this.failure,
    localKey: localKey ?? this.localKey ?? this.id,
    runMarker: runMarker ?? this.runMarker,
    finishReason: finishReason,
    hasFinishReason: hasFinishReason,
    timestamp: timestamp,
    taskPlan: taskPlan,
  );
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: '${json['id'] ?? json['message_id'] ?? ''}',
    timestamp: json['timestamp'] is num ? (json['timestamp'] as num) * 1000 : 0,
    role: text(json['display_role']).isNotEmpty
        ? text(json['display_role'])
        : text(json['role']),
    runMarker: text(json['runMarker'] ?? json['run_marker'] ?? json['run_id']),
    finishReason: (json['finish_reason'] ?? json['finishReason'])?.toString(),
    hasFinishReason:
        json.containsKey('finish_reason') || json.containsKey('finishReason'),
    content: messageText(json['display_content'] ?? json['content']),
    reasoning: messageText(json['reasoning_content'] ?? json['reasoning']),
    attachments: MessageAttachment.parse(
      json['display_content'] ?? json['content'],
    ),
    tools: asList(json['tool_calls'])
        .map(asMap)
        .map(
          (t) => ToolActivity(
            id: text(t['id']),
            name: text(asMap(t['function'])['name']),
            status: 'recorded',
          ),
        )
        .toList(),
  );
}

class MessagePage {
  const MessagePage(
    this.messages,
    this.offset,
    this.total,
    this.hasMore, {
    this.taskPlans = const [],
  });
  final List<TaskPlan> taskPlans;
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

const reasoningEffortLabels = <String, String>{
  '': '默认',
  'none': '关闭',
  'minimal': '极低',
  'low': '低',
  'medium': '中',
  'high': '高',
  'xhigh': '极高',
  'max': '最高',
};
String normalizeReasoningEffort(dynamic value) =>
    reasoningEffortLabels.containsKey(value) ? value as String : '';
