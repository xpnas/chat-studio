import 'package:flutter/foundation.dart';
import '../data/models.dart';
import '../data/protocol_capabilities.dart';
import '../data/session_tasks.dart';
import '../data/studio_api.dart';

/// User-authorized goals. Never calls the agent's context-bound tool endpoints.
class SessionTasksController extends ChangeNotifier {
  SessionTasksController(this.api, {this.sessionId})
    : _token = api.token,
      _profile = api.profile;
  final StudioApi api;
  final String? sessionId;
  final String _token, _profile;
  String status = '', search = '', order = 'newest';
  bool allProfiles = false, loading = false, hasMore = false;
  String? error, notice;
  List<SessionGoal> tasks = [];
  int total = 0, _offset = 0, _generation = 0;
  bool _disposed = false;
  final pending = <String>{};
  final uncertain = <String>{};
  bool get valid =>
      !_disposed && api.token == _token && api.profile == _profile;
  CapabilityState get capability =>
      api.capabilities[ProtocolCapability.sessionTasks];

  Future<void> filter({
    String? status,
    String? search,
    String? order,
    bool? allProfiles,
  }) async {
    this.status = status ?? this.status;
    this.search = search ?? this.search;
    this.order = order ?? this.order;
    this.allProfiles = allProfiles ?? this.allProfiles;
    tasks = [];
    total = 0;
    hasMore = false;
    _offset = 0;
    await refresh();
  }

  Future<void> refresh({bool more = false}) async {
    if (!valid || more && (loading || !hasMore)) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await api.sessionGoals(
        sessionId: sessionId,
        status: status,
        search: search,
        order: order,
        offset: more ? _offset : 0,
        allProfiles: allProfiles,
      );
      if (!valid || generation != _generation) return;
      final merged = <String, SessionGoal>{
        if (more)
          for (final task in tasks) task.key: task,
      };
      for (final task in page.tasks) {
        merged[task.key] = task;
      }
      tasks = merged.values.toList();
      total = page.total;
      hasMore = page.hasMore;
      _offset = (more ? _offset : 0) + page.tasks.length;
      if (!more) uncertain.clear();
    } catch (e) {
      if (!valid || generation != _generation) return;
      error = e is StaleProtocolResponse ? null : '$e';
      // Permission changes must not leave previously authorized bodies visible.
      if (e is ApiException && (e.status == 401 || e.status == 403)) {
        tasks = [];
        total = 0;
        hasMore = false;
      }
    } finally {
      if (valid && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setStatus(SessionGoal task, String status) async {
    if (!valid ||
        !task.editable ||
        pending.contains(task.key) ||
        uncertain.contains(task.key)) {
      return;
    }
    final generation = _generation;
    pending.add(task.key);
    notice = null;
    notifyListeners();
    try {
      final snapshot = await api.setGoalStatus(task, status);
      if (!valid || generation != _generation) return;
      final replacements = {for (final goal in snapshot.tasks) goal.key: goal};
      tasks = [
        for (final goal in tasks)
          if (goal.sessionId != snapshot.sessionId ||
              goal.profile != task.profile)
            goal
          else if (replacements.containsKey(goal.key))
            replacements[goal.key]!,
      ];
      notifyListeners();
      await refresh();
    } catch (e) {
      if (!valid) return;
      if (e is ApiException && e.status == 409) {
        notice = '任务已变化，请重新选择操作';
        await refresh();
      } else if (e is ApiException && e.status > 0) {
        notice = '$e';
        if (e.status == 403 || e.status == 404) await refresh();
      } else {
        uncertain.add(task.key);
        notice = '操作结果未知，请刷新核对后再操作';
      }
    } finally {
      pending.remove(task.key);
      if (valid) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

enum EvidenceResult { found, missing, forbidden, unsupported, cancelled, limit }

class EvidenceLookup {
  int _generation = 0;
  void cancel() => _generation++;
  Future<(EvidenceResult, ChatMessage?)> locate(
    StudioApi api,
    SessionGoal task,
    int id, {
    int maxPages = 20,
  }) async {
    final generation = ++_generation, profile = api.profile;
    final token = api.token;
    // Uses the authorized resource Profile without mutating the app's identity.
    final reader = _readPage;
    var offset = 0;
    try {
      for (var page = 0; page < maxPages; page++) {
        final data = await reader(api, task, offset);
        if (generation != _generation ||
            token != api.token ||
            profile != api.profile) {
          return (EvidenceResult.cancelled, null);
        }
        final messages = asList(
          data['messages'],
        ).map((row) => ChatMessage.fromJson(asMap(row))).toList();
        final match = messages
            .where((message) => message.id == '$id')
            .firstOrNull;
        if (match != null) {
          return match.visible
              ? (EvidenceResult.found, match)
              : (EvidenceResult.unsupported, null);
        }
        if (data['hasMore'] != true || messages.isEmpty) {
          return (EvidenceResult.missing, null);
        }
        offset += messages.length;
      }
      return (EvidenceResult.limit, null);
    } on ApiException catch (e) {
      return (
        e.status == 403 || e.status == 401
            ? EvidenceResult.forbidden
            : e.status == 404
            ? EvidenceResult.missing
            : EvidenceResult.unsupported,
        null,
      );
    }
  }

  Future<Map<String, dynamic>> _readPage(
    StudioApi api,
    SessionGoal task,
    int offset,
  ) => api.request(
    '/api/studio/sessions/conversations/${Uri.encodeComponent(task.sessionId)}/messages/paginated',
    query: {'profile': task.profile, 'offset': '$offset', 'limit': '60'},
  );
}
