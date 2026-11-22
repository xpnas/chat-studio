import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/chat_transport.dart';
import '../data/models.dart';
import '../data/person_api.dart';
import '../data/person_models.dart';
import '../data/person_history_cache.dart';
import '../data/session_sync_transport.dart';
import '../data/studio_api.dart';
import '../data/speech_playback.dart';
import 'message_controller.dart';
import 'chat_timeline.dart';
import 'conversation_state.dart';
import 'person_timeline.dart';
import 'person_operations.dart';
import 'session_sync_controller.dart';

class PersonController extends ChangeNotifier implements MessageController {
  PersonController({
    required this.api,
    required this.account,
    required this.sessionId,
    required this.cache,
    required this.identityValid,
    SpeechPlayback? speech,
    ChatTransport? transport,
    SessionSyncTransport? observer,
  }) : speech = speech ?? SpeechPlayback(),
       transport = transport ?? SocketChatTransport(),
       sync = SessionSyncController(observer ?? SocketSessionSyncTransport()) {
    operation = PersonOperation(
      persist: (journal) => saveCache(),
      valid: () => valid,
    );
    operation.addListener(changed);
    sync.addListener(changed);
    sync.projection.allowedPersonSessions.add(sessionId);
    sync.onRemoval = (id) {
      if (id == sessionId) unawaited(refreshSnapshot());
    };
  }
  @override
  final StudioApi api;
  @override
  final SpeechPlayback speech;
  @override
  String get profile => api.profile;
  @override
  bool get messageScopeValid => valid;
  @override
  String get messageAgentId => 'ekko-agent';
  @override
  String? get messageSenderName => snapshot?.session.title ?? 'BOT';
  @override
  String audioAttachmentId(MessageAttachment file) =>
      'audio:$account:$sessionId:${file.path}';
  @override
  void playAudioAttachment(MessageAttachment file) {
    if (!valid || !foreground || !file.isAudio) return;
    final id = audioAttachmentId(file);
    if (speech.activeId == id) {
      unawaited(speech.stop());
    } else {
      unawaited(speech.playAttachment(api, id, file));
    }
  }

  @override
  void reconnect() => onForeground();
  final Object account;
  final String sessionId;
  final PersonHistoryCache cache;
  final bool Function() identityValid;
  final ChatTransport transport;
  final SessionSyncController sync;
  final timeline = PersonTimeline(),
      live = ChatTimeline(),
      draft = ConversationDraft();
  late final PersonOperation operation;
  PersonSnapshot? snapshot;
  bool? resourceAllowed;
  bool connected = false,
      syncing = false,
      loadingOlder = false,
      foreground = true;
  bool _disposed = false, _snapshotLoading = false, _retryCacheMiss = false;
  bool _resumeAfterRefresh = false, _staleHistoryRetry = false;
  int _generation = 0,
      _snapshotRequest = 0,
      _historyRequest = 0,
      _historyFloor = -1;
  Timer? _refresh, _resumeTimer, _runTimer;
  String? error;
  final answering = <String>{};
  bool get valid => !_disposed && identityValid();
  bool get working => live.working;
  bool get configurationReady =>
      snapshot?.settings['model'] is Map &&
      asList(snapshot?.settings['agents']).isNotEmpty;
  bool get canSend =>
      valid &&
      !modelSaving &&
      connected &&
      !syncing &&
      !working &&
      configurationReady &&
      resourceAllowed == true &&
      timeline.latest != null;
  bool modelSaving = false;
  String? modelError;
  bool get canChangeModel =>
      valid &&
      foreground &&
      connected &&
      !syncing &&
      !_snapshotLoading &&
      !working &&
      snapshot != null &&
      !snapshot!.busy &&
      !modelSaving &&
      !operation.pending &&
      !operation.uncertain;

