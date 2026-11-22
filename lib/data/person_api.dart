import 'models.dart';
import 'dart:convert';
import 'person_models.dart';
import 'session_tasks.dart';
import 'studio_api.dart';
import 'protocol_capabilities.dart';

extension PersonApi on StudioApi {
  Future<List<PersonModelChoice>> personModels() async =>
      PersonModelChoice.parseCatalog(
        await request('/api/studio/person/models'),
      );

  Future<Map<String, dynamic>> changePersonModel(
    String id,
    int revision,
    PersonModelChoice model,
  ) {
    if (!isPersonMain(id)) {
      throw ArgumentError('A BOT main conversation is required');
    }
    return request(
      '/api/studio/person/settings',
      method: 'PUT',
      body: {
        'session_id': id,
        'expected_revision': revision,
        'model': model.toSelection(),
      },
    );
  }

  Future<PersonDefaults> personDefaults() async =>
      PersonDefaults.fromJson(await request('/api/studio/person'));

  Future<PersonConversation> createPersonConversation(
    Object account, {
    required String title,
    required int revision,
    PersonModelChoice? model,
    String workspace = '',
  }) async {
    if (title.trim().isEmpty || title.trim().length > 100) {
      throw ArgumentError('Invalid BOT name');
    }
    final result = PersonConversation.fromJson(
      await request(
        '/api/studio/person/conversations',
        method: 'POST',
        body: {
          'title': title.trim(),
          'expected_revision': revision,
          if (model != null) 'model': model.toSelection(),
          if (workspace.trim().isNotEmpty) 'workspace': workspace.trim(),
        },
      ),
    );
    if (!result.ownedBy(account)) {
      throw const ApiException('BOT ownership could not be verified', 403);
    }
    return result;
  }

  Future<PersonConversationPage> personConversations(
    Object account, {
    String search = '',
    int offset = 0,
  }) async {
    final data = await readCapability(
      ProtocolCapability.person,
      '/api/studio/person/conversations',
      query: {'search': search, 'offset': '$offset'},
      isMissingRoute: missingReadRoute,
    );
    return PersonConversationPage(
      asList(data['sessions'])
          .map((row) => PersonConversation.fromJson(asMap(row)))
          .where((session) => session.ownedBy(account))
          .toList(),
      data['next_offset'] is int ? data['next_offset'] as int : null,
    );
  }

  Future<PersonSnapshot> personSnapshot(String id, Object account) async {
    if (!isPersonMain(id)) {
      throw ArgumentError('A BOT main conversation is required');
    }
    final snapshot = PersonSnapshot.fromJson(
      await request('/api/studio/person', query: {'session_id': id}),
    );
    if (snapshot.session.id != id || !snapshot.session.ownedBy(account)) {
      throw const ApiException('BOT ownership could not be verified', 403);
    }
    return snapshot;
  }

  Future<PersonTimelinePage> personTimeline(
    String id, {
    String? before,
  }) async => PersonTimelinePage.fromJson(
    await readCapability(
      ProtocolCapability.timeline,
      '/api/studio/sessions/conversations/${Uri.encodeComponent(id)}/messages/paginated',
      query: {
        'timeline': 'true',
        'limit': '150',
        if (before != null && before.isNotEmpty) 'before': before,
      },
      isMissingRoute: missingReadRoute,
    ),
  );
  Future<List<PersonFlow>> personFlows({
    String? sessionId,
    String? flowId,
  }) async => asList(
    (await request(
      '/api/studio/person/flows/query',
      method: 'POST',
      body: {'session_id': ?sessionId, 'flow_id': ?flowId},
    ))['flows'],
  ).map((row) => PersonFlow.fromJson(asMap(row))).toList();
  Future<PersonFlow> applyPersonFlow(Map<String, dynamic> input) async {
    if (!const ['create', 'stop', 'resume'].contains(input['action'])) {
      throw ArgumentError('Unsupported mobile flow operation');
    }
    return PersonFlow.fromJson(
      await request(
        '/api/studio/person/flows/apply',
        method: 'POST',
        body: input,
      ),
    );
  }

