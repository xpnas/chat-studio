import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/studio_api.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/agent_avatar.dart';

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
      _usage = _mapResult(results[9]);
      _skillsUsage = _mapResult(results[10]);
      _logFiles = _listResult(results[11]);
      _performance = _mapResult(results[12]);
      _selectedLog = _selectedLog.isNotEmpty
          ? _selectedLog
          : text(_logFiles.firstOrNull?['name']);
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
      title: const Text('服务管理'),
      actions: [
        IconButton(
          tooltip: '刷新全部数据',
          onPressed: _loading ? null : _loadAll,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      bottom: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabs: const [
          Tab(icon: Icon(Icons.smart_toy_outlined), text: 'Agent'),
          Tab(icon: Icon(Icons.hub_outlined), text: '模型'),
          Tab(icon: Icon(Icons.monitor_heart_outlined), text: '诊断'),
          Tab(icon: Icon(Icons.tune_rounded), text: '设置'),
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

  Widget _section(String title, String subtitle, List<Widget> children) =>
      Padding(
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
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(children: children),
            ),
          ],
        ),
      );

  Widget _agentsPage() => _page([
    _section('Agent 管理', '安装状态、版本更新和 Agent 配置均在服务端执行。', [
      if (_agentRows.isEmpty) const _EmptyRow(label: '服务端未返回 Agent 管理数据'),
      for (final agent in _agentRows) _agentTile(agent),
    ]),
    _section('移动端边界', '手机端只管理服务端运行环境，不会在手机上安装 CLI 或执行 Agent。', [
      const ListTile(
        leading: Icon(Icons.info_outline_rounded),
        title: Text('配置文件与 MCP'),
        subtitle: Text('可查看和保存 Agent 的配置文件；大段配置建议在 Web 端编辑。'),
      ),
    ]),
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
      _ => id.isEmpty ? '未知 Agent' : id,
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
            ? '${text(agent['version']).isEmpty ? '已安装' : text(agent['version'])} · ${text(agent['source'])}'
            : '未安装',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Agent 操作',
        onSelected: (action) => _agentAction(id, action),
        itemBuilder: (_) => [
          if (!installed)
            const PopupMenuItem(value: 'install', child: Text('安装')),
          if (installed)
            const PopupMenuItem(value: 'update', child: Text('检查更新')),
          if (installed && id != 'hermes')
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          if (installed && id != 'hermes')
            const PopupMenuItem(value: 'config', child: Text('编辑配置')),
          if (installed && id != 'hermes')
            PopupMenuItem(
              value: 'toggle-auto-update',
              child: Text(
                flag(asMap(_agentPolicies['agents'])[id]['autoUpdate'])
                    ? '关闭自动更新'
                    : '开启自动更新',
              ),
            ),
          if (installed && id != 'hermes')
            const PopupMenuItem(value: 'mcp', child: Text('管理 MCP 服务')),
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
      final current = flag(asMap(_agentPolicies['agents'])[id]['autoUpdate']);
      await _run(
        current ? '自动更新已关闭' : '自动更新已开启',
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
          title: const Text('删除 Agent？'),
          content: Text('将从服务端移除 $id，已存在的历史对话不会删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _run('Agent 已删除', () async {
        await api.deleteCodingAgent(id);
      });
      return;
    }
    await _run(action == 'install' ? 'Agent 安装请求已完成' : '已完成更新检查', () async {
      if (action == 'install') {
        await api.installCodingAgent(id);
      } else {
        await api.checkCodingAgentUpdate(id);
      }
    });
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
    final editor = TextEditingController(text: text(data['content']));
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$id 配置'),
        content: SizedBox(
          width: 650,
          child: TextField(
            controller: editor,
            maxLines: 16,
            minLines: 8,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              labelText: text(data['path']).isEmpty ? key : text(data['path']),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (save == true) {
      await _run('Agent 配置已保存', () async {
        await api.saveCodingAgentConfig(id, key, editor.text);
      });
    }
    editor.dispose();
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
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('$id MCP 服务'),
          content: SizedBox(
            width: 620,
            child: servers.isEmpty
                ? const _EmptyRow(label: '暂无 MCP 服务')
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
                                '${text(server['transport'])} · ${integer(server['tools_registered'])}/${integer(server['tools'])} 个工具',
                              ),
                              trailing: Wrap(
                                spacing: 0,
                                children: [
                                  IconButton(
                                    tooltip: '测试',
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
                                              ? 'MCP 测试成功'
                                              : text(result['error']).isEmpty
                                              ? 'MCP 测试失败'
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
                                    tooltip: '删除',
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
              child: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'add'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (selected == 'add') {
      await _showMcpEditor(id);
    } else if (selected case final action? when action.startsWith('delete:')) {
      final name = action.substring('delete:'.length);
      await _run('MCP 服务已删除', () => api.deleteCodingAgentMcpServer(id, name));
    }
  }

  Future<void> _showMcpEditor(String id) async {
    final name = TextEditingController();
    final config = TextEditingController(text: '{\n  "command": ""\n}');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加 MCP 服务'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '服务名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: config,
                minLines: 8,
                maxLines: 16,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'MCP JSON 配置',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == true && _api != null) {
      try {
        final decoded = jsonDecode(config.text);
        if (decoded is! Map || name.text.trim().isEmpty) {
          throw const FormatException('名称和 JSON 配置不能为空');
        }
        await _run(
          'MCP 服务已添加',
          () => _api!.addCodingAgentMcpServer(
            id,
            name.text.trim(),
            Map<String, dynamic>.from(decoded),
          ),
        );
      } on FormatException catch (error) {
        _message(error.message, error: true);
      }
    }
    name.dispose();
    config.dispose();
  }

  Widget _modelsPage() => _page([
    _section('通用模型', '按 Provider 分组展示，当前默认模型会固定在顶部。', [
      ListTile(
        leading: const Icon(Icons.cached_rounded),
        title: const Text('刷新模型缓存'),
        subtitle: const Text('重新读取已配置 Provider 的模型目录'),
        trailing: IconButton(
          tooltip: '刷新模型缓存',
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
        title: const Text('添加 Provider'),
        subtitle: const Text('OpenAI 兼容、Anthropic 等接口由服务端保存凭据'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _showProviderDialog,
      ),
    ]),
    _section('辅助模型', '视觉、压缩、标题生成、委派等后台任务使用的模型。', [
      _jsonSummary(_auxiliary['auxiliary'], empty: '暂无辅助模型配置'),
      ListTile(
        leading: const Icon(Icons.edit_outlined),
        title: const Text('编辑辅助模型配置'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showJsonEditor(
          '辅助模型',
          _auxiliary['auxiliary'],
          (value) =>
              _run('辅助模型已保存', () async => _api!.saveAuxiliaryModels(value)),
        ),
      ),
    ]),
    _section('组合模型 / MoA', '多个参考模型协作后由聚合模型输出结果。', [
      _jsonSummary(_combination['moa'], empty: '暂无组合模型配置'),
      ListTile(
        leading: const Icon(Icons.account_tree_outlined),
        title: const Text('编辑组合模型'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showJsonEditor(
          '组合模型',
          _combination['moa'],
          (value) =>
              _run('组合模型已保存', () async => _api!.saveCombinationModels(value)),
        ),
      ),
    ]),
    _section('委派模型', '需要把任务交给其他 Agent 时使用的服务端模型。', [
      _jsonSummary(_delegation['delegation'], empty: '暂无委派模型配置'),
      ListTile(
        leading: const Icon(Icons.alt_route_rounded),
        title: const Text('编辑委派模型'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showJsonEditor(
          '委派模型',
          _delegation['delegation'],
          (value) =>
              _run('委派模型已保存', () async => _api!.saveDelegationModel(value)),
        ),
      ),
    ]),
    _voiceSection('STT 语音识别', _stt, 'stt'),
    _voiceSection('TTS 语音合成', _tts, 'tts'),
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
        '$provider · ${models.length} 个模型${isDefault ? ' · 当前默认' : ''}',
      ),
      children: [
        if (text(group['provider_key']).isNotEmpty || provider.isNotEmpty)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            leading: const Icon(Icons.edit_outlined, size: 18),
            title: const Text('编辑 Provider'),
            onTap: () => _showProviderEditor(group),
          ),
        if (flag(group['model_refreshable']))
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            leading: const Icon(Icons.sync_rounded, size: 18),
            title: const Text('刷新此 Provider 模型'),
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
              '还有 ${models.length - 80} 个模型，请在 Web 端精细管理。',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        if (flag(group['provider_editable']) || provider.startsWith('custom:'))
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 72, right: 16),
            leading: const Icon(Icons.delete_outline_rounded, size: 18),
            title: const Text('删除此 Provider'),
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
    await _run('默认模型已更新', () => api.setDefaultModel(model, provider));
  }

  Future<void> _refreshModelCache() async {
    final api = _api;
    if (api == null) return;
    setState(() => _refreshingCache = true);
    try {
      await api.refreshModelCache();
      _message('模型缓存刷新完成');
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
            title: const Text('确认更新模型目录'),
            content: Text(
              text(result['message']).isEmpty
                  ? '部分旧模型将从当前 Provider 列表中移除，是否继续？'
                  : text(result['message']),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('继续更新'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
        await api.refreshProviderModels(poolKey, confirm: true);
      }
      _message('Provider 模型目录已更新');
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
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                  decoration: const InputDecoration(labelText: '显示名称'),
                ),
                TextField(
                  controller: baseUrl,
                  enabled: editable,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                TextField(
                  controller: model,
                  enabled: editable,
                  decoration: const InputDecoration(labelText: '首选模型'),
                ),
                TextField(
                  controller: key,
                  enabled: editable,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: flag(detail['credential_configured'])
                        ? '替换 API Key（留空保持不变）'
                        : 'API Key',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: '接口模式'),
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
                      label: const Text('清除已保存的 API Key'),
                    ),
                  ),
                if (!editable)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        '此 Provider 由服务端环境变量管理，不能在此修改。',
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
              child: const Text('取消'),
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
                          ? 'Provider 连接测试成功'
                          : text(response['error']).isEmpty
                          ? 'Provider 连接测试失败'
                          : text(response['error']),
                      error: !flag(response['success']),
                    );
                  } catch (error) {
                    _message(_friendlyError(error), error: true);
                  }
                },
                child: const Text('测试连接'),
              ),
            FilledButton(
              onPressed: editable ? () => Navigator.pop(context, 'save') : null,
              child: const Text('保存'),
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
      await _run('Provider 已保存', () async {
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
        title: const Text('删除 Provider？'),
        content: Text('删除 $provider 后，服务端会切换到其他可用 Provider（如有）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run(
      'Provider 已删除',
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
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('添加 Provider'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
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
                  decoration: const InputDecoration(labelText: '默认模型'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: '接口模式'),
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty ||
                    url.text.trim().isEmpty ||
                    model.text.trim().isEmpty) {
                  _message('名称、Base URL 和默认模型不能为空', error: true);
                  return;
                }
                if (key.text.trim().isEmpty) {
                  _message(
                    '请输入 API Key；无需密钥的 Provider 请在服务端 Web 端添加',
                    error: true,
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      final api = _api;
      if (api != null) {
        await _run(
          'Provider 已添加',
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
    return _section(title, '配置由服务端保存，移动端不保存 API Key。', [
      ListTile(
        leading: Icon(
          kind == 'stt' ? Icons.mic_none_rounded : Icons.volume_up_outlined,
        ),
        title: Text(active.isEmpty ? '未启用' : active),
        subtitle: Text('${providers.length} 个已保存的 Provider'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showVoiceDialog(kind, providers, active),
      ),
      ListTile(
        leading: const Icon(Icons.add_circle_outline_rounded),
        title: Text('添加或编辑${kind == 'stt' ? ' STT' : ' TTS'} Provider'),
        subtitle: const Text('仅提交新的 API Key；已保存密钥不会回显'),
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
      _message('当前没有已配置的 $kind Provider，请在 Web 端先添加。');
      return;
    }
    var selected = options.contains(active) ? active : options.first;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(kind == 'stt' ? '选择 STT Provider' : '选择 TTS Provider'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
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
                            tooltip: '删除 Provider',
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: const Text('启用'),
            ),
          ],
        ),
      ),
    );
    if (result != null && _api != null) {
      await _run(
        '语音 Provider 已切换',
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
    return fields.isEmpty ? '使用服务端默认设置' : fields.join(' · ');
  }

  Future<void> _deleteVoiceProvider(String kind, String provider) async {
    final api = _api;
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除语音 Provider？'),
        content: Text('将删除服务端 $provider 配置和该 Provider 保存的密钥。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      '语音 Provider 已删除',
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
    final result = await showDialog<bool>(
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
          return AlertDialog(
            title: Text(kind == 'stt' ? '配置 STT Provider' : '配置 TTS Provider'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
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
                    decoration: const InputDecoration(
                      labelText: 'Base URL（可选）',
                    ),
                  ),
                  TextField(
                    controller: model,
                    decoration: const InputDecoration(labelText: '模型（可选）'),
                  ),
                  if (kind == 'tts')
                    TextField(
                      controller: voice,
                      decoration: const InputDecoration(
                        labelText: '音色 / Voice（可选）',
                      ),
                    ),
                  TextField(
                    controller: language,
                    decoration: const InputDecoration(labelText: '语言（可选）'),
                  ),
                  if (provider != 'edge' && provider != 'local')
                    TextField(
                      controller: apiKey,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: existing == null
                            ? 'API Key'
                            : '替换 API Key（留空保持不变）',
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存并启用'),
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
        '语音 Provider 已保存并启用',
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
    _section('用量', '按当前 Profile 统计最近 30 天的模型、Agent 和 Token 使用情况。', [
      _metricRow('会话', integer(_usage['total_sessions'])),
      _metricRow('输入 Token', integer(_usage['total_input_tokens'])),
      _metricRow('输出 Token', integer(_usage['total_output_tokens'])),
      _metricRow('估算费用', _number(_usage['total_cost'])),
    ]),
    _section('技能用量', '记录 Skill 加载与管理操作，不展开聊天正文。', [
      _metricRow(
        '技能动作',
        integer(asMap(_skillsUsage['summary'])['total_skill_actions']),
      ),
      _metricRow(
        '加载次数',
        integer(asMap(_skillsUsage['summary'])['total_skill_loads']),
      ),
      _metricRow(
        '编辑次数',
        integer(asMap(_skillsUsage['summary'])['total_skill_edits']),
      ),
      _metricRow(
        '使用过的技能',
        integer(asMap(_skillsUsage['summary'])['distinct_skills_used']),
      ),
    ]),
    _section('性能监控', '需要超级管理员权限；数据来自服务端进程，不是手机性能。', [
      _metricRow(
        '系统 CPU',
        _percent(asMap(_performance['system'])['cpuPercent']),
      ),
      _metricRow(
        '系统内存',
        _percent(asMap(_performance['system'])['memoryPercent']),
      ),
      _metricRow('活动会话', integer(asMap(_performance['sessions'])['active'])),
      _metricRow('运行会话', integer(asMap(_performance['sessions'])['running'])),
      ListTile(
        leading: const Icon(Icons.refresh_rounded),
        title: const Text('刷新性能数据'),
        onTap: _loadAll,
      ),
    ]),
    _section('服务日志', '按文件查看最近日志，便于定位断网、Agent 和 Provider 问题.', [
      _logSelector(),
      ..._logs.take(80).map(_logTile),
    ]),
  ]);

  Widget _logSelector() {
    if (_logFiles.isEmpty) {
      return const _EmptyRow(label: '暂无可读日志或权限不足');
    }
    final items = _logFiles
        .map(
          (file) => DropdownMenuItem<String>(
            value: text(file['name']),
            child: Text(text(file['name'])),
          ),
        )
        .toList();
    return DropdownButtonFormField<String>(
      initialValue: items.any((item) => item.value == _selectedLog)
          ? _selectedLog
          : null,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.description_outlined),
        labelText: '日志文件',
      ),
      items: items,
      onChanged: (value) {
        if (value == null) return;
        setState(() => _selectedLog = value);
        unawaited(_loadLogs());
      },
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
    _section('显示与聊天', '与 Web 端 Profile 配置同步，保存后由服务端生效。', [
      _switchRow(
        '流式输出',
        'display',
        'streaming',
        flag(asMap(_config['display'])['streaming']),
      ),
      _switchRow(
        '显示思考过程',
        'display',
        'show_reasoning',
        flag(asMap(_config['display'])['show_reasoning']),
      ),
      _switchRow(
        '显示费用',
        'display',
        'show_cost',
        flag(asMap(_config['display'])['show_cost']),
      ),
      _switchRow(
        '启用记忆',
        'memory',
        'memory_enabled',
        flag(asMap(_config['memory'])['memory_enabled']),
      ),
      _switchRow(
        '隐私脱敏',
        'privacy',
        'redact_pii',
        flag(asMap(_config['privacy'])['redact_pii']),
      ),
    ]),
    _section('运行参数', '适合手机快速调整的常用服务端参数。', [
      ListTile(
        leading: const Icon(Icons.speed_outlined),
        title: const Text('最大运行步数'),
        subtitle: Text('${integer(asMap(_config['agent'])['max_turns'])} 步'),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _showNumberConfig(
          'agent',
          'max_turns',
          integer(asMap(_config['agent'])['max_turns']),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.compress_outlined),
        title: const Text('上下文压缩'),
        subtitle: Text(
          flag(asMap(_config['compression'])['enabled']) ? '已启用' : '未启用',
        ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _showNumberConfig(
          'compression',
          'threshold',
          integer(asMap(_config['compression'])['threshold']),
        ),
      ),
    ]),
    _section('高级服务配置', '完整配置仍由服务端保存；此处可编辑移动端未单独展开的字段。', [
      ListTile(
        leading: const Icon(Icons.data_object_rounded),
        title: const Text('编辑完整服务配置'),
        subtitle: const Text('显示、记忆、隐私、代理和平台配置等'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showJsonEditor('完整服务配置', _config, _saveFullConfig),
      ),
    ]),
    _section('权限说明', '以下能力由服务端角色控制。移动端不会绕过权限。', [
      const ListTile(
        leading: Icon(Icons.admin_panel_settings_outlined),
        title: Text('管理员'),
        subtitle: Text('可写 Provider、模型和 Profile 配置，具体以服务端鉴权结果为准。'),
      ),
      const ListTile(
        leading: Icon(Icons.security_outlined),
        title: Text('超级管理员'),
        subtitle: Text('可查看服务性能与系统级诊断。'),
      ),
    ]),
  ]);

  Widget _switchRow(String title, String section, String key, bool value) =>
      SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: _saving
            ? null
            : (next) => _run(
                '$title已更新',
                () => _api!.updateConfigSection(section, {key: next}),
              ),
      );

  Future<void> _saveFullConfig(Map<String, dynamic> value) async {
    final api = _api;
    if (api == null) return;
    await _run('完整服务配置已保存', () async {
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

  Future<void> _showNumberConfig(
    String section,
    String key,
    int initial,
  ) async {
    final input = TextEditingController(text: initial > 0 ? '$initial' : '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('设置 $key'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '数值'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (save == true) {
      final value = int.tryParse(input.text.trim());
      if (value == null || value <= 0) {
        _message('请输入大于 0 的整数', error: true);
      } else {
        await _run(
          '配置已保存',
          () => _api!.updateConfigSection(section, {key: value}),
        );
      }
    }
    input.dispose();
  }

  Future<void> _showJsonEditor(
    String title,
    dynamic value,
    Future<void> Function(Map<String, dynamic>) save,
  ) async {
    final input = TextEditingController(text: _prettyJson(value));
    String? error;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 680,
            child: TextField(
              controller: input,
              minLines: 10,
              maxLines: 20,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                labelText: 'JSON 配置',
                errorText: error,
                alignLabelWithHint: true,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final decoded = jsonDecode(input.text);
                  if (decoded is! Map) {
                    throw const FormatException('配置必须是 JSON 对象');
                  }
                  Navigator.pop(context, true);
                } on FormatException catch (exception) {
                  setDialogState(() => error = exception.message);
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final decoded = jsonDecode(input.text);
      await save(Map<String, dynamic>.from(decoded as Map));
    }
    input.dispose();
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
