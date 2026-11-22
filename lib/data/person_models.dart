import 'dart:convert';
import 'models.dart';

const personProjection = 'person-display-v1';
bool isPersonMain(String id) => id.startsWith('person-main-');
bool isPersonWorker(String id) => id.startsWith('person-task-');

/// BOT model resources are identified by Profile, provider and model together.
/// Keep only display/selection data from the authorized server catalog.
class PersonModelChoice extends ModelChoice {
  const PersonModelChoice({
    required this.profile,
    required super.provider,
    required super.id,
    required super.label,
    super.providerLabel = '',
    super.apiMode = '',
    super.reasoningEfforts,
  });
  final String profile;
  @override
  String get key => jsonEncode([profile, provider, id]);
  @override
  String get groupKey => jsonEncode([profile, provider]);
  Map<String, dynamic> toSelection() => {
    'profile': profile,
    'provider': provider,
    'model': id,
    if (apiMode.isNotEmpty) 'apiMode': apiMode,
  };
  static PersonModelChoice? fromSelection(dynamic value) {
    final model = asMap(value);
    final profile = text(model['profile']),
        provider = text(model['provider']),
        id = text(model['model']);
    if (profile.isEmpty || provider.isEmpty || id.isEmpty) return null;
    return PersonModelChoice(
      profile: profile,
      provider: provider,
      id: id,
      label: id,
      providerLabel: '$provider · $profile',
      apiMode: text(model['apiMode']),
    );
  }

  static List<PersonModelChoice> parseCatalog(Map<String, dynamic> data) {
    if (data['groups'] is! List) {
      throw const FormatException('Invalid BOT model catalog');
    }
    return [
      for (final raw in asList(data['groups']))
        if (text(asMap(raw)['profile']).isNotEmpty &&
            text(asMap(raw)['provider']).isNotEmpty)
          for (final model in ModelChoice.parseGroups([raw]))
            PersonModelChoice(
              profile: text(asMap(raw)['profile']),
              provider: model.provider,
              id: model.id,
              label: model.label,
              providerLabel:
                  '${model.providerLabel.isEmpty ? model.provider : model.providerLabel} · ${text(asMap(raw)['profile'])}',
              apiMode: model.apiMode,
              reasoningEfforts: model.reasoningEfforts,
            ),
    ];
  }
}

class PersonDefaults {
  PersonDefaults.fromJson(Map<String, dynamic> data)
    : revision = integer(data['revision']),
      model = PersonModelChoice.fromSelection(
        asMap(data['settings'])['model'],
      ) {
    if (data['revision'] is! int || data['settings'] is! Map) {
      throw const FormatException('Invalid BOT defaults');
    }
  }
  final int revision;
  final PersonModelChoice? model;
}

class PersonConversation {
  PersonConversation.fromJson(Map<String, dynamic> json)
    : id = text(json['id']),
      title = text(json['title']),
      profile = text(json['profile']),
      owner = '${json['studio_user_id'] ?? ''}',
      botType = text(json['bot_type']),
      historyRevision = integer(json['history_revision']);
  final String id, title, profile, owner, botType;
  final int historyRevision;
  bool ownedBy(Object account) => isPersonMain(id) && owner == '$account';
}

class PersonConversationPage {
  const PersonConversationPage(this.sessions, this.nextOffset);
  final List<PersonConversation> sessions;
  final int? nextOffset;
}

class PersonInteraction {
  PersonInteraction.fromJson(Map<String, dynamic> json)
    : id = text(json['id']),
      revision = integer(json['revision']),
      taskId = text(json['task_id']),
      executionId = text(json['execution_id']),
      kind = text(json['kind']),
      state = text(json['state']),
      question = text(json['question']),
      choices = _choices(json['choices_json'] ?? json['choices']);
  final String id, taskId, executionId, kind, state, question;
  final int revision;
  final List<String> choices;
  String get key => 'person-interaction:$id:$revision';
  bool get pending =>
      state == 'pending' && const ['approval', 'question'].contains(kind);
  Map<String, dynamic> get event => {
    'kind': kind == 'approval' ? 'approval.requested' : 'clarify.requested',
    kind == 'approval' ? 'approval_id' : 'clarify_id': key,
    'question': question,
    'description': question,
    'choices': kind == 'approval' ? ['once', 'deny'] : choices,
    'allow_permanent': false,
    'durable': true,
  };
  static List<String> _choices(dynamic value) {
    try {
      return asList(
        value is String ? jsonDecode(value) : value,
      ).whereType<String>().toList();
    } catch (_) {
      return [];
    }
  }
}