  Future<PersonFlowMessagesPage> personFlowMessages(
    String id, {
    int? before,
  }) async => PersonFlowMessagesPage.fromJson(
    await request(
      '/api/studio/person/flows/${Uri.encodeComponent(id)}/messages',
      query: {'limit': '100', if (before != null) 'before_id': '$before'},
    ),
  );
  Future<Map<String, dynamic>> answerPersonInteraction(
    PersonInteraction interaction,
    String answer,
  ) => request(
    '/api/studio/person/interactions/${Uri.encodeComponent(interaction.id)}/answer',
    method: 'POST',
    body: {'expected_revision': interaction.revision, 'answer': answer},
  );
  Future<Map<String, dynamic>> personTaskChat(
    String id, {
    String? executionId,
  }) => request(
    '/api/studio/person/tasks/${Uri.encodeComponent(id)}/chat',
    query: {'execution_id': ?executionId},
  );
  Future<List<PersonExecution>> personExecutions(String id) async => asList(
    (await request(
      '/api/studio/person/tasks/${Uri.encodeComponent(id)}/executions',
    ))['executions'],
  ).map((row) => PersonExecution.fromJson(asMap(row))).toList();
  Future<List<Map<String, dynamic>>> personExecutionEvents(String id) async =>
      asList(
        (await request(
          '/api/studio/person/executions/${Uri.encodeComponent(id)}/events',
          query: {'after': '0'},
        ))['events'],
      ).map(asMap).toList();
  Future<Map<String, dynamic>> continuePersonTask(
    String id,
    Map<String, dynamic> input,
  ) => request(
    '/api/studio/person/tasks/${Uri.encodeComponent(id)}/chat',
    method: 'POST',
    body: input,
  );
  Future<Map<String, dynamic>> stopPersonTask(Map<String, dynamic> input) =>
      request(
        '/api/studio/person/tasks/apply',
        method: 'POST',
        body: {...input, 'action': 'stop'},
      );
}

class PersonFlowDraft {
  PersonFlowDraft({
    required this.creator,
    required this.title,
    required this.goal,
    required this.stages,
    this.rounds = 1,
  });
  final String creator, title, goal;
  final List<({String sessionId, String goal, String expectation, int group})>
  stages;
  final int rounds;
  String? validate(Set<String> authorized) {
    if (!authorized.contains(creator) ||
        title.trim().isEmpty ||
        title.length > 200 ||
        goal.trim().isEmpty ||
        goal.length > 8000 ||
        stages.isEmpty ||
        stages.length > 13 ||
        rounds < 1 ||
        rounds > 1000) {
      return '请填写目标、1–13 个阶段及 1–1000 轮';
    }
    final groups = <List<String>>[];
    for (final stage in stages) {
      if (!authorized.contains(stage.sessionId) ||
          stage.goal.trim().isEmpty ||
          stage.goal.length > 8000 ||
          stage.expectation.trim().isEmpty ||
          stage.expectation.length > 4000 ||
          stage.group < 0 ||
          stage.group > groups.length) {
        return '阶段必须使用有权访问的 BOT，分组从 0 连续排列';
      }
      if (stage.group == groups.length) groups.add([]);
      if (stage.group != groups.length - 1 ||
          groups[stage.group].contains(stage.sessionId)) {
        return '同一并行组不能重复 BOT，分组必须连续';
      }
      groups[stage.group].add(stage.sessionId);
    }
    var previous = [creator];
    for (final group in groups) {
      if (group.length == 1 &&
          previous.length == 1 &&
          group.single == previous.single) {
        return 'BOT 不能向自身交接';
      }
      previous = group;
    }
    if (rounds > 1 &&
        groups.first.length == 1 &&
        groups.last.length == 1 &&
        groups.first.single == groups.last.single) {
      return '重复轮次的边界不能自交接';
    }
    final payload = toJson('validation');
    if (jsonEncode(payload['stages']).length > 32000) return '协作路线内容过长';
    return null;
  }

  Map<String, dynamic> toJson(String key) => {
    'action': 'create',
    'session_id': creator,
    'title': title.trim(),
    'goal': goal.trim(),
    'rounds': rounds,
    'stages': [
      for (final stage in stages)
        {
          'session_id': stage.sessionId,
          'goal': stage.goal.trim(),
          'return_expectation': stage.expectation.trim(),
          'group': stage.group,
        },
    ],
    'idempotency_key': key,
  };
}
