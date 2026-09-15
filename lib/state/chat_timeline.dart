import '../data/models.dart';

/// Pure reducer. Historical pages are authoritative; live tokens affect only one
/// pending bubble. It is independent of widgets and of the Socket.IO library.
class ChatTimeline {
  List<ChatMessage> messages = [];
  String? runId;
  bool working = false;
  Map<String, dynamic>? interaction;
  String activity = '';
  int liveRevision = 0;
  final Set<String> _finishedRuns = {};

  void clear() {
    messages = [];
    _finishedRuns.clear();
    runId = null;
    working = false;
    interaction = null;
    activity = '';
  }

  void begin(
    String input,
    String localId, {
    List<MessageAttachment> attachments = const [],
  }) {
    messages = [
      ...messages,
      ChatMessage(
        id: localId,
        role: 'user',
        content: input,
        pending: true,
        attachments: attachments,
        delivery: 'sending',
      ),
    ];
    working = true;
    activity = '正在发送';
    interaction = null;
  }

  void replace(List<ChatMessage> history, {bool keepOlder = false}) {
    final old = messages;
    final used = <String>{};
    messages = history.where((m) => m.visible).map((next) {
      final eligible = old.where(
        (m) => !used.contains(m.renderKey) && m.role == next.role,
      );
      final match =
          eligible.where((m) => m.id == next.id).firstOrNull ??
          eligible
              .where(
                (m) =>
                    (m.renderKey.startsWith('local:') ||
                        m.renderKey.startsWith('stream:')) &&
                    m.content == next.content &&
                    m.content.isNotEmpty,
              )
              .firstOrNull;
      if (match == null) return next;
      used.add(match.renderKey);
      return next.copyWith(
        localKey: match.renderKey,
        delivery:
            next.delivery.isEmpty &&
                ['failed', 'stopped'].contains(match.delivery)
            ? match.delivery
            : next.delivery,
        failure: next.failure.isEmpty && match.delivery == 'failed'
            ? match.failure
            : next.failure,
        tools: next.tools.isEmpty
            ? match.tools
            : next.tools
                  .map(
                    (t) => t.status == 'recorded'
                        ? match.tools
                                  .where((old) => old.id == t.id)
                                  .firstOrNull ??
                              t
                        : t,
                  )
                  .toList(),
        attachments: next.attachments.map((f) {
          final previous = match.attachments
              .where((a) => a.path == f.path)
              .firstOrNull;
          return f.size > 0 || previous == null ? f : previous;
        }).toList(),
      );
    }).toList();
    if (keepOlder && messages.isNotEmpty) {
      final first = messages.first;
      final overlap = old.indexWhere(
        (m) => m.id == first.id || m.renderKey == first.renderKey,
      );
      if (overlap > 0) messages = [...old.take(overlap), ...messages];
    }
  }

  /// Keep one visual assistant turn, while raw rows still determine pagination.
  List<ChatMessage> get displayMessages {
    final result = <ChatMessage>[];
    for (final message in messages.where((m) => m.visible)) {
      if (message.role == 'assistant' &&
          result.isNotEmpty &&
          result.last.role == 'assistant') {
        final old = result.removeLast();
        result.add(
          old.copyWith(
            content: [
              old.content,
              message.content,
            ].where((s) => s.isNotEmpty).join('\n\n'),
            reasoning: [
              old.reasoning,
              message.reasoning,
            ].where((s) => s.isNotEmpty).join('\n'),
            tools: {
              ...{for (final t in old.tools) t.id: t},
              ...{for (final t in message.tools) t.id: t},
            }.values.toList(),
            attachments: [...old.attachments, ...message.attachments],
            pending: old.pending || message.pending,
            failure: message.failure.isNotEmpty ? message.failure : old.failure,
            delivery: message.delivery.isNotEmpty
                ? message.delivery
                : old.delivery,
          ),
        );
      } else {
        result.add(message);
      }
    }
    return result;
  }

  void markUncertain() {
    messages = messages
        .map(
          (m) => m.role == 'user' && m.delivery == 'sending'
              ? m.copyWith(delivery: 'uncertain')
              : m,
        )
        .toList();
  }

  void _acknowledge() {
    final lastUser = messages.lastIndexWhere((m) => m.role == 'user');
    if (lastUser < 0) return;
    final user = messages[lastUser];
    if (user.pending && ['sending', 'uncertain'].contains(user.delivery)) {
      messages = [...messages]
        ..[lastUser] = user.copyWith(pending: false, delivery: '');
    }
  }

  void _tool(String event, Map<String, dynamic> data) {
    var index = messages.lastIndexWhere(
      (m) => m.role == 'assistant' && m.pending,
    );
    if (index < 0) {
      _assistant();
      index = messages.length - 1;
    }
    final message = messages[index];
    final id = text(data['tool_call_id'] ?? data['id']);
    final name = text(data['tool_name'] ?? data['tool'] ?? data['name']);
    final tool = ToolActivity(
      id: id.isEmpty ? name : id,
      name: name.isEmpty ? '工具' : name,
      status: event == 'tool.completed'
          ? 'done'
          : event == 'tool.failed'
          ? 'failed'
          : 'running',
    );
    messages = [...messages]
      ..[index] = message.copyWith(
        tools: {
          ...{for (final t in message.tools) t.id: t},
          tool.id: tool,
        }.values.take(100).toList(),
      );
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
        _acknowledge();
        messages = messages
            .map(
              (m) => m.role == 'user' && m.pending
                  ? m.copyWith(pending: false)
                  : m,
            )
            .toList();
      case 'message.delta':
        liveRevision++;
        _acknowledge();
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
        _tool(event, data);
        activity =
            '正在使用 ${text(data['tool_name'] ?? data['tool'] ?? data['name'])}';
      case 'tool.completed':
      case 'tool.failed':
        _tool(event, data);
        activity = '';
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
        _acknowledge();
        liveRevision++;
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
        final lastUser = messages.lastIndexWhere((m) => m.role == 'user');
        messages = messages.indexed.map((entry) {
          final m = entry.$2;
          return m.copyWith(
            pending: false,
            delivery:
                entry.$1 == lastUser && (m.delivery != 'uncertain' || m.pending)
                ? (event == 'run.failed' ? 'failed' : 'stopped')
                : m.delivery,
            failure:
                entry.$1 == lastUser &&
                    event == 'run.failed' &&
                    (m.delivery != 'uncertain' || m.pending)
                ? (text(data['error']).isEmpty
                      ? '生成失败，请检查模型配置'
                      : text(data['error']))
                : m.failure,
            tools: m.tools
                .map(
                  (t) => t.status == 'running'
                      ? ToolActivity(id: t.id, name: t.name, status: 'stopped')
                      : t,
                )
                .toList(),
          );
        }).toList();
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
    final previous = messages;
    final unresolved = messages
        .where((m) => m.delivery == 'uncertain')
        .toList();
    clear();
    messages = previous;
    replace(
      asList(
        data['messages'],
      ).map((m) => ChatMessage.fromJson(asMap(m))).toList(),
      keepOlder: flag(data['hasMoreBefore']),
    );
    working = flag(data['isWorking']);
    for (final m in unresolved) {
      if (!messages.any(
        (n) =>
            n.renderKey == m.renderKey ||
            (n.role == m.role && n.content == m.content),
      )) {
        messages.add(m.copyWith(delivery: 'uncertain', pending: false));
      }
    }
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
