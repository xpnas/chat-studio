import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/agent_capabilities.dart';
import '../data/models.dart';
import '../data/studio_api.dart';
import '../l10n.dart';
import '../state/app_controller.dart';
import 'widgets/agent_avatar.dart';
import 'widgets/settings_editors.dart';
import 'theme.dart';

/// Mobile counterpart of the Web Studio sidebars. It uses compact full-screen
/// lists instead of copying the desktop two-column layout.
class AgentCapabilitiesScreen extends StatefulWidget {
  const AgentCapabilitiesScreen({
    super.key,
    required this.api,
    required this.controller,
  });
  final StudioApi api;
  final AppController controller;
  @override
  State<AgentCapabilitiesScreen> createState() =>
      _AgentCapabilitiesScreenState();
}

class _AgentCapabilitiesScreenState extends State<AgentCapabilitiesScreen> {
  bool _hermes = true;
  bool _loading = false;
  String? _error;

  List<_Capability> get _capabilities => [
    if (_hermes) ...[
      _Capability('tasks', '任务', '创建、暂停和立即执行定时任务', Icons.schedule_rounded),
      _Capability(
        'channels',
        '频道',
        '配置 Telegram、Discord、Slack 等消息入口',
        Icons.forum_outlined,
      ),
      _Capability('skills', '技能', '启用、置顶并查看可复用技能', Icons.auto_awesome_outlined),
      _Capability('plugins', '插件', '查看插件状态并启用或停用', Icons.extension_outlined),
      _Capability('mcp', 'MCP', '管理外部工具服务器和连接状态', Icons.hub_outlined),
      _Capability(
        'memory',
        '记忆',
        '编辑 Hermes 的长期记忆、用户和灵魂档案',
        Icons.psychology_outlined,
      ),
    ] else ...[
      _Capability(
        'skills',
        '技能',
        '管理 Ekko Agent 技能和启用状态',
        Icons.auto_awesome_outlined,
      ),
      _Capability('mcp', 'MCP', '管理 Ekko Agent 的外部工具服务器', Icons.hub_outlined),
      _Capability(
        'memory',
        '记忆',
        '搜索、编辑和删除 Ekko 记忆节点',
        Icons.psychology_outlined,
      ),
    ],
  ];

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_hermes) {
        await widget.api.hermesSkills();
      } else {
        await widget.api.ekkoSkills();
      }
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(_Capability capability) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AgentCapabilityDetailScreen(
          api: widget.api,
          controller: widget.controller,
          hermes: _hermes,
          capability: capability.id,
          title: capability.title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.tr('Agent 能力')),
      actions: [
        IconButton(
          tooltip: context.tr('刷新'),
          onPressed: _loading ? null : _refresh,
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          context.tr('将 Web 端左侧管理功能整理为适合手机操作的能力入口。所有修改直接保存到当前服务器和 Profile。'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: true,
              icon: AgentAvatar(
                controller: widget.controller,
                agentId: 'hermes',
                size: 22,
              ),
              label: Text(context.tr('Hermes')),
            ),
            ButtonSegment(
              value: false,
              icon: AgentAvatar(
                controller: widget.controller,
                agentId: 'ekko-agent',
                size: 22,
              ),
              label: Text(context.tr('Ekko')),
            ),
          ],
          selected: {_hermes},
          onSelectionChanged: (value) {
            if (value.isNotEmpty && value.first != _hermes) {
              setState(() {
                _hermes = value.first;
                _error = null;
              });
            }
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          ErrorNotice(
            message: _error!,
            onDismiss: () => setState(() => _error = null),
          ),
        ],
        const SizedBox(height: 20),
        ..._capabilities.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CapabilityTile(item: item, onTap: () => _open(item)),
          ),
        ),
      ],
    ),
  );

  String _friendlyError(Object error) =>
      error is ApiException ? error.message : '$error';
}

