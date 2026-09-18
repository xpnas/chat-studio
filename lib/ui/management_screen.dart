import '../l10n.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/compression_settings.dart';
import '../data/studio_api.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/agent_avatar.dart';
import 'widgets/settings_editors.dart';

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen>
    with SingleTickerProviderStateMixin {
  StudioApi? get _api => widget.controller.api;
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _agents = const {};
  Map<String, dynamic> _agentPolicies = const {};
  Map<String, dynamic> _modelCatalog = const {};
  Map<String, dynamic> _auxiliary = const {};
  Map<String, dynamic> _delegation = const {};
  Map<String, dynamic> _combination = const {};
  Map<String, dynamic> _stt = const {};
  Map<String, dynamic> _tts = const {};
  Map<String, dynamic> _config = const {};
  String? _configError;
  Map<String, dynamic> _runtimeAgents = const {};
  String? _runtimeError;
  String? _agentsError;
  Map<String, dynamic> _usage = const {};
  Map<String, dynamic> _skillsUsage = const {};
  List<Map<String, dynamic>> _logFiles = const [];
  List<Map<String, dynamic>> _logs = const [];
  Map<String, dynamic> _performance = const {};
  String _selectedLog = '';
  bool _refreshingCache = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final api = _api;
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait<Object?>([
      _attempt(() => api.codingAgents()),
      _attempt(() => api.codingAgentUpdatePolicies()),
      _attempt(() => api.models()),
      _attempt(() => api.auxiliaryModels()),
      _attempt(() => api.delegationModel()),
      _attempt(() => api.combinationModels()),
      _attempt(() => api.sttSettings()),
      _attempt(() => api.ttsSettings()),
      _attempt(() => api.fetchConfig()),
      _attempt(() => api.usageStats()),
      _attempt(() => api.skillUsageStats()),
      _attempt(() => api.logFiles()),
      _attempt(() => api.performanceRuntime()),
      _attempt(() => api.agentAvailability()),
    ]);
    if (!mounted) return;
    setState(() {
      _agents = _mapResult(results[0]);
      _agentPolicies = _mapResult(results[1]);
      _modelCatalog = _mapResult(results[2]);
      _auxiliary = _mapResult(results[3]);
      _delegation = _mapResult(results[4]);
      _combination = _mapResult(results[5]);
      _stt = _mapResult(results[6]);
      _tts = _mapResult(results[7]);
      _config = _mapResult(results[8]);
      _configError = results[8] is Map<String, dynamic>
          ? null
          : _friendlyError(results[8]!);
      _agentsError = results[0] is Map<String, dynamic>
          ? null
          : _friendlyError(results[0]!);
      _runtimeAgents = _mapResult(results[13]);
      _runtimeError =
          results[13] is Map<String, dynamic> &&
              _runtimeAgents['agents'] is List
          ? null
          : context.tr("无法读取运行时状态，请刷新重试");
      _usage = _mapResult(results[9]);
      _skillsUsage = _mapResult(results[10]);
      _logFiles = _listResult(results[11]);
      _performance = _mapResult(results[12]);
      final availableLogNames = _logFiles
          .map((file) => text(file['name']))
          .where((name) => name.isNotEmpty)
          .toSet();
      _selectedLog = availableLogNames.contains(_selectedLog)
          ? _selectedLog
          : (availableLogNames.isEmpty ? '' : availableLogNames.first);
      _loading = false;
      final failures = results.whereType<ApiException>().toList();
      _error = failures.length == results.length && failures.isNotEmpty
          ? failures.first.message
          : null;
    });
    if (_selectedLog.isNotEmpty) unawaited(_loadLogs());
  }

  Future<Object?> _attempt(Future<Object?> Function() action) async {
    try {
      return await action();
    } catch (error) {
      return error;
    }
  }

  Map<String, dynamic> _mapResult(Object? value) =>
      value is Map<String, dynamic> ? value : const {};

  List<Map<String, dynamic>> _listResult(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : const [];

  String _friendlyError(Object error) => error is ApiException
      ? error.message
      : error.toString().replaceFirst('Exception: ', '');

  void _message(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _run(String success, Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
      _message(success);
      await _loadAll();
    } catch (error) {
      _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>> get _agentRows {
    final tools = asList(_agents['tools']);
    return tools
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) => !['hermes', 'ekko-agent'].contains(text(row['id'])))
        .toList();
  }

  List<Map<String, dynamic>> get _modelGroups {
    final groups = asList(_modelCatalog['groups']);
    return groups
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.tr("服务管理")),
      actions: [
        IconButton(
          tooltip: context.tr("刷新全部数据"),
          onPressed: _loading ? null : _loadAll,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabs: [
          Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Agent'),
          Tab(icon: Icon(Icons.hub_outlined), text: context.tr("模型")),
          Tab(icon: Icon(Icons.monitor_heart_outlined), text: context.tr("诊断")),
          Tab(icon: Icon(Icons.tune_rounded), text: context.tr("设置")),
        ],
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_error != null)
                ErrorNotice(
                  message: _error!,
                  onDismiss: () => setState(() => _error = null),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _agentsPage(),
                    _modelsPage(),
                    _diagnosticsPage(),
                    _settingsPage(),
                  ],
                ),
              ),
            ],
          ),
  );

  Widget _page(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
    children: children,
  );

  Widget _section(
    String title,
    String subtitle,
    List<Widget> children,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        // Keep floating labels and popup anchors outside the section surface
        // from being cut off by the rounded card boundary.
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.none,
          child: Column(children: children),
        ),
      ],
    ),
  );

  Widget _agentsPage() => _page([
    _section(context.tr("运行时"), context.tr("运行时状态与 Coding Agent 安装目录来自不同接口。"), [
      if (_runtimeError != null) ...[_EmptyRow(label: _runtimeError!)],
      if (_runtimeError == null)
        ...asList(_runtimeAgents['agents'])
            .map(asMap)
            .where((row) => ['hermes', 'ekko-agent'].contains(text(row['id'])))
            .map(
              (row) => ListTile(
                leading: AgentAvatar(
                  controller: widget.controller,
                  agentId: text(row['id']),
                  size: 38,
                ),
                title: Text(
                  row['id'] == 'hermes' ? 'Hermes Runtime' : 'Ekko Agent',
                ),
                subtitle: Text(
                  context.l10n.format('{0} · {1}', {
                    '0': row['installed'] is! bool
                        ? context.tr('状态未知')
                        : row['installed'] == true &&
                              row['source'] != 'not-installed'
                        ? context.tr('已安装')
                        : context.tr('未安装或不可用'),
                    '1': row['id'] == 'hermes'
                        ? context.tr(
                            '独立 Python 运行时，安装与修复请使用 Studio Web 端 Runtime 管理',
                          )
                        : context.tr('服务端内置，随 Studio 更新'),
                  }),
                ),
              ),
            ),
    ]),
    _section(
      context.tr("Coding Agent 管理"),
      context.tr("以下 CLI 的安装、更新和配置均在服务端执行；不包含 Hermes Runtime。"),
      [
        if (_agentsError != null) _EmptyRow(label: _agentsError!),
        if (_agentRows.isEmpty)
          _EmptyRow(label: context.tr("服务端未返回 Agent 管理数据")),
        for (final agent in _agentRows) _agentTile(agent),
      ],
    ),
    _section(
      context.tr("移动端边界"),
      context.tr("手机端只管理服务端运行环境，不会在手机上安装 CLI 或执行 Agent。"),
      [
        ListTile(
          leading: Icon(Icons.info_outline_rounded),
          title: Text(context.tr("配置文件与 MCP")),
          subtitle: Text(
            context.tr("配置文件使用全屏编辑；Hermes Runtime 与 CLI 使用不同的管理接口。"),
          ),
        ),
      ],
    ),
  ]);

  Widget _agentTile(Map<String, dynamic> agent) {
    final id = text(agent['id']);
    final installed = flag(agent['installed']);
    final name = switch (id) {
      'claude-code' => 'Claude Code',
      'codex' => 'Codex',
      'opencode' => 'OpenCode',
      'grok' => 'Grok',
      'pi' => 'Pi',
      'hermes' => 'Hermes',
      _ => id.isEmpty ? context.tr("未知 Agent") : id,
    };
    return ListTile(
      leading: AgentAvatar(
        controller: widget.controller,
        agentId: id,
        size: 38,
      ),
      title: Text(name),
      subtitle: Text(
        installed
            ? '${text(agent['version']).isEmpty ? context.tr("已安装") : text(agent['version'])} · ${text(agent['source'])}'
            : context.tr("未安装"),
      ),
      trailing: PopupMenuButton<String>(
        tooltip: context.tr("Agent 操作"),
        onSelected: (action) => _agentAction(id, action),
        itemBuilder: (_) => [
          if (!installed)
            PopupMenuItem(value: 'install', child: Text(context.tr("安装"))),
          if (installed)
            PopupMenuItem(value: 'update', child: Text(context.tr("检查更新"))),
          if (installed && id != 'hermes')
            PopupMenuItem(value: 'delete', child: Text(context.tr("删除"))),
          if (installed && id != 'hermes')
            PopupMenuItem(value: 'config', child: Text(context.tr("编辑配置"))),
          if (installed && id != 'hermes')
            PopupMenuItem(
              value: 'toggle-auto-update',
              child: Text(
                flag(asMap(asMap(_agentPolicies['agents'])[id])['autoUpdate'])
                    ? context.tr("关闭自动更新")
                    : context.tr("开启自动更新"),
              ),
            ),
          if (installed && id != 'hermes')
            PopupMenuItem(value: 'mcp', child: Text(context.tr("管理 MCP 服务"))),
        ],
      ),
    );
  }

  Future<void> _agentAction(String id, String action) async {
    final api = _api;
    if (api == null) return;
    if (action == 'config') {
      await _showAgentConfig(id);
      return;
    }
    if (action == 'toggle-auto-update') {
      final current = flag(
        asMap(asMap(_agentPolicies['agents'])[id])['autoUpdate'],
      );
      await _run(
        current ? context.tr("自动更新已关闭") : context.tr("自动更新已开启"),
        () => api.setCodingAgentAutoUpdate(id, !current),
      );
      return;
    }
    if (action == 'mcp') {
      await _showMcpManager(id);
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr("删除 Agent？")),
          content: Text(
            context.l10n.format("将从服务端移除 {0}，已存在的历史对话不会删除。", {'0': id}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr("取消")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr("删除")),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _run(context.tr("Agent 已删除"), () async {
        await api.deleteCodingAgent(id);
      });
      return;
    }
    await _run(
      action == 'install' ? context.tr("Agent 安装请求已完成") : context.tr("已完成更新检查"),
      () async {
        if (action == 'install') {
          await api.installCodingAgent(id);
        } else {
          await api.checkCodingAgentUpdate(id);
        }
      },
    );
  }

  Future<void> _showAgentConfig(String id) async {
    final api = _api;
    if (api == null) return;
    final key = switch (id) {
      'claude-code' || 'opencode' => 'settings',
      'codex' || 'pi' => 'config',
      _ => 'settings',
    };
    final data = await _try(() => api.codingAgentConfig(id, key));
    if (!mounted || data == null) return;
    final content = await showSettingsTextEditor(
      context: context,
      title: context.l10n.format("{0} 配置", {'0': id}),
      label: text(data['path']).isEmpty ? key : text(data['path']),
      initialValue: text(data['content']),
    );
    if (!mounted || content == null) return;
    await _run(context.tr("Agent 配置已保存"), () async {
      await api.saveCodingAgentConfig(id, key, content);
    });
  }

  Future<void> _showMcpManager(String id) async {
    final api = _api;
    if (api == null) return;
    Map<String, dynamic> data = const {};
    try {
      data = await api.codingAgentMcpServers(id);
    } catch (error) {
      _message(_friendlyError(error), error: true);
      return;
    }
    if (!mounted) return;
    final servers = asList(
      data['servers'],
    ).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    final selected = await showSettingsSheet<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => SettingsSheet(
          title: Text(context.l10n.format("{0} MCP 服务", {'0': id})),
          content: SizedBox(
            width: 620,
            child: servers.isEmpty
                ? _EmptyRow(label: context.tr("暂无 MCP 服务"))
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: servers
                          .map(
                            (server) => ListTile(
                              dense: true,
                              leading: Icon(
                                flag(server['connected'])
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                              ),
                              title: Text(text(server['name'])),
                              subtitle: Text(
                                context.l10n.format("{0} · {1}/{2} 个工具", {
                                  '0': text(server['transport']),
                                  '1': integer(server['tools_registered']),
                                  '2': integer(server['tools']),
                                }),
                              ),
                              trailing: Wrap(
                                spacing: 0,
                                children: [
                                  IconButton(
                                    tooltip: context.tr("测试"),
                                    icon: const Icon(
                                      Icons.network_check_outlined,
                                    ),
                                    onPressed: () async {
                                      try {
                                        final result = await api
                                            .testCodingAgentMcpServer(
                                              id,
                                              text(server['name']),
                                            );
                                        _message(
                                          flag(result['ok'])
                                              ? context.tr("MCP 测试成功")
                                              : text(result['error']).isEmpty
                                              ? context.tr("MCP 测试失败")
                                              : text(result['error']),
                                          error: !flag(result['ok']),
                                        );
                                      } catch (error) {
                                        _message(
                                          _friendlyError(error),
                                          error: true,
                                        );
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: context.tr("删除"),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(
                                        context,
                                        'delete:${text(server['name'])}',
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr("关闭")),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'add'),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr("添加")),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (selected == 'add') {
      await _showMcpEditor(id);
    } else if (selected case final action? when action.startsWith('delete:')) {
      final name = action.substring('delete:'.length);
      await _run(
        context.tr("MCP 服务已删除"),
        () => api.deleteCodingAgentMcpServer(id, name),
      );
    }
  }

  Future<void> _showMcpEditor(String id) async {
    final api = _api;
    if (api == null) return;
    final name = TextEditingController();
    var config = '{\n  "command": ""\n}';
    String? error;
    final result = await showSettingsSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SettingsSheet(
          title: Text(context.tr("添加 MCP 服务")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: context.tr("服务名称"),
                  errorText: error,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr("编辑 MCP JSON 配置")),
                subtitle: Text(
                  config,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.fullscreen_rounded),
                onTap: () async {
                  final value = await showSettingsTextEditor(
                    context: context,
                    title: context.tr("MCP 配置"),
                    label: context.tr("JSON 配置"),
                    initialValue: config,
                    validator: validateJsonObject,
                  );
                  if (context.mounted && value != null) {
                    update(() => config = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr("取消")),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) {
                  update(() => error = context.tr("请输入服务名称"));
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(context.tr("保存")),
            ),
          ],
        ),
      ),
    );
    if (mounted && result == true) {
      await _run(
        context.tr("MCP 服务已添加"),
        () => api.addCodingAgentMcpServer(
          id,
          name.text.trim(),
          Map<String, dynamic>.from(jsonDecode(config) as Map),
        ),
      );
    }
    name.dispose();
  }

  Widget _modelsPage() => _page([
    _section(context.tr("通用模型"), context.tr("按 Provider 分组展示，当前默认模型会固定在顶部。"), [
      ListTile(
        leading: const Icon(Icons.cached_rounded),
        title: Text(context.tr("刷新模型缓存")),
        subtitle: Text(context.tr("重新读取已配置 Provider 的模型目录")),
        trailing: IconButton(
          tooltip: context.tr("刷新模型缓存"),
          onPressed: _refreshingCache ? null : _refreshModelCache,
          icon: _refreshingCache
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ),
      for (final group in _modelGroups) _modelGroupTile(group),
      ListTile(
        leading: const Icon(Icons.add_link_rounded),
        title: Text(context.tr("添加 Provider")),
        subtitle: Text(context.tr("OpenAI 兼容、Anthropic 等接口由服务端保存凭据")),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _showProviderDialog,
      ),
    ]),
    _section(context.tr("辅助模型"), context.tr("视觉、压缩、标题生成、委派等后台任务使用的模型。"), [
      _jsonSummary(_auxiliary['auxiliary'], empty: context.tr("暂无辅助模型配置")),
      ListTile(
        leading: const Icon(Icons.edit_outlined),
        title: Text(context.tr("编辑辅助模型配置")),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showJsonEditor(
          context.tr("辅助模型"),
          _auxiliary['auxiliary'],
          (value) => _run(
            context.tr("辅助模型已保存"),
            () async => _api!.saveAuxiliaryModels(value),
          ),
        ),
      ),
    ]),
    _section(context.tr("组合模型 / MoA"), context.tr("多个参考模型协作后由聚合模型输出结果。"), [
      _jsonSummary(_combination['moa'], empty: context.tr("暂无组合模型配置")),
      ListTile(
        leading: const Icon(Icons.account_tree_outlined),
        title: Text(context.tr("编辑组合模型")),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showJsonEditor(
          context.tr("组合模型"),
          _combination['moa'],
          (value) => _run(
            context.tr("组合模型已保存"),
            () async => _api!.saveCombinationModels(value),
          ),
        ),
      ),
    ]),
    _section(context.tr("委派模型"), context.tr("需要把任务交给其他 Agent 时使用的服务端模型。"), [
      _jsonSummary(_delegation['delegation'], empty: context.tr("暂无委派模型配置")),
      ListTile(
        leading: const Icon(Icons.alt_route_rounded),
        title: Text(context.tr("编辑委派模型")),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showJsonEditor(
          context.tr("委派模型"),
          _delegation['delegation'],
          (value) => _run(
            context.tr("委派模型已保存"),
            () async => _api!.saveDelegationModel(value),
          ),
        ),
      ),
    ]),
    _voiceSection(context.tr("STT 语音识别"), _stt, 'stt'),
    _voiceSection(context.tr("TTS 语音合成"), _tts, 'tts'),
  ]);

  Widget _modelGroupTile(Map<String, dynamic> group) {
    final models = asList(group['models']).whereType<String>().toList();
    final provider = text(group['provider']);
    final defaultModel = text(_modelCatalog['default']);
    final defaultProvider = text(_modelCatalog['default_provider']);
    final isDefault =
        provider == defaultProvider && models.contains(defaultModel);
    return ExpansionTile(
      leading: Icon(
        isDefault ? Icons.star_rounded : Icons.hub_outlined,
        color: isDefault ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(
        text(group['label']).isEmpty ? provider : text(group['label']),
      ),
      subtitle: Text(
        context.l10n.format("{0} · {1} 个模型{2}", {
          '0': provider,
          '1': models.length,
          '2': isDefault ? context.tr(" · 当前默认") : '',
        }),
      ),
      children: [
        if (text(group['provider_key']).isNotEmpty || provider.isNotEmpty)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            leading: const Icon(Icons.edit_outlined, size: 18),
            title: Text(context.tr("编辑 Provider")),
            onTap: () => _showProviderEditor(group),
          ),
        if (flag(group['model_refreshable']))
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            leading: const Icon(Icons.sync_rounded, size: 18),
            title: Text(context.tr("刷新此 Provider 模型")),
            onTap: () => _refreshProvider(group),
          ),
        for (final model in models.take(80))
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            title: Text(model, style: const TextStyle(fontSize: 13)),
            trailing: model == defaultModel && provider == defaultProvider
                ? const Icon(Icons.check_circle_rounded, size: 18)
                : null,
            onTap: () => _setDefaultModel(model, provider),
          ),
        if (models.length > 80)
          Padding(
            padding: const EdgeInsets.fromLTRB(72, 4, 16, 12),
            child: Text(
              context.l10n.format("还有 {0} 个模型，请在 Web 端精细管理。", {
                '0': models.length - 80,
              }),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if (flag(group['provider_editable']) || provider.startsWith('custom:'))
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            leading: const Icon(Icons.delete_outline_rounded, size: 18),
            title: Text(context.tr("删除此 Provider")),
            onTap: () => _removeProvider(
              provider,
              text(group['provider_source']),
              text(group['provider_key']),
            ),
          ),
      ],
    );
  }

  Future<void> _setDefaultModel(String model, String provider) async {
    final api = _api;
    if (api == null) return;
    await _run(
      context.tr("默认模型已更新"),
      () => api.setDefaultModel(model, provider),
    );
  }

  Future<void> _refreshModelCache() async {
    final api = _api;
    if (api == null) return;
    setState(() => _refreshingCache = true);
    try {
      await api.refreshModelCache();
      _message(context.tr("模型缓存刷新完成"));
      await _loadAll();
    } catch (error) {
      _message(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _refreshingCache = false);
    }
  }

  Future<void> _refreshProvider(Map<String, dynamic> group) async {
    final api = _api;
    final poolKey = text(group['provider']);
    if (api == null || poolKey.isEmpty) return;
    try {
      final result = await api.refreshProviderModels(poolKey);
      if (!mounted) return;
      if (flag(result['requires_confirmation'])) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.tr("确认更新模型目录")),
            content: Text(
              text(result['message']).isEmpty
                  ? context.tr("部分旧模型将从当前 Provider 列表中移除，是否继续？")
                  : text(result['message']),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr("取消")),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.tr("继续更新")),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        await api.refreshProviderModels(poolKey, confirm: true);
      }
      _message(context.tr("Provider 模型目录已更新"));
      await _loadAll();
    } catch (error) {
      _message(_friendlyError(error), error: true);
    }
  }

  Future<void> _showProviderEditor(Map<String, dynamic> group) async {
    final api = _api;
    final poolKey = text(group['provider']);
    if (api == null || poolKey.isEmpty) return;
    final detail = await _try(() async {
      final response = await api.providerEditor(poolKey);
      return asMap(response['provider']).isEmpty
          ? response
          : asMap(response['provider']);
    });
    if (!mounted || detail == null || detail.isEmpty) return;
    final label = TextEditingController(text: text(detail['label']));
    final baseUrl = TextEditingController(text: text(detail['base_url']));
    final model = TextEditingController(text: text(detail['preferred_model']));
    final key = TextEditingController();
    var mode = text(detail['api_mode']).isEmpty
        ? 'chat_completions'
        : text(detail['api_mode']);
    final revision = text(detail['revision']);
    final editable = flag(detail['editable']);
    final result = await showSettingsSheet<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => SettingsSheet(
          title: Text(
            text(detail['label']).isEmpty ? poolKey : text(detail['label']),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  enabled: editable,
                  decoration: InputDecoration(labelText: context.tr("显示名称")),
                ),
                TextField(
                  controller: baseUrl,
                  enabled: editable,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                TextField(
                  controller: model,
                  enabled: editable,
                  decoration: InputDecoration(labelText: context.tr("首选模型")),
                ),
                TextField(
                  controller: key,
                  enabled: editable,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: flag(detail['credential_configured'])
                        ? context.tr("替换 API Key（留空保持不变）")
                        : 'API Key',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: mode,
                  decoration: InputDecoration(labelText: context.tr("接口模式")),
                  items: const [
                    DropdownMenuItem(
                      value: 'chat_completions',
                      child: Text('Chat Completions'),
                    ),
                    DropdownMenuItem(
                      value: 'codex_responses',
                      child: Text('Responses'),
                    ),
                    DropdownMenuItem(
                      value: 'anthropic_messages',
                      child: Text('Anthropic Messages'),
                    ),
                    DropdownMenuItem(
                      value: 'bedrock_converse',
                      child: Text('Bedrock Converse'),
                    ),
                    DropdownMenuItem(
                      value: 'codex_app_server',
                      child: Text('Codex App Server'),
                    ),
                  ],
                  onChanged: editable
                      ? (value) => setDialogState(() => mode = value ?? mode)
                      : null,
                ),
                if (flag(detail['credential_configured']))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: editable
                          ? () => setDialogState(() => key.text = '__CLEAR__')
                          : null,
                      icon: const Icon(Icons.key_off_outlined, size: 18),
                      label: Text(context.tr("清除已保存的 API Key")),
                    ),
                  ),
                if (!editable)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        context.tr("此 Provider 由服务端环境变量管理，不能在此修改。"),
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr("取消")),
            ),
            if (editable)
              OutlinedButton(
                onPressed: () async {
                  try {
                    final response = await api.testProviderEditor(poolKey, {
                      'label': label.text.trim(),
                      'base_url': baseUrl.text.trim(),
                      'preferred_model': model.text.trim(),
                      'api_mode': mode,
                      if (key.text.trim().isNotEmpty && key.text != '__CLEAR__')
                        'api_key': key.text,
                    });
                    if (!context.mounted) return;
                    _message(
                      flag(response['success'])
                          ? context.tr("Provider 连接测试成功")
                          : text(response['error']).isEmpty
                          ? context.tr("Provider 连接测试失败")
                          : text(response['error']),
                      error: !flag(response['success']),
                    );
                  } catch (error) {
                    _message(_friendlyError(error), error: true);
                  }
                },
                child: Text(context.tr("测试连接")),
              ),
            FilledButton(
              onPressed: editable ? () => Navigator.pop(context, 'save') : null,
              child: Text(context.tr("保存")),
            ),
          ],
        ),
      ),
    );
    if (result == 'save') {
      final values = <String, dynamic>{
        'label': label.text.trim(),
        'base_url': baseUrl.text.trim(),
        'preferred_model': model.text.trim(),
        'api_mode': mode,
        if (key.text == '__CLEAR__')
          'credential_action': 'clear'
        else if (key.text.trim().isNotEmpty) ...{
          'credential_action': 'replace',
          'api_key': key.text,
        },
      };
      await _run(context.tr("Provider 已保存"), () async {
        await api.patchProviderEditor(poolKey, revision, values);
      });
    }
    label.dispose();
    baseUrl.dispose();
    model.dispose();
    key.dispose();
  }

  Future<void> _removeProvider(
    String provider,
    String source,
    String providerKey,
  ) async {
    final api = _api;
    if (api == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr("删除 Provider？")),
        content: Text(
          context.l10n.format("删除 {0} 后，服务端会切换到其他可用 Provider（如有）。", {
            '0': provider,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr("取消")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr("删除")),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run(
      context.tr("Provider 已删除"),
      () => api.removeProvider(
        provider,
        source: source.isEmpty ? null : source,
        providerKey: providerKey.isEmpty ? null : providerKey,
      ),
    );
  }

  Future<void> _showProviderDialog() async {
    final name = TextEditingController();
    final url = TextEditingController();
    final key = TextEditingController();
    final model = TextEditingController();
    var mode = 'chat_completions';
    final save = await showSettingsSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => SettingsSheet(
          title: Text(context.tr("添加 Provider")),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: context.tr("名称")),
                ),
                TextField(
                  controller: url,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                TextField(
                  controller: key,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API Key'),
                ),
                TextField(
                  controller: model,
                  decoration: InputDecoration(labelText: context.tr("默认模型")),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: mode,
                  decoration: InputDecoration(labelText: context.tr("接口模式")),
                  items: const [
                    DropdownMenuItem(
                      value: 'chat_completions',
                      child: Text('Chat Completions'),
                    ),
                    DropdownMenuItem(
                      value: 'codex_responses',
                      child: Text('Responses'),
                    ),
                    DropdownMenuItem(
                      value: 'anthropic_messages',
                      child: Text('Anthropic Messages'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => mode = value ?? mode),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr("取消")),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty ||
                    url.text.trim().isEmpty ||
                    model.text.trim().isEmpty) {
                  _message(context.tr("名称、Base URL 和默认模型不能为空"), error: true);
                  return;
                }
                if (key.text.trim().isEmpty) {
                  _message(
                    context.tr("请输入 API Key；无需密钥的 Provider 请在服务端 Web 端添加"),
                    error: true,
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: Text(context.tr("保存")),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final api = _api;
      if (api != null) {
        await _run(
          context.tr("Provider 已添加"),
          () => api.addProvider(
            name: name.text.trim(),
            baseUrl: url.text.trim(),
            apiKey: key.text,
            model: model.text.trim(),
            apiMode: mode,
          ),
        );
      }
    }
    name.dispose();
    url.dispose();
    key.dispose();
    model.dispose();
  }

  Widget _voiceSection(String title, Map<String, dynamic> data, String kind) {
    final rawProviders = data['providers'] ?? data['settings'];
    final providers = asList(
      rawProviders,
    ).whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
    final active = text(data['activeProvider']);
    return _section(title, context.tr("配置由服务端保存，移动端不保存 API Key。"), [
      ListTile(
        leading: Icon(
          kind == 'stt' ? Icons.mic_none_rounded : Icons.volume_up_outlined,
        ),
        title: Text(active.isEmpty ? context.tr("未启用") : active),
        subtitle: Text(
          context.l10n.format("{0} 个已保存的 Provider", {'0': providers.length}),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showVoiceDialog(kind, providers, active),
      ),
      ListTile(
        leading: const Icon(Icons.add_circle_outline_rounded),
        title: Text(
          context.l10n.format("添加或编辑{0} Provider", {
            '0': kind == 'stt' ? ' STT' : ' TTS',
          }),
        ),
        subtitle: Text(context.tr("仅提交新的 API Key；已保存密钥不会回显")),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showVoiceProviderEditor(kind, providers),
      ),
    ]);
  }

  Future<void> _showVoiceDialog(
    String kind,
    List<Map<String, dynamic>> providers,
    String active,
  ) async {
    final options = providers
        .map((item) => text(item['provider']))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (options.isEmpty) {
      _message(
        context.l10n.format("当前没有已配置的 {0} Provider，请在 Web 端先添加。", {'0': kind}),
      );
      return;
    }
    var selected = options.contains(active) ? active : options.first;
    final result = await showSettingsSheet<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SettingsSheet(
          title: Text(
            kind == 'stt'
                ? context.tr("选择 STT Provider")
                : context.tr("选择 TTS Provider"),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selected,
                  items: options
                      .map(
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => selected = value ?? selected),
                ),
                const SizedBox(height: 8),
                ...providers.map(
                  (provider) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(text(provider['provider'])),
                    subtitle: Text(
                      _voiceSettingsLabel(asMap(provider['settings'])),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: text(provider['provider']) == 'edge'
                        ? null
                        : IconButton(
                            tooltip: context.tr("删除 Provider"),
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final name = text(provider['provider']);
                              if (name.isEmpty) return;
                              Navigator.pop(context);
                              await _deleteVoiceProvider(kind, name);
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr("取消")),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: Text(context.tr("启用")),
            ),
          ],
        ),
      ),
    );
    if (result != null && _api != null) {
      await _run(
        context.tr("语音 Provider 已切换"),
        () => _api!.setActiveVoiceProvider(kind, result),
      );
    }
  }

  String _voiceSettingsLabel(Map<String, dynamic> settings) {
    final fields = [
      text(settings['model']),
      text(settings['voice']),
      text(settings['language']),
      text(settings['baseUrl']),
    ].where((value) => value.isNotEmpty);
    return fields.isEmpty ? context.tr("使用服务端默认设置") : fields.join(' · ');
  }

  Future<void> _deleteVoiceProvider(String kind, String provider) async {
    final api = _api;
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr("删除语音 Provider？")),
        content: Text(
          context.l10n.format("将删除服务端 {0} 配置和该 Provider 保存的密钥。", {
            '0': provider,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr("取消")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr("删除")),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      context.tr("语音 Provider 已删除"),
      () => api.deleteVoiceProvider(kind, provider),
    );
  }

  Future<void> _showVoiceProviderEditor(
    String kind,
    List<Map<String, dynamic>> providers,
  ) async {
    final choices = kind == 'stt'
        ? const [
            'openai',
            'custom',
            'doubao',
            'groq',
            'mistral',
            'xai',
            'elevenlabs',
            'deepinfra',
            'local',
          ]
        : const [
            'edge',
            'openai',
            'custom',
            'doubao',
            'elevenlabs',
            'gemini',
            'xai',
            'mistral',
            'minimax',
            'deepinfra',
          ];
    String provider = choices.first;
    final baseUrl = TextEditingController();
    final model = TextEditingController();
    final voice = TextEditingController();
    final language = TextEditingController();
    final apiKey = TextEditingController();
    final result = await showSettingsSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final existing = providers
              .where((item) => text(item['provider']) == provider)
              .firstOrNull;
          final settings = asMap(existing?['settings']);
          if (baseUrl.text.isEmpty && model.text.isEmpty && existing != null) {
            baseUrl.text = text(settings['baseUrl']);
            model.text = text(settings['model']);
            voice.text = text(settings['voice']);
            language.text = text(settings['language']);
          }
          return SettingsSheet(
            title: Text(
              kind == 'stt'
                  ? context.tr("配置 STT Provider")
                  : context.tr("配置 TTS Provider"),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: provider,
                    decoration: const InputDecoration(labelText: 'Provider'),
                    items: choices
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        provider = value;
                        final existing = providers
                            .where((item) => text(item['provider']) == provider)
                            .firstOrNull;
                        final settings = asMap(existing?['settings']);
                        baseUrl.text = text(settings['baseUrl']);
                        model.text = text(settings['model']);
                        voice.text = text(settings['voice']);
                        language.text = text(settings['language']);
                        apiKey.clear();
                      });
                    },
                  ),
                  TextField(
                    controller: baseUrl,
                    decoration: InputDecoration(
                      labelText: context.tr("Base URL（可选）"),
                    ),
                  ),
                  TextField(
                    controller: model,
                    decoration: InputDecoration(
                      labelText: context.tr("模型（可选）"),
                    ),
                  ),
                  if (kind == 'tts')
                    TextField(
                      controller: voice,
                      decoration: InputDecoration(
                        labelText: context.tr("音色 / Voice（可选）"),
                      ),
                    ),
                  TextField(
                    controller: language,
                    decoration: InputDecoration(
                      labelText: context.tr("语言（可选）"),
                    ),
                  ),
                  if (provider != 'edge' && provider != 'local')
                    TextField(
                      controller: apiKey,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: existing == null
                            ? 'API Key'
                            : context.tr("替换 API Key（留空保持不变）"),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.tr("取消")),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.tr("保存并启用")),
              ),
            ],
          );
        },
      ),
    );
    if (result == true && _api != null) {
      final settings = <String, dynamic>{
        if (baseUrl.text.trim().isNotEmpty) 'baseUrl': baseUrl.text.trim(),
        if (model.text.trim().isNotEmpty) 'model': model.text.trim(),
        if (voice.text.trim().isNotEmpty && kind == 'tts')
          'voice': voice.text.trim(),
        if (language.text.trim().isNotEmpty) 'language': language.text.trim(),
      };
      await _run(
        context.tr("语音 Provider 已保存并启用"),
        () => _api!.saveVoiceProvider(
          kind,
          provider,
          settings,
          apiKey: apiKey.text,
        ),
      );
    }
    baseUrl.dispose();
    model.dispose();
    voice.dispose();
    language.dispose();
    apiKey.dispose();
  }

  Widget _diagnosticsPage() => _page([
    _section(
      context.tr("用量"),
      context.tr("按当前 Profile 统计最近 30 天的模型、Agent 和 Token 使用情况。"),
      [
        _metricRow(context.tr("会话"), integer(_usage['total_sessions'])),
        _metricRow(
          context.tr("输入 Token"),
          integer(_usage['total_input_tokens']),
        ),
        _metricRow(
          context.tr("输出 Token"),
          integer(_usage['total_output_tokens']),
        ),
        _metricRow(context.tr("估算费用"), _number(_usage['total_cost'])),
      ],
    ),
    _section(context.tr("技能用量"), context.tr("记录 Skill 加载与管理操作，不展开聊天正文。"), [
      _metricRow(
        context.tr("技能动作"),
        integer(asMap(_skillsUsage['summary'])['total_skill_actions']),
      ),
      _metricRow(
        context.tr("加载次数"),
        integer(asMap(_skillsUsage['summary'])['total_skill_loads']),
      ),
      _metricRow(
        context.tr("编辑次数"),
        integer(asMap(_skillsUsage['summary'])['total_skill_edits']),
      ),
      _metricRow(
        context.tr("使用过的技能"),
        integer(asMap(_skillsUsage['summary'])['distinct_skills_used']),
      ),
    ]),
    _section(context.tr("性能监控"), context.tr("需要超级管理员权限；数据来自服务端进程，不是手机性能。"), [
      _metricRow(
        context.tr("系统 CPU"),
        _percent(asMap(_performance['system'])['cpuPercent']),
      ),
      _metricRow(
        context.tr("系统内存"),
        _percent(asMap(_performance['system'])['memoryPercent']),
      ),
      _metricRow(
        context.tr("活动会话"),
        integer(asMap(_performance['sessions'])['active']),
      ),
      _metricRow(
        context.tr("运行会话"),
        integer(asMap(_performance['sessions'])['running']),
      ),
      ListTile(
        leading: const Icon(Icons.refresh_rounded),
        title: Text(context.tr("刷新性能数据")),
        onTap: _loadAll,
      ),
    ]),
    _section(
      context.tr("服务日志"),
      context.tr("按文件查看最近日志，便于定位断网、Agent 和 Provider 问题."),
      [_logSelector(), ..._logs.take(80).map(_logTile)],
    ),
  ]);

  Widget _logSelector() {
    if (_logFiles.isEmpty) {
      return _EmptyRow(label: context.tr("暂无可读日志或权限不足"));
    }
    final items = _logFiles
        .map(
          (file) => DropdownMenuItem<String>(
            value: text(file['name']),
            child: Text(text(file['name'])),
          ),
        )
        .toList();
    // InputDecoration.labelText floats above the field border. The section card
    // clips its children, so leave room for the floating label instead of
    // letting the top half of the label be clipped by the card boundary.
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: items.any((item) => item.value == _selectedLog)
            ? _selectedLog
            : null,
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.description_outlined),
          labelText: context.tr("日志文件"),
        ),
        items: items,
        onChanged: (value) {
          if (value == null) return;
          setState(() => _selectedLog = value);
          unawaited(_loadLogs());
        },
      ),
    );
  }

  Widget _logTile(Map<String, dynamic> row) => ListTile(
    dense: true,
    leading: Text(
      text(row['level']),
      style: TextStyle(
        fontSize: 10,
        color: _levelColor(context, text(row['level'])),
      ),
    ),
    title: Text(
      text(row['message']).isEmpty ? text(row['raw']) : text(row['message']),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12),
    ),
    subtitle: Text(
      text(row['timestamp']),
      style: const TextStyle(fontSize: 10),
    ),
  );

  Future<void> _loadLogs() async {
    final api = _api;
    if (api == null || _selectedLog.isEmpty) return;
    try {
      final rows = await api.logs(_selectedLog);
      if (mounted) setState(() => _logs = rows);
    } catch (error) {
      _message(_friendlyError(error), error: true);
    }
  }

  Widget _settingsPage() => _page([
    _section(
      context.tr("显示与聊天"),
      context.tr("与 Web 端 Profile 配置同步，保存后由服务端生效。"),
      [
        _switchRow(
          context.tr("流式输出"),
          'display',
          'streaming',
          flag(asMap(_config['display'])['streaming']),
        ),
        _switchRow(
          context.tr("显示思考过程"),
          'display',
          'show_reasoning',
          flag(asMap(_config['display'])['show_reasoning']),
        ),
        _switchRow(
          context.tr("显示费用"),
          'display',
          'show_cost',
          flag(asMap(_config['display'])['show_cost']),
        ),
        _switchRow(
          context.tr("启用记忆"),
          'memory',
          'memory_enabled',
          flag(asMap(_config['memory'])['memory_enabled']),
        ),
        _switchRow(
          context.tr("隐私脱敏"),
          'privacy',
          'redact_pii',
          flag(asMap(_config['privacy'])['redact_pii']),
        ),
      ],
    ),
    if (_configError != null)
      ErrorNotice(
        message: context.l10n.format("服务配置读取失败：{0}", {'0': _configError}),
        onDismiss: _loadAll,
      ),
    _section(
      context.tr("运行参数"),
      context.tr("当前 Profile 的配置策略，不代表当前会话已经发生压缩。"),
      [
        ListTile(
          leading: const Icon(Icons.speed_outlined),
          title: Text(context.tr("最大运行步数")),
          subtitle: Text(
            context.l10n.format("{0} 步", {
              '0': integer(asMap(_config['agent'])['max_turns']),
            }),
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: _saving || _configError != null
              ? null
              : () => _showNumberConfig(
                  'agent',
                  'max_turns',
                  integer(asMap(_config['agent'])['max_turns']),
                ),
        ),
        ListTile(
          key: const Key('compression-settings'),
          leading: const Icon(Icons.compress_outlined),
          title: Text(context.tr("上下文自动压缩")),
          subtitle: Text(
            _configError != null
                ? context.tr("状态未知 · 配置读取失败")
                : _compressionSummary(CompressionSettings.fromConfig(_config)),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _saving || _configError != null
              ? null
              : _showCompressionSettings,
        ),
      ],
    ),
    _section(
      context.tr("高级服务配置"),
      context.tr("完整配置仍由服务端保存；此处可编辑移动端未单独展开的字段。"),
      [
        ListTile(
          leading: const Icon(Icons.data_object_rounded),
          title: Text(context.tr("编辑完整服务配置")),
          subtitle: Text(context.tr("显示、记忆、隐私、代理和平台配置等")),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: _saving || _configError != null
              ? null
              : () => _showJsonEditor(
                  context.tr("完整服务配置"),
                  _config,
                  _saveFullConfig,
                ),
        ),
      ],
    ),
    _section(context.tr("权限说明"), context.tr("以下能力由服务端角色控制。移动端不会绕过权限。"), [
      ListTile(
        leading: Icon(Icons.admin_panel_settings_outlined),
        title: Text(context.tr("管理员")),
        subtitle: Text(context.tr("可写 Provider、模型和 Profile 配置，具体以服务端鉴权结果为准。")),
      ),
      ListTile(
        leading: Icon(Icons.security_outlined),
        title: Text(context.tr("超级管理员")),
        subtitle: Text(context.tr("可查看服务性能与系统级诊断。")),
      ),
    ]),
  ]);

  Widget _switchRow(String title, String section, String key, bool value) =>
      SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: _saving || _configError != null
            ? null
            : (next) => _run(
                context.l10n.format("{0}已更新", {'0': title}),
                () => _api!.updateConfigSection(section, {key: next}),
              ),
      );

  Future<void> _saveFullConfig(Map<String, dynamic> value) async {
    final api = _api;
    if (api == null) return;
    await _run(context.tr("完整服务配置已保存"), () async {
      for (final entry in value.entries) {
        if (entry.value is Map) {
          await api.updateConfigSection(
            entry.key,
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    });
  }

  String _compressionSummary(CompressionSettings settings) {
    final enabled = context.tr(settings.enabled ? '已启用' : '已关闭');
    final defaultText = settings.defaultEnabled ? context.tr('（服务端默认）') : '';
    return context.l10n.format('{0}{1} · 阈值 {2}%', {
      '0': enabled,
      '1': defaultText,
      '2': settings.percent,
    });
  }

  Future<void> _showCompressionSettings() async {
    final api = _api;
    if (api == null) return;
    final values = await showSettingsSheet<Map<String, dynamic>>(
      context: context,
      builder: (_) => CompressionSettingsSheet(
        settings: CompressionSettings.fromConfig(_config),
      ),
    );
    if (!mounted || values == null) return;
    await _run(
      context.tr("上下文压缩策略已保存"),
      () => api.updateConfigSection('compression', values),
    );
  }

  Future<void> _showNumberConfig(
    String section,
    String key,
    int initial,
  ) async {
    final api = _api;
    if (api == null) return;
    final input = TextEditingController(text: initial > 0 ? '$initial' : '');
    String? error;
    final value = await showSettingsSheet<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SettingsSheet(
          title: Text(context.tr("最大运行步数")),
          content: TextField(
            controller: input,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.tr("步数"),
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr("取消")),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(input.text.trim());
                if (value == null || value <= 0) {
                  update(() => error = context.tr("请输入大于 0 的整数"));
                  return;
                }
                Navigator.pop(context, value);
              },
              child: Text(context.tr("保存")),
            ),
          ],
        ),
      ),
    );
    input.dispose();
    if (mounted && value != null) {
      await _run(
        context.tr("配置已保存"),
        () => api.updateConfigSection(section, {key: value}),
      );
    }
  }

  Future<void> _showJsonEditor(
    String title,
    dynamic value,
    Future<void> Function(Map<String, dynamic>) save,
  ) async {
    final content = await showSettingsTextEditor(
      context: context,
      title: title,
      label: context.tr("JSON 配置"),
      initialValue: _prettyJson(value),
      validator: validateJsonObject,
    );
    if (!mounted || content == null) return;
    await save(Map<String, dynamic>.from(jsonDecode(content) as Map));
  }

  String _prettyJson(dynamic value) {
    if (value is Map) {
      try {
        return const JsonEncoder.withIndent('  ').convert(value);
      } catch (_) {}
    }
    return '{}';
  }

  Widget _jsonSummary(dynamic value, {required String empty}) {
    if (value is! Map || value.isEmpty) return _EmptyRow(label: empty);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Text(
        _prettyJson(value),
        maxLines: 8,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      ),
    );
  }

  Widget _metricRow(String title, Object value) => ListTile(
    dense: true,
    title: Text(title),
    trailing: Text(
      '$value',
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );

  String _percent(dynamic value) =>
      value is num ? '${value.toStringAsFixed(1)}%' : '-';

  String _number(dynamic value) => value is num
      ? value.toStringAsFixed(4)
      : text(value).isEmpty
      ? '-'
      : text(value);

  Color _levelColor(BuildContext context, String value) {
    final colors = Theme.of(context).colorScheme;
    return switch (value.toUpperCase()) {
      'ERROR' || 'FATAL' => colors.error,
      'WARNING' || 'WARN' => Colors.orange,
      _ => colors.onSurfaceVariant,
    };
  }

  Future<Map<String, dynamic>?> _try(
    Future<Map<String, dynamic>> Function() action,
  ) async {
    try {
      return await action();
    } catch (error) {
      _message(_friendlyError(error), error: true);
      return null;
    }
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(18),
    child: Center(
      child: Text(
        label,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
