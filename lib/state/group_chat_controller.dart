import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/group_chat_transport.dart';
import '../data/models.dart';
import '../data/studio_api.dart';
import 'chat_timeline.dart';
import 'conversation_state.dart';

class GroupChatController extends ChangeNotifier {
  GroupChatController({
    required this.api,
    required this.room,
    GroupChatTransport? transport,
    this.ackTimeout = const Duration(seconds: 30),
  }) : transport = transport ?? GroupChatTransport();
  final StudioApi api;
  final Duration ackTimeout;
  GroupRoom room;
  final GroupChatTransport transport;
  final draft = ConversationDraft();
  final timeline = ChatTimeline();
  final messages = <GroupChatMessage>[];
  List<GroupAgentSummary> agents = const [];
  bool loading = true, sending = false, connected = false;
  bool hasMore = false;
  String? error;
  int total = 0;
  bool _disposed = false;
  bool _joined = false;
  bool _joining = false;
  int _generation = 0;
  Timer? _streamNotification;
  String? _pendingId, _pendingSignature;
  bool get canSend => connected && _joined && !sending;
  bool get working => messages.any((m) => m.isStreaming);
  List<ChatMessage> get displayMessages => timeline.displayMessages;
  final _uuid = const Uuid();

  Future<void> start() async {
    final generation = ++_generation;
    transport.dispose();
    connected = _joined = _joining = false;
    error = null;
    loading = true;
    _notify();
    try {
      final detail = await api.groupRoomDetail(room.id);
      if (_disposed || generation != _generation) return;
      room = detail.room;
      agents = detail.agents;
      messages
        ..clear()
        ..addAll(detail.messages);
      total = detail.total;
      hasMore = detail.hasMore;
      loading = false;
      _notify();
      transport.connect(api, _onEvent);
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = '$e';
      loading = false;
      _notify();
    }
  }

