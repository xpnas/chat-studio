import '../data/models.dart';

/// Pure reducer. Historical pages are authoritative; live tokens affect only one
/// pending bubble. It is independent of widgets and of the Socket.IO library.
class ChatTimeline {
  List<ChatMessage> messages = [];
  String? runId;
  bool working = false;
  Map<String, dynamic>? interaction;
  String activity = '';
  final Set<String> _finishedRuns = {};

  void clear() {
    messages = [];
    _finishedRuns.clear();
    runId = null;
    working = false;
    interaction = null;
    activity = '';
  }

  void begin(String input, String localId) {
    messages = [
      ...messages,
      ChatMessage(id: localId, role: 'user', content: input, pending: true),
    ];
    working = true;
    activity = '正在发送';
    interaction = null;
  }

  void replace(List<ChatMessage> history) {
    messages = history.where((m) => m.visible).toList();
  }

  void prepend(List<ChatMessage> history) {
    final ids = messages.map((m) => m.id).toSet();
    messages = [
      ...history.where((m) => m.visible && !ids.contains(m.id)),
      ...messages,
    ];
  }

  void _assistant({
    String? delta,
    String? reasoning,
    String? output,
    String? id,
    bool done = false,
  }) {
    final index = messages.lastIndexWhere(
      (m) => m.role == 'assistant' && m.pending,
    );
    final old = index >= 0
        ? messages[index]
        : ChatMessage(
            id: 'stream:${runId ?? 'pending'}',
            role: 'assistant',
            content: '',
            pending: true,
          );
    final next = old.copyWith(
      id: id,
      content: output ?? '${old.content}${delta ?? ''}',
      reasoning: '${old.reasoning}${reasoning ?? ''}',
      pending: !done,
    );
    if (index >= 0) {
      messages = [...messages]..[index] = next;
    } else if (next.content.isNotEmpty || next.reasoning.isNotEmpty || !done) {
      messages = [...messages, next];
    }
  }

  bool apply(String event, Map<String, dynamic> data) {
    final incomingRun = text(data['run_id']);
    if (incomingRun.isNotEmpty && _finishedRuns.contains(incomingRun)) {
      return false;
    }
    if (event != 'run.started' &&
        incomingRun.isNotEmpty &&
        runId != null &&
        incomingRun != runId) {
      return false;
    }
    switch (event) {
      case 'run.started':
        runId = incomingRun.isEmpty ? null : incomingRun;
        working = true;
        activity = '正在思考';
        messages = messages
            .map(
              (m) => m.role == 'user' && m.pending
                  ? m.copyWith(pending: false)
                  : m,
            )
            .toList();
      case 'message.delta':
        working = true;
        activity = '';
        _assistant(delta: messageText(data['delta']));
      case 'reasoning.delta':
        _assistant(reasoning: messageText(data['delta']));
      case 'run.peer_user_message':
        final content = messageText(data['content'] ?? data['input']);
        if (content.isNotEmpty) {
          messages = [
            ...messages,
            ChatMessage(
              id: '${data['message_id'] ?? DateTime.now().microsecondsSinceEpoch}',
              role: 'user',
              content: content,
            ),
          ];
        }
      case 'tool.started':
      case 'tool.call':
        activity =
            '正在使用 ${text(data['tool_name'] ?? data['tool'] ?? data['name'])}';
      case 'approval.requested':
      case 'clarify.requested':
        if (data['remaining_timeout_ms'] != null &&
            integer(data['remaining_timeout_ms']) <= 0) {
          return false;
        }
        interaction = {...data, 'kind': event};
        activity = '等待你的确认';
      case 'approval.resolved':
      case 'clarify.resolved':
        final idKey = event.startsWith('approval')
            ? 'approval_id'
            : 'clarify_id';
        if (interaction?[idKey] == data[idKey]) interaction = null;
        activity = '';
      case 'run.completed':
        final output = data['output'];
        _assistant(
          output: output == null ? null : messageText(output),
          id: data['message_id']?.toString(),
          done: true,
        );
        working = false;
        interaction = null;
        activity = '';
        if (runId != null) _finishedRuns.add(runId!);
        if (_finishedRuns.length > 100) {
          _finishedRuns.remove(_finishedRuns.first);
        }
        runId = null;
      case 'run.failed':
      case 'abort.completed':
        messages = messages.map((m) => m.copyWith(pending: false)).toList();
        working = false;
        interaction = null;
        activity = '';
        if (runId != null) _finishedRuns.add(runId!);
        if (_finishedRuns.length > 100) {
          _finishedRuns.remove(_finishedRuns.first);
        }
        runId = null;
    }
    return true;
  }

  void resume(Map<String, dynamic> data) {
    clear();
    replace(
      asList(
        data['messages'],
      ).map((m) => ChatMessage.fromJson(asMap(m))).toList(),
    );
    working = flag(data['isWorking']);
    if (!working) return;
    final events = asList(data['events']).map(asMap).toList();
    final start = events.lastIndexWhere((e) => e['event'] == 'run.started');
    final currentEvents = events.skip(start < 0 ? 0 : start).toList();
    final marker = currentEvents
        .map((e) => text(asMap(e['data'])['run_id']))
        .where((id) => id.isNotEmpty)
        .lastOrNull;
    // Hermes snapshots may already include the in-flight assistant. Ekko
    // snapshots may only include the user, with partial text in replay events.
    // Never append replay text to a snapshot that already contains those tokens.
    final rows = asList(data['messages']).map(asMap).toList();
    final tail = rows.lastOrNull;
    final tailMarker = tail == null
        ? ''
        : text(tail['runMarker'] ?? tail['run_marker'] ?? tail['run_id']);
    final hasSnapshot =
        tail != null &&
        tail['role'] == 'assistant' &&
        ((marker != null && marker == tailMarker) ||
            (tail.containsKey('finish_reason') &&
                tail['finish_reason'] == null) ||
            (tail.containsKey('finishReason') && tail['finishReason'] == null));
    if (hasSnapshot &&
        messages.isNotEmpty &&
        messages.last.role == 'assistant') {
      messages = [...messages]
        ..[messages.length - 1] = messages.last.copyWith(pending: true);
    }
    for (final entry in currentEvents) {
      final event = text(entry['event']);
      if (hasSnapshot &&
          (event == 'message.delta' || event == 'reasoning.delta')) {
        continue;
      }
      // User messages in the authoritative snapshot must not be echoed again.
      if (event == 'run.peer_user_message') continue;
      apply(event, asMap(entry['data']));
    }
    working = flag(data['isWorking']);
    if (activity.isEmpty && !messages.any((m) => m.pending)) {
      activity = '正在继续生成';
    }
  }
}