  Future<bool> changeModel(PersonModelChoice model) async {
    if (!canChangeModel) return false;
    final revision = snapshot!.settingsRevision;
    modelSaving = true;
    modelError = null;
    // A snapshot started before this write cannot overwrite the saved choice.
    _snapshotRequest++;
    changed();
    try {
      final result = await api.changePersonModel(sessionId, revision, model);
      if (!valid) return false;
      final current = snapshot;
      if (current == null) return false;
      final updated = PersonSnapshot.updatedSettings(current, result);
      if (updated.settingsRevision >= current.settingsRevision) {
        snapshot = updated;
      }
      await refreshSnapshot();
      return valid && snapshot != null;
    } catch (e) {
      if (!valid) return false;
      modelError = e is ApiException && e.status == 409
          ? 'BOT 配置已变化或正在回复，请刷新后重新选择模型'
          : e is ApiException && e.status == 403
          ? '没有权限使用此 BOT 模型，请重新选择'
          : 'BOT 模型保存未确认，请刷新后检查当前模型';
      // Revision conflicts and uncertain writes are reconciled, never replayed.
      await refreshSnapshot();
      return false;
    } finally {
      modelSaving = false;
      changed();
    }
  }

  int get backgroundPending => snapshot?.backgroundPending ?? 0;
  void changed() {
    if (valid) notifyListeners();
  }

  Future<void> initialize() async {
    if (!isPersonMain(sessionId) || !valid) return;
    final generation = ++_generation;
    final saved = await cache.read();
    if (!valid || generation != _generation) return;
    if (saved != null) {
      try {
        timeline.restore(saved);
        operation.restore(asMap(saved['operation']));
      } catch (_) {
        timeline.clear();
      }
    }
    await refreshSnapshot();
    if (!valid || generation != _generation || snapshot == null) return;
    live.sessionId = sessionId;
    transport.connect(api, (event, data) {
      if (valid && generation == _generation) onEvent(event, data);
    });
    sync.connect(api);
    changed();
  }

  Future<void> refreshSnapshot() async {
    if (!valid) return;
    final request = ++_snapshotRequest;
    _snapshotLoading = true;
    try {
      final next = await api.personSnapshot(sessionId, account);
      List<String> permittedProfiles;
      try {
        permittedProfiles = await api.profiles();
      } on ApiException catch (e) {
        // Profile access can be revoked while the account still owns this BOT.
        // Keep its authorized history, but never allow a new run.
        if (e.status != 403) rethrow;
        permittedProfiles = [];
      }
      if (!valid || request != _snapshotRequest) return;
      if (snapshot != null &&
          next.settingsRevision < snapshot!.settingsRevision) {
        return;
      }
      final resource = text(asMap(next.settings['model'])['profile']).isNotEmpty
          ? text(asMap(next.settings['model'])['profile'])
          : next.session.profile.isNotEmpty
          ? next.session.profile
          : api.profile;
      resourceAllowed = permittedProfiles.contains(resource);
      snapshot = next;
      if (next.session.profile.isNotEmpty &&
          api.profile != next.session.profile) {
        api.profile = next.session.profile;
        if (connected) onForeground();
      }
      timeline.mergeFlows(next.flows);
      if (next.historyRevision > _historyFloor) {
        _historyFloor = next.historyRevision;
      }
      if (timeline.latest != null &&
          next.historyRevision > timeline.historyRevision) {
        timeline.clear();
        live.clear();
        _historyRequest++;
        unawaited(saveCache());
        if (connected) requestResume(full: true);
      }
    } catch (e) {
      if (!valid || request != _snapshotRequest) return;
      error = '$e';
      resourceAllowed = null;
      if (e is ApiException &&
          (e.status == 403 || e.status == 404 || e.status == 401)) {
        snapshot = null;
        timeline.clear();
        live.clear();
        transport.dispose();
        sync.disconnect();
        connected = false;
        await cache.clear();
      }
    } finally {
      if (valid && request == _snapshotRequest) {
        _snapshotLoading = false;
        changed();
      }
    }
  }