class PersonTask {
  PersonTask.fromJson(Map<String, dynamic> json)
    : id = text(json['id']),
      sessionId = text(json['session_id']),
      title = text(json['title']),
      summary = text(json['summary']),
      status = text(json['status']),
      revision = integer(json['revision']),
      requirementsRevision = integer(json['requirements_revision']),
      executionId = text(json['execution_id']),
      executionState = text(json['execution_state']),
      acceptanceState = text(json['acceptance_state']),
      acceptanceReason = text(json['acceptance_reason']),
      pendingCount = integer(json['pending_count']);
  final String id,
      sessionId,
      title,
      summary,
      status,
      executionId,
      executionState,
      acceptanceState,
      acceptanceReason;
  final int revision, requirementsRevision, pendingCount;
  bool get running => const [
    'pending',
    'queued',
    'starting',
    'running',
    'waiting_person',
    'waiting_user',
    'waiting_approval',
    'stopping',
  ].contains(executionState);
  bool get canFollowUp =>
      const ['open', 'completed'].contains(status) &&
      const [
        '',
        'idle',
        'pending',
        'queued',
        'starting',
        'running',
        'waiting_person',
        'waiting_user',
        'waiting_approval',
        'finished',
        'failed',
        'interrupted',
      ].contains(executionState);
}

class PersonExecution {
  PersonExecution.fromJson(Map<String, dynamic> json)
    : id = text(json['id']),
      taskId = text(json['task_id']),
      state = text(json['state']),
      output = text(json['output']),
      error = text(json['error']),
      generation = integer(json['generation']),
      requirementsRevision = integer(json['requirements_revision']);
  final String id, taskId, state, output, error;
  final int generation, requirementsRevision;
}

class PersonSnapshot {
  PersonSnapshot.fromJson(Map<String, dynamic> json)
    : session = PersonConversation.fromJson(asMap(json['session'])),
      settingsRevision = integer(json['revision']),
      historyRevision = integer(json['history_revision']),
      settings = asMap(json['settings']),
      busy = json['busy'] == true,
      backgroundPending = integer(json['active_agent_task_count']),
      tasks = asList(
        json['tasks'],
      ).map((row) => PersonTask.fromJson(asMap(row))).toList(),
      interactions = asList(
        json['interactions'],
      ).map((row) => PersonInteraction.fromJson(asMap(row))).toList(),
      flows = asList(
        json['flows'],
      ).map((row) => PersonFlow.fromJson(asMap(row))).toList();
  PersonSnapshot.updatedSettings(
    PersonSnapshot previous,
    Map<String, dynamic> data,
  ) : session = previous.session,
      settingsRevision = integer(data['revision']),
      historyRevision = previous.historyRevision,
      settings = asMap(data['settings']),
      busy = previous.busy,
      backgroundPending = previous.backgroundPending,
      tasks = previous.tasks,
      interactions = previous.interactions,
      flows = previous.flows {
    if (data['revision'] is! int || data['settings'] is! Map) {
      throw const FormatException('Invalid BOT settings response');
    }
  }
  final PersonConversation session;
  final int settingsRevision, historyRevision, backgroundPending;
  final bool busy;
  final Map<String, dynamic> settings;
  final List<PersonTask> tasks;
  final List<PersonInteraction> interactions;
  final List<PersonFlow> flows;
}

class PersonStage {
  PersonStage.fromJson(this.json)
    : id = text(json['id']),
      sessionId = text(json['session_id']),
      sessionTitle = text(json['session_title']),
      goal = text(json['goal']),
      returnExpectation = text(json['return_expectation']),
      state = text(json['state']),
      group = integer(json['group_position']),
      position = integer(json['position']),
      resultMessageId = json['result_message_id'] is int
          ? json['result_message_id'] as int
          : null,
      deliveryState = text(json['delivery_state']),
      deliveryError = text(json['delivery_error']),
      confirmation = asMap(json['confirmation']);
  final Map<String, dynamic> json, confirmation;
  final String id,
      sessionId,
      sessionTitle,
      goal,
      returnExpectation,
      state,
      deliveryState,
      deliveryError;
  final int group, position;
  final int? resultMessageId;
  bool get confirmed =>
      state == 'completed' && confirmation['decision_pending'] != true;
}

