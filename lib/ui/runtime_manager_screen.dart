import 'dart:async';
import 'package:flutter/material.dart';
import '../data/agent_settings.dart';
import '../data/models.dart';
import '../data/studio_api.dart';
import '../l10n.dart';
import 'widgets/settings_editors.dart';

class RuntimeManagerScreen extends StatefulWidget {
  const RuntimeManagerScreen({super.key, required this.api});
  final StudioApi api;
  @override
  State<RuntimeManagerScreen> createState() => _RuntimeManagerScreenState();
}

class _RuntimeManagerScreenState extends State<RuntimeManagerScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _status;
  List<Map<String, dynamic>> _jobs = [];
  final Set<String> _actions = {};
  String? _error;
  bool _refreshing = false,
      _polling = false,
      _foreground = true,
      _restartNeeded = false;
  Timer? _timer;
  Map<String, dynamic> get _runtime => asMap(_status?['hermes']);
  List<Map<String, dynamic>> get _installed => asList(
    _runtime['installed'],
  ).map(asMap).where((row) => row['platform'] == _status?['platform']).toList();
  bool get _running =>
      _jobs.any((job) => ['queued', 'running'].contains(job['status']));
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh(remote: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _timer?.cancel();
    } else {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh({bool remote = false}) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    try {
      final status = await widget.api.runtimeVersions(remote: remote);
      if (!mounted) return;
      if (status['hermes'] is! Map) throw const ApiException('服务端未返回运行时信息');
      setState(() {
        // Local refreshes must not erase an already fetched remote catalog.
        final oldRemote = _runtime['remoteVersions'];
        _status = status;
        if (!remote && oldRemote != null) {
          _status!['hermes'] = {..._runtime, 'remoteVersions': oldRemote};
        }
      });
      final jobs = await widget.api.runtimeJobs();
      if (mounted) {
        setState(
          () => _jobs = jobs.where((j) => j['kind'] == 'runtime').toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
        _schedule();
      }
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_foreground || !_running || !mounted) return;
    _timer = Timer(const Duration(seconds: 2), _poll);
  }

  Future<void> _poll() async {
    if (_polling || _refreshing) {
      _schedule();
      return;
    }
    _polling = true;
    try {
      final jobs = await widget.api.runtimeJobs();
      if (!mounted) return;
      final wasRunning = _running;
      setState(
        () => _jobs = jobs.where((j) => j['kind'] == 'runtime').toList(),
      );
      if (wasRunning && !_running) {
        _restartNeeded =
            _restartNeeded || _jobs.any((j) => j['status'] == 'completed');
        await _refresh();
      }
      _schedule();
    } catch (e) {
      // Stop polling on errors; retry is explicit, not an infinite network loop.
      if (mounted) setState(() => _error = '$e');
    } finally {
      _polling = false;
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
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
      ) ==
      true;
  Future<void> _act(String key, Future<void> Function() action) async {
    if (_actions.isNotEmpty || _refreshing) return;
    setState(() {
      _actions.add(key);
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _actions.remove(key));
    }
  }

  Future<void> _activate(String version) async {
    if (!await _confirm(
          context.tr('切换运行时？'),
          context.l10n.format('切换至 {0}，重启服务后生效；可能中断正在执行的任务。', {'0': version}),
        ) ||
        !mounted) {
      return;
    }
    await _act('activate:$version', () async {
      await widget.api.activateRuntime(version);
      if (!mounted) return;
      setState(() => _restartNeeded = true);
      await _refresh();
    });
  }

  Future<void> _delete(String version) async {
    if (!await _confirm(
          context.tr('删除运行时？'),
          context.l10n.format('从服务器删除版本 {0}，此操作不可撤销。', {'0': version}),
        ) ||
        !mounted) {
      return;
    }
    await _act('delete:$version', () async {
      await widget.api.deleteRuntime(version);
      if (mounted) await _refresh();
    });
  }

  Future<void> _download([String version = '']) async {
    final input = TextEditingController(text: version);
    var source = 'github';
    final form = GlobalKey<FormState>();
    final selected = await showSettingsSheet<(String, String)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SettingsSheet(
          title: Text(context.tr('下载运行时')),
          content: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.tr('安装和下载均在服务器执行，不会下载到手机。')),
                const SizedBox(height: 16),
                TextFormField(
                  controller: input,
                  decoration: InputDecoration(labelText: context.tr('版本号')),
                  validator: (v) =>
                      v == null ||
                          !RegExp(
                            r'^v?\d+\.\d+\.\d+[a-zA-Z0-9.+-]*$',
                          ).hasMatch(v.trim())
                      ? context.tr('请输入有效版本号')
                      : null,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final item in ['github', 'cf'])
                      ChoiceChip(
                        label: Text(item == 'github' ? 'GitHub' : 'Cloudflare'),
                        selected: item == source,
                        onSelected: (_) => update(() => source = item),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(context, (
                    input.text.trim().replaceFirst(RegExp(r'^v'), ''),
                    source,
                  ));
                }
              },
              child: Text(context.tr('开始下载')),
            ),
          ],
        ),
      ),
    );
    input.dispose();
    if (!mounted || selected == null) return;
    await _act('download:${selected.$1}', () async {
      final result = await widget.api.downloadRuntime(selected.$1, selected.$2);
      if (!mounted) return;
      final job = asMap(result['job']);
      if (job['id'] == null) throw const ApiException('服务端未返回下载任务');
      setState(
        () => _jobs = [job, ..._jobs.where((j) => j['id'] != job['id'])],
      );
      _schedule();
    });
  }

  Future<void> _directory({bool reset = false}) async {
    final current = text(_runtime['pendingStorageDirectory']).isNotEmpty
        ? text(_runtime['pendingStorageDirectory'])
        : text(_runtime['storageDirectory']);
    final directory = reset
        ? text(_runtime['defaultStorageDirectory'])
        : await showSettingsTextEditor(
            context: context,
            title: context.tr('运行时存储目录'),
            label: context.tr('服务器上的绝对路径，不是手机目录'),
            initialValue: current,
          );
    if (!mounted ||
        directory == null ||
        directory.trim().isEmpty ||
        directory.trim() == current) {
      return;
    }
    final target = directory.trim();
    if (!target.startsWith('/') &&
        !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(target) &&
        !target.startsWith(r'\\')) {
      setState(() => _error = context.tr('请输入服务器上的绝对路径'));
      return;
    }
    if (!await _confirm(
          context.tr('迁移运行时目录？'),
          context.l10n.format('目标目录：{0}。重启服务器后迁移运行时文件，不会改变手机文件。', {
            '0': target,
          }),
        ) ||
        !mounted) {
      return;
    }
    await _act('directory', () async {
      await widget.api.setRuntimeDirectory(target);
      if (!mounted) return;
      setState(() => _restartNeeded = true);
      await _refresh();
    });
  }

  Future<void> _restart() async {
    if (!await _confirm(
          context.tr('重启服务？'),
          context.tr('这会暂时断开所有设备连接，并可能中断执行中的任务。'),
        ) ||
        !mounted) {
      return;
    }
    await _act('restart', () async {
      await widget.api.restartRuntimeService();
      if (!mounted) return;
      setState(() => _restartNeeded = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('已请求重启，请稍后刷新状态'))));
    });
  }

  Widget _detail(String title, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr(title), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        SelectableText(value == null || '$value'.isEmpty ? '—' : '$value'),
      ],
    ),
  );
  Widget _version(String version) {
    final installed = _installed
        .where((r) => r['version'] == version)
        .firstOrNull;
    final active = installed?['active'] == true;
    final downloading = _jobs.any(
      (j) =>
          j['version'] == version &&
          ['running', 'queued'].contains(j['status']),
    );
    final enabled = _actions.isEmpty && !_refreshing && !downloading;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    version,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  context.tr(
                    active
                        ? '当前使用'
                        : installed != null
                        ? '已安装'
                        : '可下载',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (installed != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  text(installed['directory']),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (installed == null)
                  TextButton.icon(
                    onPressed: enabled ? () => _download(version) : null,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(context.tr(downloading ? '下载中' : '下载')),
                  ),
                if (installed != null && !active) ...[
                  TextButton(
                    onPressed: enabled ? () => _activate(version) : null,
                    child: Text(context.tr('切换')),
                  ),
                  TextButton(
                    onPressed: enabled ? () => _delete(version) : null,
                    child: Text(context.tr('删除')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _job(Map<String, dynamic> job) {
    final percent = num.tryParse('${job['percent']}');
    final progress = percent != null && percent.isFinite
        ? (percent / 100).clamp(0.0, 1.0)
        : null;
    final state = text(job['status']);
    final stage = text(job['stage']);
    final label =
        (state == 'running'
            ? const {
                'resolve': '解析版本',
                'download': '下载中',
                'verify': '验证文件',
                'extract': '解压文件',
                'install': '安装中',
              }[stage]
            : null) ??
        const {
          'queued': '排队中',
          'running': '下载中',
          'completed': '已完成',
          'failed': '失败',
        }[state] ??
        state;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${job['version']} · ${context.tr(label)} · ${job['source'] ?? ''}',
          ),
          const SizedBox(height: 6),
          if (['queued', 'running'].contains(state))
            LinearProgressIndicator(value: progress, minHeight: 3),
          if (integer(job['totalBytes']) > 0)
            Text(
              '${integer(job['receivedBytes']) ~/ 1048576} / ${integer(job['totalBytes']) ~/ 1048576} MB',
            ),
          if (text(job['error']).isNotEmpty)
            SelectableText(
              text(job['error']),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final versions =
        {
            ...asList(_runtime['remoteVersions']).map(text),
            ..._installed.map((r) => text(r['version'])),
            ...asList(asMap(_status?['active'])['runtimeValidationFailures'])
                .map(asMap)
                .where((r) => r['platform'] == _status?['platform'])
                .map((r) => text(r['version'])),
          }.where((v) => v.isNotEmpty).toList()
          ..sort((a, b) => _compareVersions(b, a));
    final busy = _refreshing || _actions.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hermes Runtime'),
        actions: [
          IconButton(
            tooltip: context.tr('检查更新'),
            onPressed: busy ? null : () => _refresh(remote: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(remote: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(15, 8, 15, 24),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_status != null) ...[
                    Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _detail(
                            '运行来源',
                            context.tr(
                              const {
                                    'managed-runtime': '受管理运行时',
                                    'user-cli': '用户安装的 CLI',
                                    'none': '未安装',
                                  }[text(_runtime['source'])] ??
                                  text(_runtime['source']),
                            ),
                          ),
                          _detail('Agent 版本', _runtime['agentVersion']),
                          _detail('运行时版本', _runtime['activeVersion']),
                          ExpansionTile(
                            title: Text(context.tr('路径与 CLI 详情')),
                            children: [
                              _detail('运行目录', _runtime['activeDirectory']),
                              _detail('Python 路径', _runtime['pythonPath']),
                              _detail('Agent 根目录', _runtime['agentRoot']),
                              _detail('数据目录', _runtime['dataDirectory']),
                              for (final cli in asList(
                                _runtime['cliInstallations'],
                              ).map(asMap))
                                _detail(
                                  '${cli['version']} · ${cli['source']}',
                                  cli['path'],
                                ),
                            ],
                          ),
                          _detail('运行时存储目录', _runtime['storageDirectory']),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: busy ? null : () => _directory(),
                                  child: Text(context.tr('修改目录')),
                                ),
                                TextButton(
                                  onPressed:
                                      busy ||
                                          text(
                                            _runtime['defaultStorageDirectory'],
                                          ).isEmpty ||
                                          (text(_runtime['pendingStorageDirectory'])
                                                      .isNotEmpty
                                                  ? _runtime['pendingStorageDirectory']
                                                  : _runtime['storageDirectory']) ==
                                              _runtime['defaultStorageDirectory']
                                      ? null
                                      : () => _directory(reset: true),
                                  child: Text(context.tr('恢复默认目录')),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    for (final key in [
                      'pendingStorageDirectory',
                      'migrationError',
                      'activationError',
                    ])
                      if (text(_runtime[key]).isNotEmpty)
                        _detail(
                          context.tr(
                            const {
                              'pendingStorageDirectory': '等待迁移的目录',
                              'migrationError': '迁移失败',
                              'activationError': '激活失败',
                            }[key]!,
                          ),
                          _runtime[key],
                        ),
                    for (final failure in asList(
                      asMap(_status?['active'])['runtimeValidationFailures'],
                    ).map(asMap))
                      _detail(
                        '${context.tr('校验失败')} · ${failure['version']}',
                        failure['reason'],
                      ),
                    if (text(_status?['remoteError']).isNotEmpty)
                      _detail('远程版本列表获取失败', _status?['remoteError']),
                    if (_restartNeeded ||
                        text(_runtime['pendingStorageDirectory']).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: FilledButton.tonalIcon(
                          onPressed: busy ? null : _restart,
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: Text(context.tr('重启服务以应用更改')),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Text(
                        context.tr('运行时版本'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final version in versions) _version(version),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _download,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('下载指定版本')),
                    ),
                    if (_jobs.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          context.tr('下载任务'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Card(
                        child: Column(
                          children: [for (final job in _jobs) _job(job)],
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        context.tr(
                          '这里只管理服务器上的 Hermes Runtime。CLI 来源的更新需在服务器执行；不会更新手机 App。',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ] else if (!_refreshing)
                    TextButton(
                      onPressed: () => _refresh(remote: true),
                      child: Text(context.tr('重试')),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

int _compareVersions(String a, String b) {
  final left = a.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.+-]'));
  final right = b.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.+-]'));
  for (var i = 0; i < left.length && i < right.length; i++) {
    final l = int.tryParse(left[i]), r = int.tryParse(right[i]);
    final result = l != null && r != null
        ? l.compareTo(r)
        : left[i].compareTo(right[i]);
    if (result != 0) return result;
  }
  return left.length.compareTo(right.length);
}