  Future<void> saveCache() async {
    if (!valid) return;
    final data = timeline.cacheData();
    if (data == null) return;
    try {
      await cache.write({...data, 'operation': operation.journal});
    } catch (_) {
      if (valid) {
        error = 'BOT 缓存保存失败，重连时将重新读取';
        changed();
      }
    }
  }

  void requestResume({bool full = false}) {
    if (!valid || !connected) return;
    syncing = true;
    _resumeTimer?.cancel();
    try {
      transport.emit('app.resume', {
        'session_id': sessionId,
        'id': full ? '' : timeline.latest?.id ?? '',
        'timeline': true,
      });
    } catch (e) {
      error = '$e';
      syncing = false;
      changed();
      return;
    }
    _resumeTimer = Timer(const Duration(seconds: 12), () {
      if (valid && syncing) {
        syncing = false;
        error = 'BOT 投影恢复未确认，请重试连接';
        changed();
      }
    });
    changed();
  }

  Map<String, dynamic> _durable(Map<String, dynamic> data) {
    final value = Map<String, dynamic>.of(data);
    if (value['durable'] == true) {
      value.remove('timeout_ms');
      value.remove('remaining_timeout_ms');
      value.remove('requested_at');
    }
    return value;
  }

  void onEvent(String event, Map<String, dynamic> data) {
    if (!valid) return;
    if (event == 'connected') {
      connected = true;
      _retryCacheMiss = false;
      requestResume();
      return;
    }
    if (event == 'disconnected' || event == 'connection.error') {
      connected = false;
      syncing = false;
      _resumeTimer?.cancel();
      live.markUncertain();
      changed();
      return;
    }
    if (event == 'person.updated') {
      scheduleRefresh();
      return;
    }
    if (text(data['session_id']) != sessionId) return;
    if (event == 'app.resumed') {
      _resumeTimer?.cancel();
      try {
        PersonTimelinePage page;
        if (data['projection'] != personProjection) {
          throw const FormatException('Unsupported BOT projection');
        }
        if (data['messagesCached'] == true) {
          if (timeline.latest == null || timeline.latest!.id != data['id']) {
            if (_retryCacheMiss) {
              throw const FormatException('BOT cache page unavailable');
            }
            _retryCacheMiss = true;
            requestResume(full: true);
            return;
          }
          page = timeline.latest!;
        } else {
          page = PersonTimelinePage.fromJson(data);
          _retryCacheMiss = false;
        }
        if (page.historyRevision < _historyFloor ||
            page.historyRevision < timeline.historyRevision) {
          if (!_staleHistoryRetry) {
            _staleHistoryRetry = true;
            requestResume(full: true);
          } else {
            syncing = false;
            error = 'BOT 历史版本尚未更新，请稍后刷新';
            changed();
          }
          return;
        }
        _staleHistoryRetry = false;
        _historyFloor = page.historyRevision;
        final reset = timeline.applyLatest(page);
        if (reset) {
          _historyRequest++;
          live.clear();
        }
        live.resume({
          ...page.raw,
          ...data,
          'messages': page.raw['messages'],
          'events': [
            for (final raw in asList(data['events']))
              {...asMap(raw), 'data': _durable(asMap(asMap(raw)['data']))},
          ],
        });
        syncing = false;
        error = null;
        _runTimer?.cancel();
        unawaited(saveCache());
        scheduleRefresh(resume: false);
        changed();
      } catch (e) {
        if (data['projection'] != personProjection) {
          timeline.clear();
          live.clear();
          unawaited(cache.clear());
        }
        syncing = false;
        error = '$e';
        changed();
      }
      return;
    }
    if (event == 'timeline.reset') {
      timeline.clear();
      live.clear();
      _historyRequest++;
      requestResume(full: true);
      return;
    }
    if (event == 'run.failed' && syncing && text(data['run_id']).isEmpty) {
      syncing = false;
      error = text(data['error']);
      changed();
      return;
    }
    // Only projected content and explicit interactions enter the main history.
    if (!const [
      'run.started',
      'run.completed',
      'run.failed',
      'run.queued',
      'run.dequeued',
      'message.delta',
      'message.interim',
      'abort.completed',
      'approval.requested',
      'approval.resolved',
      'clarify.requested',
      'clarify.resolved',
      'run.peer_user_message',
    ].contains(event)) {
      return;
    }
    live.apply(event, _durable(data));
    if (timeline.readingOlder &&
        (event.startsWith('message.') || event == 'run.peer_user_message')) {
      timeline.hasNewer = true;
    }
    if (const [
      'run.started',
      'message.delta',
      'run.completed',
      'run.failed',
      'abort.completed',
    ].contains(event)) {
      _runTimer?.cancel();
    }
    if (const [
      'run.completed',
      'run.failed',
      'abort.completed',
      'approval.resolved',
      'clarify.resolved',
    ].contains(event)) {
      scheduleRefresh();
    }
    changed();
  }

