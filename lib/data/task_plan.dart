/// Structured task plan contract from Studio v1.0.3. Never infer steps from
/// assistant text or tool arguments: only validated, committed snapshots count.
class TaskPlanStep {
  const TaskPlanStep(this.id, this.title, this.status);
  final String id, title, status;
}

class TaskPlan {
  const TaskPlan({
    required this.sessionId,
    required this.runId,
    required this.id,
    required this.revision,
    required this.executionState,
    required this.steps,
    required this.createdAt,
    required this.updatedAt,
    this.explanation = '',
  });
  final String sessionId, runId, id, executionState, explanation;
  final int revision;
  final num createdAt, updatedAt;
  final List<TaskPlanStep> steps;
  String get key => 'task-plan:$sessionId:$id';
  int get completed => steps.where((s) => s.status == 'completed').length;
  bool get isComplete => completed == steps.length;
  bool get isRunning => executionState == 'running' && !isComplete;
  TaskPlanStep? get currentStep => isRunning
      ? steps.where((s) => s.status == 'in_progress').firstOrNull
      : null;
  String get stateLabel => isComplete
      ? '已完成'
      : switch (executionState) {
          'running' => '执行中',
          'interrupted' => '已中断，剩余步骤未完成',
          'failed' => '运行失败，剩余步骤未完成',
          _ => '本次运行已结束，剩余步骤未完成',
        };

  // A terminal socket receipt may precede the final plan snapshot. Preserve
  // server revision and completed steps; never fabricate successful completion.
  TaskPlan stopped(String state) => TaskPlan(
    sessionId: sessionId,
    runId: runId,
    id: id,
    revision: revision,
    executionState: state,
    createdAt: createdAt,
    updatedAt: updatedAt,
    explanation: explanation,
    steps: List.unmodifiable(
      steps.map(
        (s) => s.status == 'in_progress'
            ? TaskPlanStep(s.id, s.title, 'pending')
            : s,
      ),
    ),
  );

  static TaskPlan? parse(dynamic raw) {
    if (raw is! Map) return null;
    for (final key in ['session_id', 'run_id', 'plan_id']) {
      if (raw[key] is! String || (raw[key] as String).trim().isEmpty) {
        return null;
      }
    }
    final revision = raw['revision'];
    if (revision is! num ||
        !revision.isFinite ||
        revision < 1 ||
        revision > 9007199254740991 ||
        revision != revision.truncateToDouble()) {
      return null;
    }
    for (final key in ['created_at', 'updated_at']) {
      if (raw[key] is! num || !(raw[key] as num).isFinite) return null;
    }
    if (![
      'running',
      'ended',
      'interrupted',
      'failed',
    ].contains(raw['execution_state'])) {
      return null;
    }
    if (raw['explanation'] != null &&
        (raw['explanation'] is! String ||
            (raw['explanation'] as String).length > 1000)) {
      return null;
    }
    final rows = raw['plan'];
    if (rows is! List || rows.isEmpty || rows.length > 30) return null;
    final ids = <String>{};
    final steps = <TaskPlanStep>[];
    for (final row in rows) {
      if (row is! Map) return null;
      final id = row['id'], title = row['step'], status = row['status'];
      if (id is! String ||
          id.trim().isEmpty ||
          id.length > 100 ||
          !ids.add(id) ||
          title is! String ||
          title.trim().isEmpty ||
          title.length > 200 ||
          !['pending', 'in_progress', 'completed'].contains(status)) {
        return null;
      }
      steps.add(TaskPlanStep(id, title, status as String));
    }
    return TaskPlan(
      sessionId: raw['session_id'] as String,
      runId: raw['run_id'] as String,
      id: raw['plan_id'] as String,
      revision: revision.toInt(),
      executionState: raw['execution_state'] as String,
      createdAt: raw['created_at'] as num,
      updatedAt: raw['updated_at'] as num,
      explanation: raw['explanation'] as String? ?? '',
      steps: List.unmodifiable(steps),
    );
  }

  static List<TaskPlan> parseList(dynamic raw, {String? sessionId}) =>
      raw is! List
      ? const []
      : raw
            .map(parse)
            .whereType<TaskPlan>()
            .where((p) => sessionId == null || p.sessionId == sessionId)
            .toList();
}
