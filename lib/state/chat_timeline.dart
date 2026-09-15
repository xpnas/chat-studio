import '../data/models.dart';
import '../data/queued_message.dart';

/// Pure reducer. Historical pages are authoritative; live tokens affect only one
/// pending bubble. It is independent of widgets and of the Socket.IO library.
class ChatTimeline {
  List<ChatMessage> messages = [];
  String? runId;
  bool working = false;
  Map<String, dynamic>? interaction;
  String activity = '';
  List<QueuedMessage> queue = [];
  String? activeQueueId;
  DateTime? interactionDeadline;
  bool interactionSubmitting = false;
  String? interactionError;
  bool get interactionExpired =>
      interactionDeadline != null &&
      !DateTime.now().isBefore(interactionDeadline!);

  bool canApprove(String choice) {
    final p = interaction;
    if (p == null || interactionExpired || interactionSubmitting) return false;
    if (p['kind'] != 'approval.requested') return true;
    if (choice == 'deny') return true;
    if (!asList(p['choices']).contains(choice)) return false;
    return choice == 'once' ||
        (choice == 'always' && p['allow_permanent'] == true);
  }

  void startQueued(String id) {
    final item = queue.where((q) => q.id == id).firstOrNull;
    queue = queue.where((q) => q.id != id).toList();
    if (item != null &&
        !messages.any((m) => m.id == 'local:$id' || m.id == id)) {
      messages = [
        ...messages,
        ChatMessage(
          id: 'local:$id',
          role: 'user',
          content: item.content,
          attachments: item.attachments,
        ),
      ];
    }
    activeQueueId = id;
  }

  void reconcileQueue(dynamic value) {
    final old = {for (final q in queue) q.id: q};
    queue = asList(value)
        .map(asMap)
        .map(QueuedMessage.fromJson)
        .where((q) => q.id.isNotEmpty)
        .map(
          (q) => QueuedMessage(
            q.id,
            q.content,
            attachments: old[q.id]?.attachments ?? const [],
          ),
        )
        .toList();
  }

  int liveRevision = 0;
  final Set<String> _finishedRuns = {};