  void scheduleRefresh({bool resume = true}) {
    if (!valid) return;
    _resumeAfterRefresh = _resumeAfterRefresh || resume;
    if (_refresh?.isActive == true) return;
    _refresh = Timer(const Duration(milliseconds: 180), () async {
      if (!valid) return;
      if (!_snapshotLoading) await refreshSnapshot();
      final needsResume = _resumeAfterRefresh;
      _resumeAfterRefresh = false;
      if (valid && needsResume && connected && !syncing) requestResume();
    });
  }

  Future<void> loadOlder() async {
    if (!valid ||
        loadingOlder ||
        !timeline.hasMore ||
        timeline.before.isEmpty) {
      return;
    }
    final generation = timeline.generation,
        request = ++_historyRequest,
        cursor = timeline.before;
    loadingOlder = true;
    timeline.beginReading();
    changed();
    try {
      final page = await api.personTimeline(sessionId, before: cursor);
      if (!valid ||
          request != _historyRequest ||
          generation != timeline.generation) {
        return;
      }
      if (page.reset || page.historyRevision != timeline.historyRevision) {
        timeline.clear();
        live.clear();
        _historyRequest++;
        requestResume(full: true);
        return;
      }
      timeline.prepend(page, generation);
      await saveCache();
    } catch (e) {
      if (valid && request == _historyRequest) error = '$e';
    } finally {
      if (valid) {
        loadingOlder = false;
        changed();
      }
    }
  }

  void showLatest() {
    timeline.showLatest();
    requestResume();
  }

  bool send(String input, {List<Map<String, dynamic>> attachments = const []}) {
    if (!canSend || (input.trim().isEmpty && attachments.isEmpty)) return false;
    final queue = const Uuid().v4();
    try {
      transport.emit('run', {
        'session_id': sessionId,
        'queue_id': queue,
        'input': attachments.isEmpty
            ? input.trim()
            : [
                if (input.trim().isNotEmpty)
                  {'type': 'text', 'text': input.trim()},
                ...attachments,
              ],
      });
      live.begin(
        input.trim(),
        'local:$queue',
        attachments: MessageAttachment.parse(attachments),
      );
      draft.text = '';
      draft.files.clear();
      draft.uploaded.clear();
      _runTimer?.cancel();
      _runTimer = Timer(const Duration(seconds: 25), () {
        if (valid) {
          live.markUncertain();
          requestResume();
        }
      });
      changed();
      return true;
    } catch (e) {
      error = '$e';
      changed();
      return false;
    }
  }

  void stop() {
    if (!valid || !connected || !working) return;
    transport.emit('abort', {'session_id': sessionId});
  }

