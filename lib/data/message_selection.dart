import 'models.dart';
import 'protocol_capabilities.dart';
import 'session_tasks.dart';
import 'studio_api.dart';
import 'studio_protocol.dart';

class MessageSelectionGroup<T extends Object> {
  const MessageSelectionGroup(
    this.id,
    this.kind,
    this.messageIds,
    this.blockedReason,
  );
  final T id;
  final String kind, blockedReason;
  final List<T> messageIds;
  bool get selectable =>
      blockedReason.isEmpty &&
      const ['run', 'message'].contains(kind) &&
      messageIds.isNotEmpty;
}

class MessageSelection<T extends Object, R extends Object> {
  const MessageSelection(this.groups, this.historyRevision);
  final List<MessageSelectionGroup<T>> groups;
  final R historyRevision;
  static MessageSelection<T, R> parse<T extends Object, R extends Object>(
    Map<String, dynamic> json,
    bool Function(T) validId,
    bool Function(R) validRevision,
  ) {
    if (json['historyRevision'] is! R ||
        !validRevision(json['historyRevision'] as R) ||
        json['groups'] is! List) {
      throw const FormatException('Invalid history selection');
    }
    final seen = <T>{}, groupIds = <T>{};
    final groups = <MessageSelectionGroup<T>>[];
    for (final raw in asList(json['groups'])) {
      final row = asMap(raw), ids = asList(asMap(raw)['messageIds']);
      if (row['id'] is! T ||
          !validId(row['id'] as T) ||
          !groupIds.add(row['id'] as T) ||
          ids.isEmpty ||
          ids.any((id) => id is! T || !validId(id) || !seen.add(id))) {
        throw const FormatException('Invalid or overlapping history groups');
      }
      groups.add(
        MessageSelectionGroup(
          row['id'] as T,
          text(row['kind']),
          List<T>.unmodifiable(ids.cast<T>()),
          text(row['deleteBlockedReason']),
        ),
      );
    }
    return MessageSelection(
      List.unmodifiable(groups),
      json['historyRevision'] as R,
    );
  }
}

bool supportsSessionSelection(Conversation? session) =>
    session != null &&
    !session.id.startsWith('person-') &&
    const [
      'cli',
      'api_server',
      'desktop',
      'builtin_agent',
    ].contains(session.source) &&
    const [
      '',
      'hermes',
      StudioProtocol.builtInAgentId,
      'builtin',
    ].contains(session.agent);

extension MessageSelectionApi on StudioApi {
  Future<MessageSelection<int, int>> sessionMessageSelection(String id) async =>
      MessageSelection.parse<int, int>(
        await readCapability(
          ProtocolCapability.messageSelection,
          '/api/studio/sessions/${Uri.encodeComponent(id)}/message-selection',
          query: {'profile': profile},
          isMissingRoute: missingReadRoute,
        ),
        (id) => id > 0,
        (revision) => revision >= 0,
      );
  Future<MessageSelection<String, String>> groupMessageSelection(
    String id,
  ) async => MessageSelection.parse<String, String>(
    await readCapability(
      ProtocolCapability.messageSelection,
      '/api/studio/group-chat/rooms/${Uri.encodeComponent(id)}/message-selection',
      isMissingRoute: missingReadRoute,
    ),
    (id) => id.isNotEmpty,
    (revision) => revision.isNotEmpty,
  );
  Future<Map<String, dynamic>> deleteSessionMessages(
    String id,
    List<int> ids,
    int revision,
  ) => request(
    '/api/studio/sessions/${Uri.encodeComponent(id)}/messages/batch-delete',
    method: 'POST',
    query: {'profile': profile},
    body: {'messageIds': ids, 'historyRevision': revision},
  );
  Future<Map<String, dynamic>> deleteGroupMessages(
    String id,
    List<String> ids,
    String revision,
  ) => request(
    '/api/studio/group-chat/rooms/${Uri.encodeComponent(id)}/messages/delete',
    method: 'POST',
    body: {'messageIds': ids, 'historyRevision': revision},
  );
}