  void clear() {
    messages = [];
    _finishedRuns.clear();
    runId = null;
    working = false;
    interaction = null;
    interactionDeadline = null;
    interactionSubmitting = false;
    interactionError = null;
    queue = [];
    activeQueueId = null;
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
                    next.role == 'assistant' &&
                    next.runMarker.isNotEmpty &&
                    m.runMarker == next.runMarker &&
                    (m.renderKey.startsWith('stream:') || m.pending),
              )
              .firstOrNull ??
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
            runMarker: runId ?? '',
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
    final failedQueue = text(data['queue_id']);
    if (event == 'run.failed' &&
        failedQueue.isNotEmpty &&
        queue.any((q) => q.id == failedQueue)) {
      queue = queue
          .map((q) => q.id == failedQueue ? q.withStatus('failed') : q)
          .toList();
      return true;
    }
    if (event != 'session.command' &&
        incomingRun.isNotEmpty &&
        _finishedRuns.contains(incomingRun)) {
      return false;
    }
    if (event != 'run.started' &&
        event != 'session.command' &&
        incomingRun.isNotEmpty &&
        runId != null &&
        incomingRun != runId) {
      return false;
    }
    switch (event) {
      case 'session.command':
        _acknowledge();
        final terminal =
            data['terminal'] == true || data['action'] == 'destroy';
        if (terminal) {
          working = false;
          activity = '';
          interaction = null;
          runId = null;
          messages = messages
              .map(
                (m) => m.copyWith(
                  pending: false,
                  tools: m.tools
                      .map(
                        (t) => t.status == 'running'
                            ? ToolActivity(
                                id: t.id,
                                name: t.name,
                                status: data['ok'] == false ? 'failed' : 'done',
                              )
                            : t,
                      )
                      .toList(),
                ),
              )
              .toList();
        } else if (data['started'] == true) {
          working = true;
          activity = '正在执行命令';
        }
        final cleared =
            data['action'] == 'clear' &&
            data['command'] == 'clear' &&
            data['ok'] != false;
        if (cleared) messages = [];
        final result = text(data['message']);
        if (result.isNotEmpty && (!cleared || flag(data['clearHistory']))) {
          messages = [
            ...messages,
            ChatMessage(
              id: 'command:${DateTime.now().microsecondsSinceEpoch}:${messages.length}',
              role: 'command',
              content: result,
              failure: data['ok'] == false ? result : '',
            ),
          ];
        }
        liveRevision++;
      case 'run.queued':
        final dequeued = text(data['dequeued_queue_id']);
        if (dequeued.isNotEmpty) startQueued(dequeued);
        if (data['queued_messages'] is List) {
          reconcileQueue(data['queued_messages']);
        }
      case 'run.started':
        final qid = text(data['queue_id']);
        if (qid.isNotEmpty) startQueued(qid);
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
        if (content.isNotEmpty &&
            !messages.any(
              (m) =>
                  m.id == text(data['message_id']) ||
                  m.id == 'local:${data['queue_id']}',
            )) {
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
        final idKey = event == 'approval.requested'
            ? 'approval_id'
            : 'clarify_id';
        if (interaction?[idKey] == data[idKey]) return false;
        interaction = {...data, 'kind': event};
        interactionSubmitting = false;
        interactionError = null;
        final remaining = integer(data['remaining_timeout_ms']);
        final timeout = integer(data['timeout_ms']);
        final requested = integer(data['requested_at']);
        interactionDeadline = data.containsKey('remaining_timeout_ms')
            ? DateTime.now().add(Duration(milliseconds: remaining))
            : timeout > 0
            ? (requested > 0
                      ? DateTime.fromMillisecondsSinceEpoch(requested)
                      : DateTime.now())
                  .add(Duration(milliseconds: timeout))
            : null;
        activity = interactionExpired ? '审批已过期，请同步会话' : '等待你的确认';
      case 'approval.resolved':
      case 'clarify.resolved':
        final idKey = event.startsWith('approval')
            ? 'approval_id'
            : 'clarify_id';
        if (interaction?[idKey] != data[idKey]) return false;
        interactionSubmitting = false;
        if (data['resolved'] == false && data['stale'] != true) {
          interactionError = text(data['error']).isEmpty
              ? '服务器未应用此操作，请重试或同步会话'
              : text(data['error']);
          activity = '等待你的确认';
        } else {
          interaction = null;
          interactionDeadline = null;
          interactionError = null;
          activity = data['stale'] == true ? '审批已失效' : '';
        }
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

  /// Rebuild atomically: persisted tool-step assistant rows may already contain
  /// text present in the event log, even when the final raw row is a tool.
  void resume(Map<String, dynamic> data) {
    final previous = messages;
    final previousRun = runId;
    final finished = Set<String>.of(_finishedRuns);
    final unresolved = previous
        .where((m) => m.delivery == 'uncertain')
        .toList();
    final events = asList(data['events']).map(asMap).toList();
    final start = events.lastIndexWhere((e) => e['event'] == 'run.started');
    final currentEvents = events.skip(start < 0 ? 0 : start).toList();
    final marker =
        currentEvents
            .map((e) => text(asMap(e['data'])['run_id']))
            .where((id) => id.isNotEmpty)
            .lastOrNull ??
        '';
    final snapshot = asList(
      data['messages'],
    ).map((m) => ChatMessage.fromJson(asMap(m))).toList();
    clear();
    messages = previous;
    replace(snapshot, keepOlder: flag(data['hasMoreBefore']));
    working = flag(data['isWorking']);
    reconcileQueue(data['queueMessages']);
    if (working) {
      final lastUser = messages.lastIndexWhere(
        (m) => m.role == 'user' || m.role == 'command',
      );
      final candidates = messages.indexed
          .where((entry) {
            final m = entry.$2;
            if (m.role != 'assistant' || entry.$1 <= lastUser) return false;
            if (marker.isNotEmpty && m.runMarker.isNotEmpty) {
              return m.runMarker == marker;
            }
            return m.hasFinishReason && m.finishReason == null;
          })
          .map((e) => e.$1)
          .toList();
      // Missing metadata: accept only a snapshot tail that is demonstrably a
      // prefix of this run's replay; never deduplicate arbitrary conversation text.
      final replayText = currentEvents
          .where((e) => e['event'] == 'message.delta')
          .map((e) => messageText(asMap(e['data'])['delta']))
          .join();
      if (candidates.isEmpty && messages.isNotEmpty && lastUser >= 0) {
        final tail = messages.last;
        if (tail.role == 'assistant' &&
            tail.runMarker.isEmpty &&
            !tail.hasFinishReason &&
            tail.content.isNotEmpty &&
            replayText.startsWith(tail.content)) {
          candidates.add(messages.length - 1);
        }
      }
      final stored = candidates.map((i) => messages[i]).toList();
      final identity = previous
          .where(
            (m) =>
                m.role == 'assistant' &&
                m.pending &&
                (marker.isNotEmpty &&
                    (m.runMarker == marker || previousRun == marker)),
          )
          .firstOrNull;
      final insertion = candidates.isEmpty ? messages.length : candidates.first;
      messages = messages.indexed
          .where((e) => !candidates.contains(e.$1))
          .map((e) => e.$2)
          .toList();
      // Replay into its own reducer: a persisted prefix must never be used as
      // the initial accumulator for the same prefix's deltas.
      final replay = ChatTimeline();
      for (final entry in currentEvents) {
        final event = text(entry['event']);
        if (event == 'run.peer_user_message' || event == 'run.queued') continue;
        replay.apply(event, asMap(entry['data']));
      }
      runId = marker.isEmpty
          ? (stored.lastOrNull?.runMarker.isNotEmpty == true
                ? stored.last.runMarker
                : null)
          : marker;
      final live = replay.messages.where((m) => m.role == 'assistant').toList();
      if (stored.isNotEmpty || live.isNotEmpty || identity != null) {
        final replayBody = live.map((m) => m.content).join();
        final replayReasoning = live.map((m) => m.reasoning).join();
        String reconcile(List<String> parts, String replayValue) {
          final compact = parts.join();
          final spaced = parts.where((s) => s.isNotEmpty).join('\n\n');
          if (compact.isEmpty) return replayValue;
          if (replayValue.isEmpty) return spaced;
          if (replayValue.startsWith(compact) ||
              replayValue.startsWith(spaced)) {
            return replayValue;
          }
          if (compact.startsWith(replayValue) ||
              spaced.startsWith(replayValue)) {
            return spaced;
          }
          // Partial replay starts after persisted steps: preserve both, in order.
          return '$spaced\n\n$replayValue';
        }

        var body = reconcile(stored.map((m) => m.content).toList(), replayBody);
        var reasoning = reconcile(
          stored.map((m) => m.reasoning).toList(),
          replayReasoning,
        );
        // An older snapshot must not roll back already-rendered bytes of this run.
        if (identity != null && identity.content.startsWith(body)) {
          body = identity.content;
        }
        if (identity != null && identity.reasoning.startsWith(reasoning)) {
          reasoning = identity.reasoning;
        }
        final base = stored.firstOrNull ?? live.firstOrNull ?? identity!;
        final merged = base.copyWith(
          content: body,
          reasoning: reasoning,
          pending: true,
          runMarker: runId ?? '',
          localKey: identity?.renderKey ?? base.renderKey,
          tools: {
            for (final m in [...stored, ...live])
              for (final t in m.tools) t.id: t,
          }.values.toList(),
          attachments: {
            for (final m in stored)
              for (final f in m.attachments) f.path: f,
          }.values.toList(),
        );
        messages = [
          ...messages.take(insertion),
          merged,
          ...messages.skip(insertion),
        ];
      }
      interaction = replay.interaction;
      interactionDeadline = replay.interactionDeadline;
      interactionError = replay.interactionError;
      activity = replay.activity;
      if (activity.isEmpty) activity = '正在继续生成';
    } else {
      _finishedRuns.addAll(finished);
    }
    for (final m in unresolved) {
      if (!messages.any(
        (n) =>
            n.renderKey == m.renderKey ||
            (n.role == m.role && n.content == m.content),
      )) {
        messages = [
          ...messages,
          m.copyWith(delivery: 'uncertain', pending: false),
        ];
      }
    }
  }
}