class PersonFlow {
  PersonFlow.fromJson(this.json)
    : id = text(json['id']),
      creatorSessionId = text(json['creator_session_id']),
      title = text(json['title']),
      goal = text(json['goal']),
      state = text(json['state']),
      error = text(json['error']),
      revision = integer(json['revision']),
      roundLimit = integer(json['round_limit']),
      roundNumber = integer(json['round_number']),
      position = integer(json['current_position']),
      stages = asList(
        json['stages'],
      ).map((row) => PersonStage.fromJson(asMap(row))).toList();
  final Map<String, dynamic> json;
  final String id, creatorSessionId, title, goal, state, error;
  final int revision, roundLimit, roundNumber, position;
  final List<PersonStage> stages;
  bool get terminal => const ['completed', 'failed', 'stopped'].contains(state);
  bool get canStop => state == 'active' || state == 'failed';
  bool get stopping => stages.any(
    (s) =>
        asList(
          s.json['tasks'],
        ).any((t) => asMap(t)['execution_state'] == 'stopping') ||
        s.deliveryState == 'cancelling',
  );
  bool get canResume =>
      !stopping &&
      (state == 'stopped' || state == 'failed') &&
      !stages.any(
        (s) =>
            s.state == 'active' &&
            asList(s.json['tasks']).any(
              (t) => const [
                'pending',
                'queued',
                'starting',
                'running',
                'waiting_user',
                'waiting_approval',
                'waiting_person',
              ].contains(asMap(t)['execution_state']),
            ),
      );
}

class PersonTimelineItem {
  PersonTimelineItem.fromJson(Map<String, dynamic> json)
    : id = text(json['id']),
      kind = text(json['kind']),
      cursor = text(json['cursor']),
      timestamp = json['timestamp'] is num ? json['timestamp'] as num : 0;
  final String id, kind, cursor;
  final num timestamp;
  String get key => '$kind:$id';
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'cursor': cursor,
    'timestamp': timestamp,
  };
}

class PersonTimelinePage {
  PersonTimelinePage.fromJson(Map<String, dynamic> json)
    : id = text(json['id']),
      projection = text(json['projection']),
      raw = Map.unmodifiable(json),
      messages = {
        for (final row in asList(json['messages']))
          text(asMap(row)['id'].toString()): ChatMessage.fromJson(asMap(row)),
      },
      cards = {
        for (final row in asList(asMap(json['personFlows'])['cards']))
          text(asMap(row)['id']): PersonFlow.fromJson(asMap(row)),
      },
      flows = asList(
        asMap(json['personFlows'])['flows'],
      ).map((row) => PersonFlow.fromJson(asMap(row))).toList(),
      items = asList(
        asMap(asMap(json['personFlows'])['timeline'])['items'],
      ).map((row) => PersonTimelineItem.fromJson(asMap(row))).toList(),
      updates = asList(
        asMap(json['personFlows'])['card_updates'],
      ).map((row) => PersonTimelineItem.fromJson(asMap(row))).toList(),
      before = text(asMap(asMap(json['personFlows'])['timeline'])['before']),
      hasMore =
          asMap(asMap(json['personFlows'])['timeline'])['has_more'] == true,
      reset = asMap(asMap(json['personFlows'])['timeline'])['reset'] == true,
      historyRevision = integer(
        asMap(asMap(json['personFlows'])['timeline'])['history_revision'],
      ),
      historyClearedAt = integer(
        asMap(json['personFlows'])['history_cleared_at'],
      ) {
    if (projection != personProjection ||
        json['messages'] is! List ||
        asMap(json['personFlows'])['timeline'] is! Map ||
        items.any(
          (i) => !const ['message', 'flow'].contains(i.kind) || i.id.isEmpty,
        ) ||
        items.map((i) => i.key).toSet().length != items.length) {
      throw const FormatException('Unsupported BOT timeline projection');
    }
    for (final item in items) {
      if (item.kind == 'message' && !messages.containsKey(item.id) ||
          item.kind == 'flow' && !cards.containsKey(item.id)) {
        throw const FormatException('Incomplete BOT timeline page');
      }
    }
  }
  final String id, projection, before;
  final bool hasMore, reset;
  final int historyRevision, historyClearedAt;
  final Map<String, dynamic> raw;
  final Map<String, ChatMessage> messages;
  final Map<String, PersonFlow> cards;
  final List<PersonFlow> flows;
  final List<PersonTimelineItem> items, updates;
}

class PersonFlowMessagesPage {
  PersonFlowMessagesPage.fromJson(Map<String, dynamic> json)
    : flow = PersonFlow.fromJson(asMap(json['flow'])),
      messages = asList(json['messages']).map(asMap).toList(),
      historyKey = text(json['history_key']),
      hasMore = json['has_more'] == true,
      nextBeforeId = json['next_before_id'] is int
          ? json['next_before_id'] as int
          : null;
  final PersonFlow flow;
  final List<Map<String, dynamic>> messages;
  final String historyKey;
  final bool hasMore;
  final int? nextBeforeId;
}