  List<PersonInteraction> get interactions =>
      snapshot?.interactions
          .where(
            (i) =>
                i.pending &&
                (snapshot!.tasks.any((t) => t.id == i.taskId) ||
                    i.taskId.isEmpty),
          )
          .toList() ??
      [];
  String get liveInteractionKey => text(
    live.interaction?[live.interaction?['kind'] == 'approval.requested'
        ? 'approval_id'
        : 'clarify_id'],
  );
  Future<void> answer(PersonInteraction interaction, String answer) async {
    if (!valid || !interaction.pending || !answering.add(interaction.key)) {
      return;
    }
    changed();
    try {
      await api.answerPersonInteraction(interaction, answer);
      if (!valid) return;
      if (liveInteractionKey == interaction.key) {
        live.interaction = null;
      }
      await refreshSnapshot();
      requestResume();
    } catch (e) {
      if (valid) {
        error = '$e';
        await refreshSnapshot();
        requestResume();
      }
    } finally {
      answering.remove(interaction.key);
      changed();
    }
  }

  Future<void> answerLive(String answer) async {
    final pending = live.interaction;
    if (pending == null || live.interactionSubmitting) return;
    final match = RegExp(
      r'^person-interaction:(.+):(\d+)$',
    ).firstMatch(liveInteractionKey);
    if (match != null) {
      await this.answer(
        PersonInteraction.fromJson({
          'id': match[1],
          'revision': int.parse(match[2]!),
          'state': 'pending',
          'kind': pending['kind'] == 'approval.requested'
              ? 'approval'
              : 'question',
        }),
        answer,
      );
      return;
    }
    if (!connected || !live.canApprove(answer)) return;
    final approval = pending['kind'] == 'approval.requested';
    live.interactionSubmitting = true;
    changed();
    try {
      transport.emit(approval ? 'approval.respond' : 'clarify.respond', {
        'session_id': sessionId,
        approval ? 'approval_id' : 'clarify_id':
            pending[approval ? 'approval_id' : 'clarify_id'],
        approval ? 'choice' : 'response': answer,
      });
    } catch (e) {
      live.interactionSubmitting = false;
      error = '$e';
      changed();
    }
  }

  Future<bool> confirmVisibleRead({
    required bool latest,
    required bool routeVisible,
    int? visibleMessageId,
  }) async {
    final observed = sync.projection.sessions[sessionId],
        cursor = visibleMessageId;
    final message = cursor == null ? null : timeline.messages['$cursor'];
    if (!valid ||
        !foreground ||
        !routeVisible ||
        !latest ||
        working ||
        syncing ||
        live.interaction != null ||
        interactions.isNotEmpty ||
        cursor == null ||
        message?.role != 'assistant' ||
        message?.visible != true ||
        !timeline.items.any(
          (item) => item.kind == 'message' && item.id == '$cursor',
        ) ||
        observed == null ||
        observed.lastAttentionId > observed.readAttentionId) {
      return false;
    }
    return sync.readVisible(
      id: sessionId,
      messageId: cursor,
      attentionId: observed.readAttentionId,
      foreground: true,
      atLatest: true,
      working: false,
      hasUnseenAttention: false,
    );
  }

  void onBackground() {
    foreground = false;
    unawaited(speech.stop());
    transport.dispose();
    sync.disconnect();
    connected = false;
    syncing = false;
    _resumeTimer?.cancel();
    changed();
  }

  void onForeground() {
    if (!valid) return;
    foreground = true;
    final generation = _generation;
    transport.connect(api, (event, data) {
      if (valid && generation == _generation) onEvent(event, data);
    });
    sync.connect(api);
    unawaited(refreshSnapshot());
  }

  @override
  void dispose() {
    _disposed = true;
    notifyListeners();
    _generation++;
    _historyRequest++;
    _snapshotRequest++;
    _refresh?.cancel();
    _resumeTimer?.cancel();
    _runTimer?.cancel();
    transport.dispose();
    sync.dispose();
    operation.dispose();
    speech.dispose();
    cache.close();
    api.close();
    super.dispose();
  }
}
