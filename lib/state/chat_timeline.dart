import '../data/models.dart';
import '../data/queued_message.dart';
import 'resume_text.dart';

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
      case 'message.interim':
        if (data['output'] is! String) return false;
        continue assistantOutput;
      assistantOutput:
      case 'message.delta':
        liveRevision++;
        _acknowledge();
        working = true;
        activity = '';
        // Bridge events carry a cumulative output in addition to the delta.
        // Prefer it: replayed copies must not append the same delta again.
        // Ordinary agent deltas have no output and remain strictly additive.
        _assistant(
          delta: messageText(data['delta']),
          output: data['output'] is String ? data['output'] as String : null,
        );
      case 'thinking.delta':
      case 'reasoning.delta':
        _assistant(reasoning: messageText(data['delta'] ?? data['text']));
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
    // Rebuild from the complete retained event sequence in a fresh reducer.
    // Removing events already seen live loses state (approvals/tools) and turns
    // a full replay into an incomplete text suffix. Reconcile text only AFTER
    // replay, without deduplicating legitimate repeated deltas by their value.
    final currentEvents = events.skip(start < 0 ? 0 : start).toList();
    final eventMarker =
        events
            .map((e) => text(asMap(e['data'])['run_id']))
            .where((id) => id.isNotEmpty)
            .lastOrNull ??
        '';
    final marker = eventMarker.isNotEmpty ? eventMarker : previousRun ?? '';
    final snapshot = asList(
      data['messages'],
    ).map((m) => ChatMessage.fromJson(asMap(m))).toList();
    // A terminal live event may overtake an asynchronous resume response.
    // Never resurrect a run that this client has already observed finishing.
    if (flag(data['isWorking']) &&
        marker.isNotEmpty &&
        finished.contains(marker)) {
      return;
    }
    clear();
    _finishedRuns.addAll(finished);
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
            if (m.role != 'assistant') return false;
            if (marker.isNotEmpty && m.runMarker.isNotEmpty) {
              return m.runMarker == marker;
            }
            return entry.$1 > lastUser &&
                m.hasFinishReason &&
                m.finishReason == null;
          })
          .map((e) => e.$1)
          .toList();
      // A render identity and its cached prefix belong to exactly one run.
      // Neither a global previousRun match nor a nonempty marker on an old
      // message proves that the message belongs to the resumed run.
      final identity = previous
          .where(
            (m) =>
                m.role == 'assistant' &&
                m.pending &&
                marker.isNotEmpty &&
                m.runMarker == marker,
          )
          .lastOrNull;
      // Bridge persistence uses cli_run_*/cli_resume_* whereas socket events
      // use the runtime run_id. Resolve this alias only within the latest user
      // turn, with open tool steps or a matching user marker, and cumulative
      // text as evidence (a flushed interim row can already be marked stop).
      // Never use text equality alone to consume an older completed run.
      String replayText = '';
      var cumulativeOutput = false;
      for (final entry in currentEvents) {
        if (!['message.delta', 'message.interim'].contains(entry['event'])) {
          continue;
        }
        final payload = asMap(entry['data']);
        if (payload['output'] is String) {
          replayText = payload['output'] as String;
          cumulativeOutput = true;
        } else {
          replayText += messageText(payload['delta']);
        }
      }
      if (candidates.isEmpty && messages.isNotEmpty && lastUser >= 0) {
        final tail = messages.last;
        final bridge =
            tail.runMarker.startsWith('cli_run_') ||
            tail.runMarker.startsWith('cli_resume_');
        final group = messages.indexed
            .where(
              (entry) =>
                  entry.$1 > lastUser &&
                  entry.$2.role == 'assistant' &&
                  entry.$2.runMarker == tail.runMarker,
            )
            .toList();
        final compact = group.map((e) => e.$2.content).join();
        final open = group.any(
          (e) =>
              !e.$2.hasFinishReason ||
              e.$2.finishReason == null ||
              e.$2.finishReason == 'tool_calls',
        );
        // Bridge flushes an interim segment with finish_reason=stop even while
        // the run continues. The persisted user shares that bridge marker.
        final sameUserRun =
            tail.runMarker.isNotEmpty &&
            messages[lastUser].runMarker == tail.runMarker;
        bool sharesPrefix(String reference) =>
            compact.isNotEmpty &&
            reference.isNotEmpty &&
            (reference.startsWith(compact) || compact.startsWith(reference));
        final matchingOutput = cumulativeOutput && sharesPrefix(replayText);
        // During a long tool phase the bounded log may contain no text events.
        // A verified local runtime prefix or an exact replayed tool-call ID can
        // still establish the alias, without concatenating a second bubble.
        final matchingLocal =
            identity != null && sharesPrefix(identity.content);
        final replayToolIds = currentEvents
            .where(
              (e) => [
                'tool.started',
                'tool.call',
                'tool.completed',
                'tool.failed',
              ].contains(e['event']),
            )
            .map((e) => text(asMap(e['data'])['tool_call_id']))
            .where((id) => id.isNotEmpty)
            .toSet();
        final matchingTool =
            sameUserRun &&
            group.any(
              (entry) =>
                  entry.$2.tools.any((tool) => replayToolIds.contains(tool.id)),
            );
        if (bridge &&
            (matchingOutput || matchingLocal || matchingTool) &&
            (open || sameUserRun)) {
          candidates.addAll(group.map((e) => e.$1));
        } else if (tail.role == 'assistant' &&
            tail.runMarker.isEmpty &&
            !tail.hasFinishReason &&
            tail.content.isNotEmpty &&
            replayText.startsWith(tail.content)) {
          candidates.add(messages.length - 1);
        }
      }
      final stored = candidates.map((i) => messages[i]).toList();
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
        final completeReplay = start >= 0;
        String reconcile(
          List<String> parts,
          String local,
          String replayValue, {
          bool authoritativeOutput = false,
        }) {
          final compact = parts.join();
          final spaced = parts.where((s) => s.isNotEmpty).join('\n\n');
          // Snapshot and local cache are PREFIX representations, not sequential
          // pieces. Merge them first, before joining the retained event TAIL.
          // Otherwise a short snapshot + nonadjacent tail creates a gap that
          // cannot overlap the longer local prefix and gets appended twice.
          var known = spaced;
          if (compact.isNotEmpty &&
              (local.startsWith(compact) || replayValue.startsWith(compact))) {
            known = compact;
          }
          if (known.isEmpty || local.startsWith(known)) known = local;
          // Conflicting prefixes: prefer the server snapshot, never concatenate.
          return reconcileResumeText(
            known,
            replayValue,
            completeReplay: completeReplay || authoritativeOutput,
          );
        }

        final body = reconcile(
          stored.map((m) => m.content).toList(),
          identity?.content ?? '',
          replayBody,
          authoritativeOutput: cumulativeOutput,
        );
        final reasoning = reconcile(
          stored.map((m) => m.reasoning).toList(),
          identity?.reasoning ?? '',
          replayReasoning,
        );
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
