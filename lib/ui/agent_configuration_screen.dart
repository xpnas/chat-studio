import 'dart:convert';
import 'package:flutter/material.dart';
import '../data/agent_settings.dart';
import '../data/models.dart';
import '../data/studio_api.dart';
import '../l10n.dart';
import 'widgets/settings_editors.dart';
import 'runtime_manager_screen.dart';

class BuiltInAgentSettingsScreen extends AgentConfigurationScreen {
  const BuiltInAgentSettingsScreen({super.key, required super.api});
}

class HermesAgentSettingsScreen extends AgentConfigurationScreen {
  const HermesAgentSettingsScreen({super.key, required super.api})
    : super(hermes: true);
}

/// Shared native form; the two server protocols retain independent saves.
class AgentConfigurationScreen extends StatefulWidget {
  const AgentConfigurationScreen({
    super.key,
    required this.api,
    this.hermes = false,
  });
  final StudioApi api;
  final bool hermes;
  @override
  State<AgentConfigurationScreen> createState() =>
      _AgentConfigurationScreenState();
}

class _AgentConfigurationScreenState extends State<AgentConfigurationScreen> {
  final Map<String, Map<String, dynamic>> _changes = {};
  List<String> _profiles = [];
  String? _profilesError;
  Map<String, List<AgentSettingField>> get _sections =>
      widget.hermes ? hermesSettingsSections : builtInSettingsSections;
  Map<String, dynamic>? _config;
  String _path = '',
      _schema = '',
      _section = builtInSettingsSections.keys.first;
  String? _error;
  bool _loading = false, _saving = false, _dirty = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<bool> _discard() async =>
      !_dirty ||
      await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(context.tr('放弃未保存的更改？')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.tr('取消')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.tr('放弃')),
                ),
              ],
            ),
          ) ==
          true;

  Future<void> _load() async {
    if (_loading || _saving || !await _discard() || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = widget.hermes
          ? <String, dynamic>{
              'config': await widget.api.fetchConfig(
                sections: [
                  'agent',
                  'memory',
                  'skills',
                  'approvals',
                  'session_reset',
                  'gatewayAutoStart',
                ],
              ),
            }
          : await widget.api.builtInSettings();
      if (!mounted) return;
      if (data['config'] is! Map || asMap(data['config']).isEmpty) {
        throw const ApiException('服务端未返回配置');
      }
      setState(() {
        _config = asMap(jsonDecode(jsonEncode(data['config'])));
        _path = text(data['configPath']);
        _schema = '${data['schemaVersion'] ?? ''}';
        _dirty = false;
        _changes.clear();
      });
      if (widget.hermes) await _loadProfiles();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _loading || _config == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> data;
      if (widget.hermes) {
        // Only changed keys are patched. Successful sections are not resent if
        // a later section fails, and unsaved sections remain retryable.
        for (final section in _changes.keys.toList()) {
          await widget.api.updateConfigSection(section, _changes[section]!);
          _changes.remove(section);
        }
        data = {'config': _config};
      } else {
        data = await widget.api.saveBuiltInSettings(_config!);
      }
      if (!mounted) return;
      if (data['config'] is! Map || asMap(data['config']).isEmpty) {
        throw const ApiException('服务端未返回配置');
      }
      setState(() {
        _config = asMap(data['config']);
        _dirty = false;
      });
      final deferred = integer(asMap(data['runtimeRefresh'])['deferred']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(deferred > 0 ? '设置已保存，运行中的任务结束后生效' : '设置已保存'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _set(AgentSettingField field, Object? value) {
    setState(() {
      field.write(_config!, value);
      if (widget.hermes) {
        final parts = field.path.split('.');
        (_changes[parts.first] ??= {})[parts.last] = value;
      }
      _dirty = true;
    });
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = await widget.api.profiles();
      if (mounted) {
        setState(() {
          _profiles = profiles;
          _profilesError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _profilesError = '$e');
    }
  }

  Future<bool> _confirmDisableApproval() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('关闭工具审批？')),
          content: Text(context.tr('关闭审批会允许工具无需确认执行')),
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
      ) ==
      true;

  List<Widget> _gatewayRows() {
    final gateway = asMap(_config!['gatewayAutoStart']);
    final includedOnly = gateway['include'] is List;
    return [
      SwitchListTile.adaptive(
        key: const Key('gateway-include-mode'),
        title: Text(context.tr('仅启动所选 Profile')),
        subtitle: Text(
          context.tr(
            includedOnly ? '未选中任何 Profile 时不启动网关' : '启动全部 Profile，可设置排除项',
          ),
        ),
        value: includedOnly,
        onChanged: _loading || _saving
            ? null
            : (value) {
                _set(
                  const AgentSettingField('gatewayAutoStart.include', ''),
                  value ? <String>[] : null,
                );
                if (value) {
                  _set(
                    const AgentSettingField('gatewayAutoStart.exclude', ''),
                    null,
                  );
                }
              },
      ),
      if (_profilesError != null)
        ListTile(
          title: Text(context.tr('Profile 列表加载失败')),
          subtitle: Text(_profilesError!),
          trailing: const Icon(Icons.refresh_rounded),
          onTap: _loadProfiles,
        ),
      if (_profilesError == null)
        _row(
          AgentSettingField(
            includedOnly
                ? 'gatewayAutoStart.include'
                : 'gatewayAutoStart.exclude',
            includedOnly ? '包含的 Profile' : '排除的 Profile',
            kind: AgentSettingKind.profiles,
          ),
        ),
    ];
  }

  Future<void> _edit(AgentSettingField field) async {
    final value = field.read(_config!);
    if (field.kind == AgentSettingKind.choice) {
      final choice = await showSettingsSheet<String>(
        context: context,
        builder: (context) => SettingsSheet(
          title: Text(context.tr(field.label)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in field.options)
                ListTile(
                  title: Text(_choiceLabel(field, option)),
                  selected: option == value,
                  trailing: option == value
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, option),
                ),
            ],
          ),
        ),
      );
      if (mounted && choice != null) {
        if (field.path == 'approvals.mode' &&
            choice == 'off' &&
            !await _confirmDisableApproval()) {
          return;
        }
        if (mounted) _set(field, choice);
      }
      return;
    }
    if (field.kind == AgentSettingKind.languages ||
        field.kind == AgentSettingKind.profiles) {
      final values = asList(value).map(text).toSet();
      final result = await showSettingsSheet<List<String>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => SettingsSheet(
            title: Text(context.tr(field.label)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final language
                    in (field.kind == AgentSettingKind.languages
                        ? ['node', 'python']
                        : {..._profiles, ...values}.toList()))
                  CheckboxListTile(
                    title: Text(
                      field.kind == AgentSettingKind.profiles
                          ? language
                          : language == 'node'
                          ? 'Node.js'
                          : 'Python',
                    ),
                    value: values.contains(language),
                    onChanged: (selected) => update(() {
                      selected == true
                          ? values.add(language)
                          : values.remove(language);
                    }),
                  ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context, values.toList()),
                child: Text(context.tr('确认')),
              ),
            ],
          ),
        ),
      );
      if (mounted && result != null) {
        _set(
          field,
          field.path == 'gatewayAutoStart.exclude' && result.isEmpty
              ? null
              : result,
        );
      }
      return;
    }
    final lines = field.kind == AgentSettingKind.lines;
    final initial = lines
        ? asList(value).map(text).join('\n')
        : value?.toString() ?? '';
    final input = TextEditingController(text: initial);
    final form = GlobalKey<FormState>();
    final result = await showSettingsSheet<String>(
      context: context,
      builder: (context) => SettingsSheet(
        title: Text(context.tr(field.label)),
        content: Form(
          key: form,
          child: TextFormField(
            key: const Key('agent-setting-input'),
            controller: input,
            autofocus: true,
            minLines: lines ? 4 : 1,
            maxLines: lines ? 8 : 1,
            keyboardType: lines
                ? TextInputType.multiline
                : TextInputType.numberWithOptions(decimal: field.decimal),
            decoration: InputDecoration(
              helperText: field.hint.isEmpty ? null : context.tr(field.hint),
              helperMaxLines: 3,
              labelText: lines
                  ? context.tr('内容')
                  : field.max == null
                  ? context.l10n.format('最小值 {0}', {'0': field.min})
                  : context.l10n.format('范围 {0} – {1}', {
                      '0': field.min,
                      '1': field.max,
                    }),
            ),
            validator: lines
                ? null
                : (text) {
                    final error = field.validate(text ?? '');
                    return error == null ? null : context.tr(error);
                  },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, input.text);
              }
            },
            child: Text(context.tr('确认')),
          ),
        ],
      ),
    );
    input.dispose();
    if (!mounted || result == null) return;
    _set(
      field,
      lines
          ? result
                .split('\n')
                .map((v) => v.trim())
                .where((v) => v.isNotEmpty)
                .toList()
          : result.trim().isEmpty
          ? null
          : field.decimal
          ? num.parse(result.trim())
          : num.parse(result.trim()).toInt(),
    );
  }

  String _choiceLabel(AgentSettingField field, String value) => context.tr(
    field.path == 'model.reasoningEffort'
        ? reasoningEffortLabels[value] ?? value
        : const {
                'auto': '自动',
                'concise': '简洁',
                'detailed': '详细',
                'always': '始终',
                'never': '从不',
                'manual': '手动审批',
                'off': '关闭',
                'both': '空闲或每日',
                'idle': '空闲时',
                'daily': '每日',
                'none': '不重置',
                'per_profile': '按 Profile 独立管理',
                'unified': '统一管理',
              }[value] ??
              value,
  );
  Widget _row(AgentSettingField field) {
    final value =
        field.read(_config!) ??
        (widget.hermes
            ? const {
                'agent.tool_use_enforcement': 'auto',
                'session_reset.mode': 'both',
                'gatewayAutoStart.enabled': true,
                'gatewayAutoStart.management': 'auto',
              }[field.path]
            : null);
    final exists = widget.hermes || field.exists(_config!);
    final enabled = exists && !_saving && !_loading;
    final hint = !exists
        ? context.tr('当前服务端不支持此项')
        : field.hint.isEmpty
        ? null
        : context.tr(field.hint);
    if (field.kind == AgentSettingKind.toggle) {
      return SwitchListTile.adaptive(
        key: ValueKey(field.path),
        title: Text(context.tr(field.label)),
        subtitle: hint == null ? null : Text(hint),
        value: value == true,
        onChanged: !enabled
            ? null
            : (v) async {
                if (field.path == 'tools.approvals.enabled' && !v) {
                  final accepted = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.tr('关闭工具审批？')),
                      content: Text(context.tr('关闭审批会允许工具无需确认执行')),
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
                  if (!mounted || accepted != true) return;
                }
                _set(field, v);
              },
      );
    }
    final label = field.kind == AgentSettingKind.choice
        ? _choiceLabel(field, text(value))
        : value is List
        ? value.map(text).join(' · ')
        : value?.toString() ?? context.tr(widget.hermes ? '服务端默认' : '模型默认');
    return ListTile(
      key: ValueKey(field.path),
      enabled: enabled,
      title: Text(context.tr(field.label)),
      subtitle: Text(
        [if (label.isNotEmpty) label, ?hint].join('\n'),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      onTap: enabled ? () => _edit(field) : null,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_saving,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _saving) return;
      if (await _discard() && mounted) {
        setState(() => _dirty = false);
        if (context.mounted) Navigator.pop(context);
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.hermes ? 'Hermes' : 'Ekko Agent'),
        actions: [
          IconButton(
            tooltip: context.tr('刷新'),
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton(
            key: const Key('save-agent-settings'),
            onPressed: _dirty && !_saving && !_loading ? _save : null,
            child: Text(context.tr(_saving ? '保存中' : '保存')),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading || _saving) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_config != null) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              child: Row(
                children: [
                  for (final section in _sections.keys)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(context.tr(section)),
                        selected: section == _section,
                        onSelected: (_) => setState(() => _section = section),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                key: ValueKey(_section),
                padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
                children: [
                  if (widget.hermes && _section == '运行')
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(Icons.system_update_alt_rounded),
                        title: Text(context.tr('运行时版本管理')),
                        subtitle: Text(context.tr('版本、下载、运行目录与服务重启')),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _saving || _loading
                            ? null
                            : () async {
                                if (!await _discard() || !context.mounted) {
                                  return;
                                }
                                await Navigator.push<void>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RuntimeManagerScreen(api: widget.api),
                                  ),
                                );
                                if (mounted) {
                                  setState(() => _dirty = false);
                                  await _load();
                                }
                              },
                      ),
                    ),
                  Card(
                    child: Column(
                      children: [
                        for (final field in _sections[_section]!)
                          if (field.path != 'gatewayAutoStart.management' ||
                              widget.api.profile == 'default')
                            _row(field),
                        if (widget.hermes && _section == '网关')
                          ..._gatewayRows(),
                      ],
                    ),
                  ),
                  if (!widget.hermes && _section == '高级')
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText('Schema $_schema\n$_path'),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.hermes
                          ? context.l10n.format(
                              '当前 Profile：{0}。仅保存修改项，不会自动重启服务。',
                              {'0': widget.api.profile},
                            )
                          : context.tr('仅修改服务端 Agent 设置；点击保存后生效。'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (!_loading)
            TextButton(onPressed: _load, child: Text(context.tr('重试'))),
        ],
      ),
    ),
  );
}
