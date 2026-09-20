import 'models.dart';
import 'studio_api.dart';

/// Protocol names are intentionally unchanged: these endpoints belong to Studio.
extension AgentSettingsApi on StudioApi {
  Future<Map<String, dynamic>> builtInSettings() => request('/api/ekko/config');
  Future<Map<String, dynamic>> saveBuiltInSettings(
    Map<String, dynamic> config,
  ) => request('/api/ekko/config', method: 'PUT', body: {'config': config});
  Future<Map<String, dynamic>> runtimeVersions({bool remote = false}) =>
      request('/api/hermes/runtime-versions', query: {'remote': '$remote'});
  Future<List<Map<String, dynamic>>> runtimeJobs() async => asList(
    (await request('/api/hermes/runtime-versions/jobs'))['jobs'],
  ).map(asMap).toList();
  Future<Map<String, dynamic>> downloadRuntime(String version, String source) =>
      request(
        '/api/hermes/runtime-versions/runtime/download',
        method: 'POST',
        body: {'version': version, 'source': source},
      );
  Future<Map<String, dynamic>> activateRuntime(String version) => request(
    '/api/hermes/runtime-versions/active-runtime',
    method: 'POST',
    body: {'version': version},
  );
  Future<Map<String, dynamic>> deleteRuntime(String version) => request(
    '/api/hermes/runtime-versions/runtime/${Uri.encodeComponent(version)}',
    method: 'DELETE',
  );
  Future<Map<String, dynamic>> setRuntimeDirectory(String directory) => request(
    '/api/hermes/runtime-versions/runtime-root',
    method: 'POST',
    body: {'directory': directory},
  );
  Future<Map<String, dynamic>> restartRuntimeService() =>
      request('/api/hermes/runtime-versions/restart-webui', method: 'POST');
}

enum AgentSettingKind { number, toggle, choice, lines, languages, profiles }

class AgentSettingField {
  const AgentSettingField(
    this.path,
    this.label, {
    this.kind = AgentSettingKind.number,
    this.min = 1,
    this.max,
    this.nullable = false,
    this.decimal = false,
    this.options = const [],
    this.hint = '',
  });
  final String path, label, hint;
  final AgentSettingKind kind;
  final num min;
  final num? max;
  final bool nullable, decimal;
  final List<String> options;
  Object? read(Map<String, dynamic> config) {
    Object? value = config;
    for (final key in path.split('.')) {
      value = asMap(value)[key];
    }
    return value;
  }

  bool exists(Map<String, dynamic> config) {
    final parts = path.split('.');
    Map<String, dynamic> parent = config;
    for (final key in parts.take(parts.length - 1)) {
      parent = asMap(parent[key]);
    }
    return parent.containsKey(parts.last);
  }

  void write(Map<String, dynamic> config, Object? value) {
    final parts = path.split('.');
    var parent = config;
    for (final key in parts.take(parts.length - 1)) {
      parent[key] ??= <String, dynamic>{};
      parent = parent[key] as Map<String, dynamic>;
    }
    parent[parts.last] = value;
  }

  String? validate(String text) {
    if (text.trim().isEmpty && nullable) return null;
    final n = num.tryParse(text.trim());
    if (n == null ||
        !n.isFinite ||
        n < min ||
        (max != null && n > max!) ||
        (!decimal && n != n.truncateToDouble())) {
      return '请输入有效数值';
    }
    return null;
  }
}

