import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n.dart';
import '../data/session_tasks.dart';
import '../data/protocol_capabilities.dart';
import '../state/app_controller.dart';
import '../state/session_tasks_controller.dart';
import 'widgets/message_bubble.dart';

class SessionTasksScreen extends StatefulWidget {
  const SessionTasksScreen({super.key, required this.app, this.sessionId});
  final AppController app;
  final String? sessionId;
  @override
  State<SessionTasksScreen> createState() => _SessionTasksScreenState();
}

class _SessionTasksScreenState extends State<SessionTasksScreen>
    with WidgetsBindingObserver {
  late final SessionTasksController c = SessionTasksController(
    widget.app.api!,
    sessionId: widget.sessionId,
  );
  final search = TextEditingController();
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(changed);
    widget.app.addListener(scopeChanged);
    unawaited(c.refresh());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void scopeChanged() {
    if (!c.valid && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route != null) Navigator.of(context).removeRoute(route);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(c.refresh());
  }

  @override
  void dispose() {
    debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(scopeChanged);
    c.removeListener(changed);
    c.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> evidence(SessionGoal task, int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TaskEvidenceScreen(app: widget.app, task: task, messageId: id),
      ),
    );
    if (mounted) await c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(widget.sessionId == null ? '任务中心' : '当前会话目标')),
        actions: [
          IconButton(
            tooltip: context.tr('刷新'),
            onPressed: () => c.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: search,
                decoration: InputDecoration(
                  labelText: context.tr('搜索任务'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (value) {
                  debounce?.cancel();
                  debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => c.filter(search: value),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (value, label) in const [
                    ('', '全部'),
                    ('open', '进行中'),
                    ('completed', '已完成'),
                    ('closed', '任务已关闭'),
                  ])
                    ChoiceChip(
                      label: Text(context.tr(label)),
                      selected: c.status == value,
                      onSelected: (_) => c.filter(status: value),
                    ),
                  FilterChip(
                    label: Text(context.tr('最早优先')),
                    selected: c.order == 'oldest',
                    onSelected: (v) => c.filter(order: v ? 'oldest' : 'newest'),
                  ),
                  if (widget.sessionId == null)
                    FilterChip(
                      label: Text(context.tr('全部授权 Profile')),
                      selected: c.allProfiles,
                      onSelected: (v) => c.filter(allProfiles: v),
                    ),
                ],
              ),
            ),
            if (c.loading) const LinearProgressIndicator(minHeight: 2),
            if (c.notice != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(context.tr(c.notice!)),
              ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  c.capability == CapabilityState.unsupported
                      ? context.tr('服务端不支持任务中心，运行计划仍可使用')
                      : context.tr(c.error!),
                  style: TextStyle(color: colors.error),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => c.refresh(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                  children: [
                    if (!c.loading && c.error == null && c.tasks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            context.tr('没有匹配的任务'),
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ),
                      ),
                    for (final task in c.tasks)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              if (task.summary.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(task.summary),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                '${task.sessionTitle.isEmpty ? task.sessionId : task.sessionTitle} · ${task.profile}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                '${context.tr(task.status == 'open'
                                    ? '进行中'
                                    : task.status == 'completed'
                                    ? '已完成'
                                    : task.status == 'closed'
                                    ? '任务已关闭'
                                    : task.status)} · ${task.updatedAt == null ? '—' : DateTime.fromMillisecondsSinceEpoch(task.updatedAt!).toLocal().toString().substring(0, 16)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              if (task.completionEvidence.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(task.completionEvidence),
                              ],
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (task.sourceMessageId != null)
                                    TextButton(
                                      onPressed: () =>
                                          evidence(task, task.sourceMessageId!),
                                      child: Text(context.tr('查看来源')),
                                    ),
                                  if (task.evidenceMessageId != null)
                                    TextButton(
                                      onPressed: () => evidence(
                                        task,
                                        task.evidenceMessageId!,
                                      ),
                                      child: Text(context.tr('查看完成证据')),
                                    ),
                                  for (final (value, label) in const [
                                    ('completed', '完成'),
                                    ('open', '重开'),
                                    ('closed', '关闭'),
                                  ])
                                    if (task.status != value)
                                      TextButton(
                                        onPressed:
                                            !task.editable ||
                                                c.pending.contains(task.key) ||
                                                c.uncertain.contains(task.key)
                                            ? null
                                            : () => c.setStatus(task, value),
                                        child: Text(context.tr(label)),
                                      ),
                                ],
                              ),
                              if (c.pending.contains(task.key))
                                const LinearProgressIndicator(),
                            ],
                          ),
                        ),
                      ),
                    if (c.hasMore)
                      TextButton(
                        onPressed: c.loading
                            ? null
                            : () => c.refresh(more: true),
                        child: Text(context.tr('加载更多')),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TaskEvidenceScreen extends StatefulWidget {
  const TaskEvidenceScreen({
    super.key,
    required this.app,
    required this.task,
    required this.messageId,
  });
  final AppController app;
  final SessionGoal task;
  final int messageId;
  @override
  State<TaskEvidenceScreen> createState() => _TaskEvidenceScreenState();
}

class _TaskEvidenceScreenState extends State<TaskEvidenceScreen> {
  final lookup = EvidenceLookup();
  late final api = widget.app.api;
  late final token = api?.token;
  late final profile = api?.profile;
  @override
  void initState() {
    super.initState();
    widget.app.addListener(scopeChanged);
  }

  void scopeChanged() {
    if (widget.app.api == api &&
        api?.token == token &&
        api?.profile == profile) {
      return;
    }
    lookup.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    });
  }

  late final result = lookup.locate(
    widget.app.api!,
    widget.task,
    widget.messageId,
  );
  @override
  void dispose() {
    widget.app.removeListener(scopeChanged);
    lookup.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.task.sessionTitle.isEmpty
            ? widget.task.sessionId
            : widget.task.sessionTitle,
      ),
    ),
    body: FutureBuilder(
      future: result,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                TextButton(
                  onPressed: () {
                    lookup.cancel();
                    Navigator.pop(context);
                  },
                  child: Text(context.tr('取消定位')),
                ),
              ],
            ),
          );
        }
        final (status, message) = snapshot.data!;
        if (status == EvidenceResult.found && message != null) {
          return SingleChildScrollView(
            child: MessageBubble(message: message, controller: widget.app),
          );
        }
        return Center(
          child: Text(
            context.tr(switch (status) {
              EvidenceResult.forbidden => '没有权限查看此证据',
              EvidenceResult.limit => '已达定位页数上限，请在 Studio 查看',
              EvidenceResult.cancelled => '已取消定位',
              EvidenceResult.unsupported => '此记录无法在手机展示',
              _ => '消息已删除或不可用',
            }),
          ),
        );
      },
    ),
  );
}