  Future<void> loadOlder() async {
    if (loading || !hasMore || messages.isEmpty) return;
    final generation = _generation;
    loading = true;
    _notify();
    try {
      final detail = await api.groupRoomDetail(
        room.id,
        before: messages.first.id,
        history: true,
      );
      if (_disposed || generation != _generation) return;
      final ids = messages.map((message) => message.id).toSet();
      messages.insertAll(
        0,
        detail.messages.where((message) => !ids.contains(message.id)),
      );
      total = detail.total;
      hasMore = detail.hasMore;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = '$e';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  void _onEvent(String event, Map<String, dynamic> data) {
    if (_disposed) return;
    final roomId = text(data['roomId'] ?? data['room_id']);
    if (roomId.isNotEmpty && roomId != room.id) return;
    switch (event) {
      case 'connected':
        connected = true;
        _join();
        break;
      case 'disconnected':
        _generation++;
        _joining = false;
        loading = false;
        connected = false;
        _joined = false;
        _notify();
        break;
      case 'connection.error':
        _generation++;
        _joining = false;
        connected = false;
        _joined = false;
        loading = false;
        error = text(data['error']);
        _notify();
        break;
      case 'message':
        _upsert(GroupChatMessage.fromJson({'roomId': room.id, ...data}));
        break;
      case 'message_stream_start':
        _upsert(
          GroupChatMessage.fromJson({
            'roomId': room.id,
            ...data,
            'finish_reason': 'streaming',
            'senderType': 'agent',
            'role': 'assistant',
          }),
        );
        break;
      case 'message_stream_delta':
        _append(data, reasoning: false);
        break;
      case 'message_reasoning_delta':
        _append(data, reasoning: true);
        break;
      case 'message_stream_end':
        _finish(text(data['id']));
        break;
      case 'agents_updated':
        agents = asList(
          data['agents'],
        ).map((a) => GroupAgentSummary.fromJson(asMap(a))).toList();
        _notify();
        break;
      case 'room_cleared':
        messages.clear();
        hasMore = false;
        total = 0;
        _notify();
        break;
    }
  }

  Future<void> _join() async {
    if (_joined || _joining || !connected) return;
    final generation = _generation;
    _joining = true;
    try {
      final response = await transport
          .emitAck('join', {'roomId': room.id})
          .timeout(ackTimeout);
      if (_disposed || generation != _generation || !connected) return;
      if (response['error'] != null) {
        throw ApiException(text(response['error']));
      }
      if (response['agents'] is List) {
        agents = asList(
          response['agents'],
        ).map((a) => GroupAgentSummary.fromJson(asMap(a))).toList();
      }
      // Reconnect snapshots replace matching messages; never append final text
      // to the partially received stream from before the network interruption.
      for (final raw in asList(response['messages'])) {
        _upsert(
          GroupChatMessage.fromJson({'roomId': room.id, ...asMap(raw)}),
          notify: false,
        );
      }
      if (response.containsKey('hasMore')) hasMore = flag(response['hasMore']);
      if (response.containsKey('total')) total = integer(response['total']);
      error = null;
      _joined = true;
      loading = false;
      _notify();
    } catch (e) {
      if (_disposed || generation != _generation) return;
      loading = false;
      error = '$e';
      _notify();
    } finally {
      if (generation == _generation) _joining = false;
    }
  }

  void _upsert(GroupChatMessage message, {bool notify = true}) {
    if (message.id.isEmpty) return;
    if (message.roomId.isNotEmpty && message.roomId != room.id) {
      return;
    }
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      messages.add(message);
      total = total < messages.length ? messages.length : total;
    } else {
      final existing = messages[index];
      if (!existing.isStreaming && message.isStreaming) return;
      messages[index] = message.copyWith(
        content: message.content.isEmpty ? existing.content : message.content,
        reasoning: message.reasoning.isEmpty
            ? existing.reasoning
            : message.reasoning,
        finishReason: message.finishReason.isEmpty
            ? existing.finishReason
            : message.finishReason,
        isStreaming: message.isStreaming,
      );
    }
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    if (notify) _notify();
  }

  void _append(Map<String, dynamic> data, {required bool reasoning}) {
    final id = text(data['id']);
    final delta = text(data['delta']);
    if (id.isEmpty || delta.isEmpty) {
      return;
    }
    final index = messages.indexWhere((item) => item.id == id);
    if (index < 0) {
      return;
    }
    final current = messages[index];
    if (!current.isStreaming) return;
    messages[index] = current.copyWith(
      content: reasoning ? current.content : current.content + delta,
      reasoning: reasoning ? current.reasoning + delta : current.reasoning,
      isStreaming: true,
    );
    _streamNotification ??= Timer(const Duration(milliseconds: 32), _notify);
  }

  void _finish(String id) {
    final index = messages.indexWhere((item) => item.id == id);
    if (index < 0) {
      return;
    }
    messages[index] = messages[index].copyWith(
      isStreaming: false,
      finishReason: messages[index].finishReason == 'streaming'
          ? ''
          : messages[index].finishReason,
    );
    _notify();
  }

  List<GroupChatMention> mentionsFor(String content) {
    final result = <GroupChatMention>[];
    if (room.canMentionAll &&
        RegExp(
          r'(^|\s)@all(?=\s|$|[,.!?，。！？])',
          caseSensitive: false,
        ).hasMatch(content)) {
      result.add(const GroupChatMention(type: 'all', displayName: 'all'));
    }
    for (final agent in agents) {
      final names = <String>{agent.name};
      if (names.any(
        (name) =>
            name.isNotEmpty &&
            RegExp(
              '(^|\\s)@${RegExp.escape(name)}(?=\\s|\$|[,.!?，。！？])',
              caseSensitive: false,
            ).hasMatch(content),
      )) {
        result.add(
          GroupChatMention(
            type: 'agent',
            participantId: agent.id.isEmpty ? agent.agentId : agent.id,
            displayName: agent.name,
          ),
        );
      }
    }
    return {
      for (final mention in result)
        mention.type == 'all'
                ? 'all'
                : mention.participantId ?? mention.displayName:
            mention,
    }.values.toList();
  }

  Future<bool> send(
    String content, {
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    final value = content.trim();
    if ((value.isEmpty && attachments.isEmpty) || sending) {
      return false;
    }
    if (!connected || !_joined) throw const ApiException('群聊连接尚未就绪，请稍后重试');
    sending = true;
    error = null;
    _notify();
    try {
      final signature = '$value|$attachments';
      if (_pendingSignature != signature) {
        _pendingId = _uuid.v4();
        _pendingSignature = signature;
      }
      final response = await transport
          .emitAck('message', {
            'roomId': room.id,
            'id': _pendingId,
            'content': attachments.isEmpty
                ? value
                : [
                    if (value.isNotEmpty) {'type': 'text', 'text': value},
                    ...attachments,
                  ],
            'mentions': mentionsFor(
              value,
            ).map((mention) => mention.toJson()).toList(),
          })
          .timeout(ackTimeout);
      if (response['error'] != null) {
        throw ApiException(text(response['error']));
      }
      _pendingId = _pendingSignature = null;
      return true;
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      sending = false;
      _notify();
    }
  }

  void _notify() {
    _streamNotification?.cancel();
    _streamNotification = null;
    if (_disposed) return;
    timeline.messages = [
      for (final message in messages)
        message.toChatMessage(
          agentType: message.senderAgentType.isNotEmpty
              ? message.senderAgentType
              : agents
                        .where(
                          (a) =>
                              a.id == message.senderAgentId ||
                              a.agentId == message.senderId ||
                              a.name == message.senderName,
                        )
                        .firstOrNull
                        ?.agent ??
                    '',
        ),
    ];
    notifyListeners();
  }

  Future<void> stop() async {
    try {
      final names = messages
          .where((m) => m.isStreaming)
          .map((m) => m.senderName)
          .toSet();
      for (final name in names) {
        final response = await transport
            .emitAck('interrupt_agent', {'roomId': room.id, 'agentName': name})
            .timeout(ackTimeout);
        if (response['error'] != null) {
          throw ApiException(text(response['error']));
        }
      }
    } catch (e) {
      error = '$e';
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _streamNotification?.cancel();
    transport.dispose();
    super.dispose();
  }
}
