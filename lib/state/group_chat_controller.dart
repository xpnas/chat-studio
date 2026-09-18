import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/group_chat_transport.dart';
import '../data/models.dart';
import '../data/studio_api.dart';

class GroupChatController extends ChangeNotifier {
  GroupChatController({required this.api, required this.room});
  final StudioApi api;
  GroupRoom room;
  final transport = GroupChatTransport();
  final messages = <GroupChatMessage>[];
  List<GroupAgentSummary> agents = const [];
  bool loading = true, sending = false, connected = false;
  bool hasMore = false;
  String? error;
  int total = 0;
  bool _disposed = false;
  bool _joined = false;
  final _uuid = const Uuid();

  Future<void> start() async {
    error = null;
    loading = true;
    _notify();
    try {
      final detail = await api.groupRoomDetail(room.id);
      room = detail.room;
      agents = detail.agents;
      messages
        ..clear()
        ..addAll(detail.messages);
      total = detail.total;
      hasMore = detail.hasMore;
      _notify();
      transport.connect(api, _onEvent);
    } catch (e) {
      error = '$e';
      loading = false;
      _notify();
    }
  }

  Future<void> loadOlder() async {
    if (loading || !hasMore || messages.isEmpty) return;
    loading = true;
    _notify();
    try {
      final detail = await api.groupRoomDetail(
        room.id,
        before: messages.first.id,
        history: true,
      );
      final ids = messages.map((message) => message.id).toSet();
      messages.insertAll(
        0,
        detail.messages.where((message) => !ids.contains(message.id)),
      );
      total = detail.total;
      hasMore = detail.hasMore;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      _notify();
    }
  }

  void _onEvent(String event, Map<String, dynamic> data) {
    switch (event) {
      case 'connected':
        connected = true;
        _join();
        break;
      case 'disconnected':
        connected = false;
        _joined = false;
        _notify();
        break;
      case 'connection.error':
        connected = false;
        error = text(data['error']);
        _notify();
        break;
      case 'message':
        _upsert(GroupChatMessage.fromJson(data));
        break;
      case 'message_stream_start':
        _upsert(
          GroupChatMessage.fromJson({
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
    }
  }

  Future<void> _join() async {
    if (_joined || !connected) return;
    try {
      final response = await transport.emitAck('join', {'roomId': room.id});
      if (response['error'] != null) {
        throw ApiException(text(response['error']));
      }
      _joined = true;
      loading = false;
      _notify();
    } catch (e) {
      loading = false;
      error = '$e';
      _notify();
    }
  }

  void _upsert(GroupChatMessage message) {
    if (message.roomId.isNotEmpty && message.roomId != room.id) {
      return;
    }
    final index = messages.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      messages.add(message);
      total = total < messages.length ? messages.length : total;
    } else {
      final existing = messages[index];
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
    _notify();
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
    messages[index] = current.copyWith(
      content: reasoning ? current.content : current.content + delta,
      reasoning: reasoning ? current.reasoning + delta : current.reasoning,
      isStreaming: true,
    );
    _notify();
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
    if (RegExp(r'(^|\s)@all(?:\s|$)', caseSensitive: false).hasMatch(content)) {
      result.add(const GroupChatMention(type: 'all', displayName: 'all'));
    }
    for (final agent in agents) {
      final names = <String>{agent.name, agent.agent};
      if (names.any(
        (name) =>
            name.isNotEmpty &&
            content.toLowerCase().contains('@${name.toLowerCase()}'),
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

  Future<void> send(String content) async {
    final value = content.trim();
    if (value.isEmpty || sending) {
      return;
    }
    if (!connected || !_joined) throw const ApiException('群聊连接尚未就绪，请稍后重试');
    sending = true;
    error = null;
    _notify();
    try {
      final response = await transport.emitAck('message', {
        'roomId': room.id,
        'id': _uuid.v4(),
        'content': value,
        'mentions': mentionsFor(
          value,
        ).map((mention) => mention.toJson()).toList(),
      });
      if (response['error'] != null) {
        throw ApiException(text(response['error']));
      }
    } catch (e) {
      error = '$e';
      rethrow;
    } finally {
      sending = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    transport.dispose();
    super.dispose();
  }
}
