import 'models.dart';
import 'protocol_capabilities.dart';
import 'studio_api.dart';

class SessionGoal {
  SessionGoal.fromJson(
    Map<String, dynamic> json, {
    String sessionId = '',
    String profile = 'default',
    String title = '',
  }) : id = text(json['id']),
       title = text(json['title']),
       summary = text(json['summary']),
       status = text(json['status']),
       sessionId = text(json['session_id']).isEmpty
           ? sessionId
           : text(json['session_id']),
       profile = text(json['profile']).isEmpty
           ? profile
           : text(json['profile']),
       sessionTitle = text(json['session_title']).isEmpty
           ? title
           : text(json['session_title']),
       sourceMessageId = json['source_message_id'] is int
           ? json['source_message_id'] as int
           : null,
       evidenceMessageId = json['evidence_message_id'] is int
           ? json['evidence_message_id'] as int
           : null,
       updatedAt = json['updated_at'] is int ? json['updated_at'] as int : null,
       completionEvidence = text(json['completion_evidence']);
  final String id,
      title,
      summary,
      status,
      sessionId,
      profile,
      sessionTitle,
      completionEvidence;
  final int? sourceMessageId, evidenceMessageId, updatedAt;
  String get key => '$profile\u0000$sessionId\u0000$id';
  bool get editable =>
      id.isNotEmpty &&
      sessionId.isNotEmpty &&
      updatedAt != null &&
      const ['open', 'completed', 'closed'].contains(status);
}

class SessionGoalPage {
  const SessionGoalPage(this.tasks, this.total, this.hasMore);
  final List<SessionGoal> tasks;
  final int total;
  final bool hasMore;
}

class SessionGoalSnapshot {
  SessionGoalSnapshot.fromJson(
    Map<String, dynamic> json, {
    String profile = 'default',
    String title = '',
  }) : sessionId = text(json['session_id']),
       revision = integer(json['revision']),
       tasks = asList(json['tasks'])
           .map(
             (row) => SessionGoal.fromJson(
               asMap(row),
               sessionId: text(json['session_id']),
               profile: profile,
               title: title,
             ),
           )
           .toList();
  final String sessionId;
  final int revision;
  final List<SessionGoal> tasks;
}

bool missingReadRoute(Object error) =>
    error is ApiException &&
    (error.status == 501 ||
        error.status == 404 &&
            (error.message == 'Not Found' ||
                error.message.startsWith('Cannot GET ')));

extension SessionTasksApi on StudioApi {
  Future<SessionGoalPage> sessionGoals({
    String? sessionId,
    String? resourceProfile,
    String status = '',
    String search = '',
    String order = 'newest',
    int offset = 0,
    int limit = 50,
    bool allProfiles = false,
  }) async {
    if (!const ['', 'open', 'completed', 'closed'].contains(status) ||
        !const ['newest', 'oldest'].contains(order) ||
        offset < 0 ||
        limit < 1 ||
        limit > 100 ||
        search.length > 200) {
      throw ArgumentError('Invalid task query');
    }
    final data = await readCapability(
      ProtocolCapability.sessionTasks,
      sessionId == null
          ? '/api/studio/session-tasks'
          : '/api/studio/sessions/${Uri.encodeComponent(sessionId)}/tasks',
      query: {
        'profile': allProfiles ? '' : resourceProfile ?? profile,
        if (sessionId == null) ...{
          'search': search,
          if (status.isNotEmpty) 'status': status,
          'order': order,
          'offset': '$offset',
          'limit': '$limit',
        },
      },
      isMissingRoute: missingReadRoute,
    );
    final tasks = asList(data['tasks'])
        .map(
          (row) => SessionGoal.fromJson(
            asMap(row),
            sessionId: sessionId ?? '',
            profile: resourceProfile ?? profile,
          ),
        )
        .where((task) => task.id.isNotEmpty)
        .toList();
    if (sessionId != null) {
      final filtered =
          tasks
              .where(
                (task) =>
                    (status.isEmpty || task.status == status) &&
                    '${task.title} ${task.summary}'.toLowerCase().contains(
                      search.toLowerCase(),
                    ),
              )
              .toList()
            ..sort(
              (a, b) => order == 'newest'
                  ? (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0)
                  : (a.updatedAt ?? 0).compareTo(b.updatedAt ?? 0),
            );
      return SessionGoalPage(
        filtered.skip(offset).take(limit).toList(),
        filtered.length,
        offset + limit < filtered.length,
      );
    }
    return SessionGoalPage(
      tasks,
      integer(data['total']),
      data['has_more'] == true,
    );
  }

  Future<SessionGoalSnapshot> setGoalStatus(
    SessionGoal task,
    String status,
  ) async {
    if (!task.editable ||
        !const ['open', 'completed', 'closed'].contains(status)) {
      throw ArgumentError('Invalid task status');
    }
    return SessionGoalSnapshot.fromJson(
      await request(
        '/api/studio/sessions/${Uri.encodeComponent(task.sessionId)}/tasks/${Uri.encodeComponent(task.id)}/status',
        method: 'PATCH',
        query: {'profile': task.profile},
        body: {'status': status, 'expected_updated_at': task.updatedAt},
      ),
      profile: task.profile,
      title: task.sessionTitle,
    );
  }
}