class _Capability {
  const _Capability(this.id, this.title, this.subtitle, this.icon);
  final String id, title, subtitle;
  final IconData icon;
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({required this.item, required this.onTap});
  final _Capability item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(item.icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class AgentCapabilityDetailScreen extends StatefulWidget {
  const AgentCapabilityDetailScreen({
    super.key,
    required this.api,
    required this.controller,
    required this.hermes,
    required this.capability,
    required this.title,
  });
  final StudioApi api;
  final AppController controller;
  final bool hermes;
  final String capability, title;
  @override
  State<AgentCapabilityDetailScreen> createState() =>
      _AgentCapabilityDetailScreenState();
}

class _AgentCapabilityDetailScreenState
    extends State<AgentCapabilityDetailScreen> {
  bool _loading = true, _working = false;
  String? _error;
  dynamic _data;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _data = switch (widget.capability) {
        'tasks' => await widget.api.hermesJobs(),
        'channels' => await widget.api.fetchConfig(),
        'skills' =>
          widget.hermes
              ? await widget.api.hermesSkills()
              : await widget.api.ekkoSkills(),
        'plugins' => await widget.api.hermesPlugins(),
        'mcp' =>
          widget.hermes
              ? await widget.api.hermesMcpServers()
              : await widget.api.ekkoMcpServers(),
        'memory' =>
          widget.hermes
              ? await widget.api.hermesMemory()
              : await widget.api.ekkoMemory(),
        _ => <String, dynamic>{},
      };
    } catch (error) {
      _error = _friendlyError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    String success = '已保存',
  }) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      if (mounted) _snack(success);
      await _load();
    } catch (error) {
      if (mounted) _snack(_friendlyError(error), error: true);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _snack(String message, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  String _friendlyError(Object error) =>
      error is ApiException ? error.message : '$error';
  List<Map<String, dynamic>> _rows(dynamic value, [String key = '']) => asList(
    key.isEmpty ? value : asMap(value)[key],
  ).map(asMap).where((row) => row.isNotEmpty).toList();
  String _pretty(dynamic value) {
    try {
      return const JsonEncoder.withIndent(
        '  ',
      ).convert(value is Map ? value : <String, dynamic>{});
    } catch (_) {
      return '{}';
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: context.tr('刷新'),
          onPressed: _loading || _working ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
        if (_supportsAdd)
          IconButton(
            tooltip: context.tr('添加'),
            onPressed: _working ? null : _add,
            icon: const Icon(Icons.add_rounded),
          ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? ErrorNotice(message: _error!, onDismiss: _load)
        : _body,
  );

  bool get _supportsAdd =>
      widget.capability == 'tasks' ||
      widget.capability == 'mcp' ||
      (widget.capability == 'skills' && !widget.hermes);
  Widget get _body => switch (widget.capability) {
    'tasks' => _tasks(),
    'channels' => _channels(),
    'skills' => _skills(),
    'plugins' => _plugins(),
    'mcp' => _mcp(),
    'memory' => _memory(),
    _ => const SizedBox.shrink(),
  };
  Widget _list({required List<Widget> children, String? empty}) =>
      children.isEmpty
      ? Center(
          child: Text(
            empty ?? context.tr('暂无数据'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        )
      : ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
          children: children,
        );
  Widget _tasks() {
    final rows = _rows(_data, 'jobs');
    return _list(
      empty: context.tr('暂无任务，点击右上角添加'),
      children: rows.map((job) {
        final id = text(job['job_id']).isNotEmpty
            ? text(job['job_id'])
            : text(job['id']);
        final enabled = flag(job['enabled']);
        final schedule = text(job['schedule_display']).isEmpty
            ? text(job['schedule'])
            : text(job['schedule_display']);
        final prompt = text(job['prompt_preview']).isEmpty
            ? text(job['prompt'])
            : text(job['prompt_preview']);
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Icon(
                enabled ? Icons.schedule_rounded : Icons.pause_rounded,
                size: 19,
              ),
            ),
            title: Text(
              text(job['name']).isEmpty ? id : text(job['name']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '$schedule\n$prompt',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: PopupMenuButton<String>(
              onSelected: (action) => _taskAction(id, action, enabled),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: enabled ? 'pause' : 'resume',
                  child: Text(enabled ? context.tr('暂停') : context.tr('恢复')),
                ),
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(value: 'run', child: Text('立即执行')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _taskAction(String id, String action, bool enabled) async {
    if (action == 'edit') {
      final job = _rows(_data, 'jobs').firstWhere(
        (row) =>
            (text(row['job_id']).isNotEmpty
                ? text(row['job_id'])
                : text(row['id'])) ==
            id,
        orElse: () => <String, dynamic>{},
      );
      if (job.isNotEmpty) await _showTaskEditor(job: job);
    } else if (action == 'delete') {
      if (await _confirm('删除任务', '确认删除这个任务？') != true) return;
      await _run(() => widget.api.deleteHermesJob(id), success: '任务已删除');
    } else if (action == 'pause') {
      await _run(() async {
        await widget.api.pauseHermesJob(id);
      }, success: '任务已暂停');
    } else if (action == 'resume') {
      await _run(() async {
        await widget.api.resumeHermesJob(id);
      }, success: '任务已恢复');
    } else {
      await _run(() async {
        await widget.api.runHermesJob(id);
      }, success: '任务已提交执行');
    }
  }

  Future<void> _add() async {
    if (widget.capability == 'tasks') return _showTaskEditor();
    if (widget.capability == 'mcp') return _showMcpEditor();
    if (widget.capability == 'skills' && !widget.hermes) {
      return _showEkkoSkillEditor();
    }
  }

  Future<void> _showTaskEditor({Map<String, dynamic>? job}) async {
    final editingId = job == null
        ? null
        : (text(job['job_id']).isNotEmpty
              ? text(job['job_id'])
              : text(job['id']));
    final name = TextEditingController(text: text(job?['name']));
    final schedule = TextEditingController(
      text: text(job?['schedule_display']).isNotEmpty
          ? text(job?['schedule_display'])
          : (text(job?['schedule']).isEmpty
                ? '0 9 * * *'
                : text(job?['schedule'])),
    );
    final prompt = TextEditingController(text: text(job?['prompt']));
    final result = await showSettingsSheet<Map<String, String>>(
      context: context,
      builder: (context) => SettingsSheet(
        title: Text(context.tr(editingId == null ? '创建任务' : '编辑任务')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: context.tr('名称')),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: schedule,
              decoration: const InputDecoration(
                labelText: 'Cron / schedule',
                helperText: '例如：0 9 * * * 或 every 30m',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: prompt,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(labelText: context.tr('任务提示词')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'name': name.text.trim(),
              'schedule': schedule.text.trim(),
              'prompt': prompt.text.trim(),
            }),
            child: Text(context.tr(editingId == null ? '创建' : '保存')),
          ),
        ],
      ),
    );
    name.dispose();
    schedule.dispose();
    prompt.dispose();
    if (!mounted ||
        result == null ||
        result['name']!.isEmpty ||
        result['schedule']!.isEmpty) {
      return;
    }
    await _run(() async {
      if (editingId == null) {
        await widget.api.createHermesJob(
          name: result['name']!,
          schedule: result['schedule']!,
          prompt: result['prompt']!,
        );
      } else {
        await widget.api.updateHermesJob(editingId, {
          'name': result['name']!,
          'schedule': result['schedule']!,
          'prompt': result['prompt']!,
        });
      }
    }, success: editingId == null ? '任务已创建' : '任务已更新');
  }

  Widget _channels() {
    final config = asMap(_data);
    const platforms = [
      'telegram',
      'discord',
      'slack',
      'whatsapp',
      'matrix',
      'weixin',
      'wecom',
      'feishu',
      'dingtalk',
      'qqbot',
    ];
    return _list(
      children: platforms.map((platform) {
        final values = asMap(config[platform]);
        final enabled = flag(values['enabled']) || values.isNotEmpty;
        return Card(
          child: ListTile(
            leading: Icon(
              enabled ? Icons.link_rounded : Icons.link_off_rounded,
              color: enabled ? Colors.green : null,
            ),
            title: Text(platform),
            subtitle: Text(
              enabled ? context.tr('已配置 · 点击编辑') : context.tr('未配置'),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _editJson(
              '$platform 频道配置',
              values,
              (value) => widget.api.updateConfigSection(platform, value),
            ),
          ),
        );
      }).toList(),
      empty: context.tr('当前服务未返回频道配置'),
    );
  }

  Widget _skills() {
    final rows = <Map<String, dynamic>>[];
    if (widget.hermes) {
      for (final category in asList(asMap(_data)['categories'])) {
        final group = asMap(category);
        for (final skill in asList(group['skills'])) {
          final item = asMap(skill);
          if (text(item['name']).isNotEmpty) {
            rows.add({...item, '_category': text(group['name'])});
          }
        }
      }
    } else {
      rows.addAll(_rows(_data, 'skills'));
    }
    return _list(
      children: rows.map((skill) {
        final name = text(skill['name']);
        final enabled = skill['enabled'] != false;
        final pinned = flag(skill['pinned']);
        return Card(
          child: ListTile(
            leading: Icon(
              pinned ? Icons.push_pin_rounded : Icons.auto_awesome_outlined,
            ),
            title: Text(name),
            subtitle: Text(
              [
                text(skill['description']),
                text(skill['_category']),
              ].where((v) => v.isNotEmpty).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.hermes)
                  IconButton(
                    tooltip: pinned ? context.tr('取消置顶') : context.tr('置顶'),
                    onPressed: _working ? null : () => _pinSkill(name, !pinned),
                    icon: Icon(
                      pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    ),
                  ),
                Switch(
                  value: enabled,
                  onChanged: _working
                      ? null
                      : (value) => _toggleSkill(name, value),
                ),
                if (!widget.hermes && !flag(skill['builtIn']))
                  IconButton(
                    tooltip: context.tr('删除'),
                    onPressed: _working ? null : () => _deleteEkkoSkill(name),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                if (widget.hermes && text(skill['source']) == 'local')
                  IconButton(
                    tooltip: context.tr('删除'),
                    onPressed: _working
                        ? null
                        : () => _deleteHermesSkill(
                            text(skill['_category']).isEmpty
                                ? 'misc'
                                : text(skill['_category']),
                            name,
                          ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
            onTap: () => _showSkillDetail(skill),
          ),
        );
      }).toList(),
      empty: context.tr('暂无技能'),
    );
  }

  Future<void> _toggleSkill(String name, bool enabled) => _run(() async {
    if (widget.hermes) {
      await widget.api.setHermesSkillEnabled(name, enabled);
    } else {
      await widget.api.setEkkoSkillEnabled(name, enabled);
    }
  }, success: enabled ? '技能已启用' : '技能已停用');

  Future<void> _pinSkill(String name, bool pinned) => _run(() async {
    await widget.api.setHermesSkillPinned(name, pinned);
  }, success: pinned ? '技能已置顶' : '已取消技能置顶');

  Future<void> _deleteHermesSkill(String category, String name) async {
    if (await _confirm('删除技能', '确认删除 $name？') != true) return;
    await _run(
      () => widget.api.deleteHermesSkill(category, name),
      success: '技能已删除',
    );
  }

  Future<void> _deleteEkkoSkill(String name) async {
    if (await _confirm('删除技能', '确认删除 $name？') != true) return;
    await _run(() => widget.api.deleteEkkoSkill(name), success: '技能已删除');
  }

  Future<void> _showEkkoSkillEditor() async {
    final name = TextEditingController();
    final content = TextEditingController(text: '# Skill\n\n');
    final result = await showSettingsSheet<Map<String, String>>(
      context: context,
      builder: (context) => SettingsSheet(
        title: Text(context.tr('新建技能')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: context.tr('名称')),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('技能内容')),
              subtitle: Text(
                content.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.fullscreen_rounded),
              onTap: () async {
                final value = await showSettingsTextEditor(
                  context: context,
                  title: context.tr('技能内容'),
                  label: 'SKILL.md',
                  initialValue: content.text,
                );
                if (value != null) content.text = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'name': name.text.trim(),
              'content': content.text,
            }),
            child: Text(context.tr('创建')),
          ),
        ],
      ),
    );
    name.dispose();
    content.dispose();
    if (!mounted || result == null || result['name']!.isEmpty) return;
    await _run(
      () => widget.api.createEkkoSkill(result['name']!, result['content']!),
      success: '技能已创建',
    );
  }

  Future<void> _showSkillDetail(Map<String, dynamic> skill) async {
    final name = text(skill['name']);
    final category = text(skill['_category']).isEmpty
        ? 'misc'
        : text(skill['_category']);
    if (widget.hermes) {
      try {
        final content = await widget.api.hermesSkillContent(category, name);
        if (!mounted) return;
        final value = await showSettingsTextEditor(
          context: context,
          title: name,
          label: context.tr('技能内容'),
          initialValue: content,
        );
        if (value != null) {
          await _run(
            () => widget.api.updateHermesSkill(category, name, value),
            success: '技能已更新',
          );
        }
      } catch (error) {
        if (mounted) _snack(_friendlyError(error), error: true);
      }
      return;
    }
    if (!widget.hermes) {
      try {
        final detail = await widget.api.ekkoSkill(name);
        final content = text(asMap(detail['skill'])['content']);
        if (!mounted) return;
        final value = await showSettingsTextEditor(
          context: context,
          title: name,
          label: context.tr('技能内容'),
          initialValue: content,
        );
        if (value != null) {
          await _run(() async {
            await widget.api.updateEkkoSkill(name, value);
          }, success: '技能已更新');
        }
      } catch (error) {
        if (mounted) _snack(_friendlyError(error), error: true);
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(name),
        content: SingleChildScrollView(child: Text(_pretty(skill))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('关闭')),
          ),
        ],
      ),
    );
  }

  Widget _plugins() {
    final rows = _rows(_data, 'plugins');
    return _list(
      children: rows.map((plugin) {
        final key = text(plugin['key']).isNotEmpty
            ? text(plugin['key'])
            : text(plugin['name']);
        final enabled =
            [
              'enabled',
              'auto-active',
              'provider-managed',
            ].contains(text(plugin['effectiveStatus'])) ||
            text(plugin['configStatus']) == 'enabled';
        final locked = text(plugin['configStatus']) == 'provider-managed';
        return Card(
          child: ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: Text(
              text(plugin['name']).isEmpty ? key : text(plugin['name']),
            ),
            subtitle: Text(
              [
                text(plugin['description']),
                text(plugin['version']),
              ].where((v) => v.isNotEmpty).join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: locked
                ? const Icon(Icons.lock_outline_rounded)
                : Switch(
                    value: enabled,
                    onChanged: _working
                        ? null
                        : (value) => _run(
                            () => widget.api.setHermesPluginEnabled(key, value),
                            success: value ? '插件已启用' : '插件已停用',
                          ),
                  ),
          ),
        );
      }).toList(),
      empty: context.tr('暂无插件'),
    );
  }

  Widget _mcp() {
    final rows = _rows(_data, 'servers');
    return _list(
      children: rows.map((server) {
        final name = text(server['name']);
        final connected =
            flag(server['connected']) ||
            flag(asMap(server['config'])['enabled']);
        return Card(
          child: ListTile(
            leading: Icon(
              connected ? Icons.check_circle_outline : Icons.error_outline,
              color: connected ? Colors.green : null,
            ),
            title: Text(name),
            subtitle: Text(
              widget.hermes
                  ? '${text(server['transport'])} · ${text(server['tools'])} tools'
                  : (flag(asMap(server['config'])['enabled'])
                        ? 'enabled'
                        : 'disabled'),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) => _mcpAction(name, value, server),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'test', child: Text('测试连接')),
                PopupMenuItem(value: 'edit', child: Text('编辑 JSON')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
        );
      }).toList(),
      empty: context.tr('暂无 MCP 服务，点击右上角添加'),
    );
  }

  Future<void> _mcpAction(
    String name,
    String action,
    Map<String, dynamic> server,
  ) async {
    if (action == 'test') {
      await _run(() async {
        final result = widget.hermes
            ? await widget.api.hermesMcpTest(name)
            : await widget.api.testEkkoMcp(name);
        final tools = asList(result['tools']);
        if (mounted) {
          _snack(tools.isEmpty ? '连接成功，未发现工具' : '连接成功 · ${tools.length} 个工具');
        }
      }, success: 'MCP 测试完成');
    } else if (action == 'delete') {
      if (await _confirm('删除 MCP 服务', '确认删除 $name？') != true) return;
      await _run(() async {
        if (widget.hermes) {
          await widget.api.deleteHermesMcp(name);
        } else {
          await widget.api.deleteEkkoMcp(name);
        }
      }, success: 'MCP 服务已删除');
    } else {
      final initial = widget.hermes
          ? asMap(server['raw_config'])
          : asMap(server['config']);
      await _editJson('编辑 $name', initial, (value) async {
        if (widget.hermes) {
          await widget.api.updateHermesMcp(name, value);
        } else {
          await widget.api.updateEkkoMcp(name, value);
        }
      });
    }
  }

  Future<void> _showMcpEditor() async {
    final name = TextEditingController();
    final config = TextEditingController(
      text: '{\n  "command": "",\n  "args": []\n}',
    );
    final result = await showSettingsSheet<Map<String, String>>(
      context: context,
      builder: (context) => SettingsSheet(
        title: Text(context.tr('添加 MCP 服务')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(labelText: context.tr('服务名称')),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('JSON 配置')),
              subtitle: Text(
                config.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.fullscreen_rounded),
              onTap: () async {
                final value = await showSettingsTextEditor(
                  context: context,
                  title: context.tr('MCP 配置'),
                  label: 'JSON',
                  initialValue: config.text,
                  validator: validateJsonObject,
                );
                if (value != null) config.text = value;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'name': name.text.trim(),
              'config': config.text,
            }),
            child: Text(context.tr('添加')),
          ),
        ],
      ),
    );
    name.dispose();
    config.dispose();
    if (!mounted || result == null || result['name']!.isEmpty) return;
    try {
      final decoded = jsonDecode(result['config']!);
      if (decoded is! Map) throw const FormatException('JSON 配置必须是对象');
      await _run(() async {
        if (widget.hermes) {
          await widget.api.addHermesMcp(
            result['name']!,
            Map<String, dynamic>.from(decoded),
          );
        } else {
          await widget.api.addEkkoMcp(
            result['name']!,
            Map<String, dynamic>.from(decoded),
          );
        }
      }, success: 'MCP 服务已添加');
    } catch (error) {
      if (mounted) _snack(_friendlyError(error), error: true);
    }
  }

  Widget _memory() {
    if (widget.hermes) {
      final map = asMap(_data);
      const sections = ['memory', 'user', 'soul'];
      return _list(
        children: sections
            .map(
              (section) => Card(
                child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(
                    section == 'memory'
                        ? 'Memory'
                        : section == 'user'
                        ? 'User'
                        : 'Soul',
                  ),
                  subtitle: Text(
                    text(map[section]).isEmpty
                        ? context.tr('暂无内容')
                        : text(map[section]),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editMemory(section, text(map[section])),
                ),
              ),
            )
            .toList(),
        empty: context.tr('暂无记忆'),
      );
    }
    final rows = _rows(_data, 'memories');
    return _list(
      children: rows.map((memory) {
        final id = text(memory['id']);
        final revision = integer(memory['revision']);
        return Card(
          child: ListTile(
            leading: const Icon(Icons.psychology_outlined),
            title: Text(
              text(memory['title']).isEmpty
                  ? text(memory['key'])
                  : text(memory['title']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              text(memory['content']),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'edit') await _editEkkoMemory(memory);
                if (action == 'delete' &&
                    await _confirm('删除记忆', '确认删除这条记忆？') == true) {
                  await _run(
                    () => widget.api.deleteEkkoMemory(id, revision),
                    success: '记忆已删除',
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
        );
      }).toList(),
      empty: context.tr('暂无记忆节点'),
    );
  }

  Future<void> _editMemory(String section, String initial) async {
    final value = await showSettingsTextEditor(
      context: context,
      title: '编辑 $section',
      label: context.tr('内容'),
      initialValue: initial,
    );
    if (value != null) {
      await _run(
        () => widget.api.saveHermesMemory(section, value),
        success: '记忆已保存',
      );
    }
  }

  Future<void> _editEkkoMemory(Map<String, dynamic> memory) async {
    final initial = '${text(memory['title'])}\n\n${text(memory['content'])}';
    final value = await showSettingsTextEditor(
      context: context,
      title: text(memory['title']),
      label: context.tr('标题和内容'),
      initialValue: initial,
    );
    if (value == null) return;
    final parts = value.split('\n\n');
    final title = parts.isEmpty ? text(memory['title']) : parts.first.trim();
    final content = parts.length > 1
        ? parts.sublist(1).join('\n\n').trim()
        : '';
    await _run(
      () => widget.api.updateEkkoMemory(
        text(memory['id']),
        integer(memory['revision']),
        title,
        content,
        asList(memory['tags']).map(text).toList(),
      ),
      success: '记忆已更新',
    );
  }

  Future<void> _editJson(
    String title,
    Map<String, dynamic> initial,
    Future<void> Function(Map<String, dynamic>) save,
  ) async {
    final value = await showSettingsTextEditor(
      context: context,
      title: title,
      label: 'JSON',
      initialValue: _pretty(initial),
      validator: validateJsonObject,
    );
    if (value == null) return;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map) throw const FormatException('JSON 配置必须是对象');
      await _run(
        () => save(Map<String, dynamic>.from(decoded)),
        success: '配置已保存',
      );
    } catch (error) {
      if (mounted) _snack(_friendlyError(error), error: true);
    }
  }

  Future<bool?> _confirm(String title, String message) => showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(context.tr('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.tr('确认')),
        ),
      ],
    ),
  );
}
