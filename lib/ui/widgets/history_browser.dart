import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../../state/history_controller.dart';
import '../history_detail_screen.dart';
import 'agent_avatar.dart';

class HistoryBrowser extends StatefulWidget {
  const HistoryBrowser({super.key, required this.controller});
  final AppController controller;
  @override
  State<HistoryBrowser> createState() => _HistoryBrowserState();
}

class _HistoryBrowserState extends State<HistoryBrowser> {
  late final history = HistoryController(
    widget.controller.api!,
    widget.controller.profile,
  );
  final selected = <String>{};
  final collapsed = <String>{};
  bool selecting = false, initialized = false;
  @override
  void initState() {
    super.initState();
    history.addListener(_changed);
    unawaited(history.refresh());
  }

  void _changed() {
    if (!mounted) return;
    if (!initialized && !history.loading && history.error == null) {
      initialized = true;
      collapsed.addAll(history.groups.skip(1).map((g) => g.source));
    }
    selected.removeWhere((key) => !history.entries.containsKey(key));
    setState(() {});
  }

  @override
  void dispose() {
    history.removeListener(_changed);
    history.dispose();
    super.dispose();
  }

  Future<bool> _confirmDelete(int count) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.format('删除 {0} 段对话？', {'0': count})),
          content: Text(context.tr('会同时删除服务端的对话记录，无法撤销。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('删除')),
            ),
          ],
        ),
      ) ??
      false;

  void _notice(Object text) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$text')));
    }
  }

  Future<void> _act(HistoryEntry entry, String action) async {
    if (history.mutating) return;
    try {
      if (action == 'copy-id' || action == 'copy-link') {
        final row = entry.conversation;
        final value = action == 'copy-id'
            ? row.id
            : history.linkFor(entry).toString();
        await Clipboard.setData(ClipboardData(text: value));
        if (mounted) _notice(context.tr('已复制'));
        return;
      }
      if (action == 'delete' && !await _confirmDelete(1)) return;
      if (!mounted) return;
      await history.action(entry, action);
      if (mounted) unawaited(widget.controller.refreshSessions());
    } catch (e) {
      _notice(e);
    }
  }

  Future<void> _deleteSelected() async {
    final targets = selected
        .map((key) => history.entries[key])
        .nonNulls
        .toList();
    if (targets.isEmpty || !await _confirmDelete(targets.length) || !mounted) {
      return;
    }
    try {
      final result = await history.deleteSelected(targets);
      if (mounted) {
        _notice(
          context.l10n.format('已删除 {0} 条，失败 {1} 条', {
            '0': integer(result['deleted']),
            '1': integer(result['failed']),
          }),
        );
        setState(() {
          selecting = false;
          selected.clear();
        });
        unawaited(widget.controller.refreshSessions());
      }
    } catch (e) {
      _notice(e);
    }
  }

  Widget _row(HistoryEntry entry) {
    final row = entry.conversation;
    return ListTile(
      key: ValueKey('history:${entry.key}'),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      leading: selecting
          ? Checkbox(
              value: selected.contains(entry.key),
              onChanged: history.mutating ? null : (_) => _toggle(entry.key),
            )
          : AgentAvatar(
              controller: widget.controller,
              agentId: row.agent,
              size: 24,
            ),
      title: Text(
        row.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        [
          if (row.model.isNotEmpty) row.model,
          if (row.isArchived) context.tr('已归档'),
          if (entry.imported == false) context.tr('未导入'),
          if (row.updatedAt > 0)
            DateTime.fromMillisecondsSinceEpoch(
              row.updatedAt * 1000,
            ).toLocal().toString().substring(0, 16),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      onTap: history.mutating
          ? null
          : () {
              if (selecting) {
                _toggle(entry.key);
                return;
              }
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => HistoryDetailScreen(
                    controller: widget.controller,
                    conversation: row,
                  ),
                ),
              );
            },
      trailing: selecting
          ? null
          : PopupMenuButton<String>(
              tooltip: context.tr('管理历史'),
              enabled: !history.mutating,
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
              onSelected: (action) => _act(entry, action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'import',
                  enabled: entry.imported != true,
                  child: Text(context.tr('导入单聊')),
                ),
                PopupMenuItem(
                  value: 'pin',
                  enabled: entry.imported != false,
                  child: Text(
                    row.isPinned ? context.tr('取消置顶') : context.tr('置顶对话'),
                  ),
                ),
                if (row.isArchived)
                  PopupMenuItem(
                    value: 'unarchive',
                    child: Text(context.tr('移出归档')),
                  ),
                PopupMenuItem(
                  value: 'copy-link',
                  child: Text(context.tr('复制链接')),
                ),
                PopupMenuItem(
                  value: 'copy-id',
                  child: Text(context.tr('复制 ID')),
                ),
                PopupMenuItem(value: 'delete', child: Text(context.tr('删除对话'))),
              ],
            ),
    );
  }

  void _toggle(String key) => setState(() {
    if (!selected.remove(key)) selected.add(key);
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 20, right: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selecting
                    ? context.l10n.format('已选 {0} 条', {'0': selected.length})
                    : context.tr('历史'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (selecting) ...[
              IconButton(
                tooltip: context.tr('选择全部已加载记录'),
                icon: const Icon(Icons.select_all_rounded, size: 20),
                onPressed: history.mutating
                    ? null
                    : () => setState(() {
                        if (selected.length == history.entries.length) {
                          selected.clear();
                        } else {
                          selected.addAll(history.entries.keys);
                        }
                      }),
              ),
              IconButton(
                tooltip: context.tr('删除选中'),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                onPressed: selected.isEmpty || history.mutating
                    ? null
                    : _deleteSelected,
              ),
            ],
            IconButton(
              tooltip: selecting ? context.tr('取消选择') : context.tr('批量选择'),
              onPressed: history.mutating
                  ? null
                  : () => setState(() {
                      selecting = !selecting;
                      selected.clear();
                    }),
              icon: Icon(
                selecting ? Icons.close_rounded : Icons.checklist_rounded,
                size: 20,
              ),
            ),
            IconButton(
              tooltip: context.tr('刷新历史'),
              onPressed: history.loading || history.mutating
                  ? null
                  : history.refresh,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
      ),
      if (history.loading || history.mutating)
        const LinearProgressIndicator(minHeight: 2),
      if (history.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  history.error!,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: history.loading ? null : history.refresh,
                child: Text(context.tr('重试')),
              ),
            ],
          ),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: history.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (history.entries.isEmpty &&
                  !history.loading &&
                  history.error == null)
                Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text(context.tr('暂无历史记录'))),
                ),
              if (history.rows(pinned: true).isNotEmpty) ...[
                ListTile(
                  dense: true,
                  leading: Icon(Icons.push_pin_outlined, size: 18),
                  title: Text(
                    context.tr('置顶'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                ...history.rows(pinned: true).map(_row),
              ],
              for (final group in history.groups) ...[
                ListTile(
                  key: ValueKey('history-source:${group.source}'),
                  dense: true,
                  title: Text(
                    historySourceLabel(group.source),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Icon(
                    collapsed.contains(group.source)
                        ? Icons.expand_more
                        : Icons.expand_less,
                    size: 20,
                  ),
                  onTap: () => setState(() {
                    if (!collapsed.remove(group.source)) {
                      collapsed.add(group.source);
                    }
                  }),
                ),
                if (!collapsed.contains(group.source)) ...[
                  ...history.rows(source: group.source).map(_row),
                  if (group.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        group.error!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  if (group.hasMore)
                    Center(
                      child: TextButton(
                        onPressed:
                            group.loading || history.loading || history.mutating
                            ? null
                            : () => history.loadMore(group),
                        child: Text(
                          group.loading
                              ? context.tr('加载中…')
                              : group.error == null
                              ? context.tr('加载更多')
                              : context.tr('重试'),
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    ],
  );
}