// Mirrors the visible fields in views/ekko/SettingsView.vue, not the deprecated
// failure counter or compression policy that is owned by Studio's main settings.
const builtInSettingsSections = <String, List<AgentSettingField>>{
  '运行': [
    AgentSettingField('runtime.maxSteps', '最大执行步数'),
    AgentSettingField('runtime.maxModelRetries', '模型重试次数', min: 0),
    AgentSettingField('runtime.toolFailureRecoveryThreshold', '工具失败恢复阈值'),
    AgentSettingField(
      'delegation.backgroundEnabled',
      '后台委派',
      kind: AgentSettingKind.toggle,
    ),
    AgentSettingField('delegation.subtaskMaxSteps', '子任务最大步数'),
  ],
  '模型': [
    AgentSettingField('model.requestTimeoutMs', '请求超时（毫秒）'),
    AgentSettingField(
      'model.temperature',
      '温度',
      min: 0,
      nullable: true,
      decimal: true,
      hint: '留空使用模型默认值',
    ),
    AgentSettingField(
      'model.maxTokens',
      '最大输出 tokens',
      nullable: true,
      hint: '留空使用模型默认值',
    ),
    AgentSettingField(
      'model.reasoningEffort',
      '思考深度',
      kind: AgentSettingKind.choice,
      options: ['none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'],
    ),
    AgentSettingField(
      'model.reasoningSummary',
      '思考摘要',
      kind: AgentSettingKind.choice,
      options: ['auto', 'concise', 'detailed'],
    ),
    AgentSettingField(
      'model.authorizationRefreshLeewayMs',
      '授权提前刷新（毫秒）',
      min: 0,
    ),
  ],
  '工具': [
    AgentSettingField('tools.enabled', '启用工具', kind: AgentSettingKind.toggle),
    AgentSettingField('tools.executionTimeoutMs', '工具超时（毫秒）'),
    AgentSettingField(
      'tools.approvals.enabled',
      '工具审批',
      kind: AgentSettingKind.toggle,
      hint: '关闭审批会允许工具无需确认执行',
    ),
    AgentSettingField('tools.approvals.timeoutMs', '审批超时（毫秒）'),
    AgentSettingField(
      'tools.approvals.permanentAllow',
      '永久允许的工具',
      kind: AgentSettingKind.lines,
      hint: '每行一个工具名称；这些工具无需审批',
    ),
    AgentSettingField(
      'tools.codeExec.enabled',
      '代码执行',
      kind: AgentSettingKind.toggle,
    ),
    AgentSettingField(
      'tools.codeExec.languages',
      '执行语言',
      kind: AgentSettingKind.languages,
    ),
    AgentSettingField('tools.codeExec.timeoutMs', '代码执行超时（毫秒）'),
    AgentSettingField('tools.codeExec.maxToolCalls', '代码工具最大调用次数'),
    AgentSettingField('tools.codeExec.maxOutputBytes', '标准输出上限（字节）'),
    AgentSettingField('tools.codeExec.maxStderrBytes', '错误输出上限（字节）'),
    AgentSettingField('tools.codeExec.maxSourceBytes', '代码大小上限（字节）'),
  ],
  '模块': [
    AgentSettingField('memory.enabled', '启用记忆', kind: AgentSettingKind.toggle),
    AgentSettingField('memory.recentMessageLimit', '近期消息数量'),
    AgentSettingField(
      'memory.automaticRecallTokenBudget',
      '自动回忆 token 预算',
      min: 0,
    ),
    AgentSettingField('memory.searchResultLimit', '记忆搜索结果数量'),
    AgentSettingField('skills.enabled', '启用技能', kind: AgentSettingKind.toggle),
    AgentSettingField('skills.reviewEveryToolCalls', '技能复查调用间隔', min: 0),
    AgentSettingField('mcp.enabled', '启用 MCP', kind: AgentSettingKind.toggle),
  ],
  '高级': [
    AgentSettingField('logging.maxBytes', '日志大小上限（字节）'),
    AgentSettingField(
      'prompt.instructions',
      '附加指令',
      kind: AgentSettingKind.lines,
      hint: '每行一条指令',
    ),
  ],
};

// HermesSettingsView.vue: server-backed Agent, memory, session and gateway
// settings. Browser-only recent-session preferences stay in the history UI.
const hermesSettingsSections = <String, List<AgentSettingField>>{
  '运行': [
    AgentSettingField('agent.max_turns', '最大运行步数'),
    AgentSettingField(
      'agent.gateway_timeout',
      '网关超时（秒）',
      min: 0,
      max: 7200,
      hint: '设为 0 表示不限制网关执行时间',
    ),
    AgentSettingField(
      'agent.restart_drain_timeout',
      '重启等待（秒）',
      min: 10,
      max: 300,
    ),
    AgentSettingField(
      'agent.tool_use_enforcement',
      '工具使用策略',
      kind: AgentSettingKind.choice,
      options: ['auto', 'always', 'never'],
    ),
  ],
  '记忆': [
    AgentSettingField(
      'memory.memory_enabled',
      '启用记忆',
      kind: AgentSettingKind.toggle,
    ),
    AgentSettingField(
      'memory.user_profile_enabled',
      '启用用户画像',
      kind: AgentSettingKind.toggle,
    ),
    AgentSettingField(
      'memory.memory_char_limit',
      '记忆字符上限',
      min: 100,
      max: 10000,
    ),
    AgentSettingField(
      'memory.user_char_limit',
      '用户画像字符上限',
      min: 100,
      max: 10000,
    ),
  ],
  '会话': [
    AgentSettingField(
      'approvals.mode',
      '工具审批',
      kind: AgentSettingKind.choice,
      options: ['manual', 'off'],
      hint: '关闭审批会允许工具无需确认执行',
    ),
    AgentSettingField(
      'memory.write_approval',
      '记忆写入审批',
      kind: AgentSettingKind.toggle,
    ),
    AgentSettingField(
      'skills.write_approval',
      '技能写入审批',
      kind: AgentSettingKind.toggle,
    ),
    AgentSettingField(
      'session_reset.mode',
      '会话重置策略',
      kind: AgentSettingKind.choice,
      options: ['both', 'idle', 'daily', 'none'],
    ),
    AgentSettingField(
      'session_reset.idle_minutes',
      '空闲重置（分钟）',
      min: 10,
      max: 10080,
    ),
    AgentSettingField(
      'session_reset.at_hour',
      '每日重置时间（小时）',
      min: 0,
      max: 23,
      hint: '使用服务器时区，0 至 23 时',
    ),
  ],
  '网关': [
    AgentSettingField(
      'gatewayAutoStart.enabled',
      '网关自动启动',
      kind: AgentSettingKind.toggle,
    ),
    AgentSettingField(
      'gatewayAutoStart.management',
      '网关管理方式',
      kind: AgentSettingKind.choice,
      options: ['auto', 'per_profile', 'unified'],
      hint: '仅默认 Profile 可设置全局网关管理方式',
    ),
  ],
};
