import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n.dart';
import '../data/models.dart';
import '../state/message_selection_controller.dart';

class MessageSelectionScreen<T extends Object, R extends Object>
    extends StatefulWidget {
  const MessageSelectionScreen({
    super.key,
    required this.title,
    required this.controller,
    required this.messages,
    this.initialMessageId,
    this.scopeChanges,
  });
  final String title;
  final MessageSelectionController<T, R> controller;
  final List<ChatMessage> messages;
  final String? initialMessageId;
  final Listenable? scopeChanges;
  @override
  State<MessageSelectionScreen<T, R>> createState() =>
      _MessageSelectionScreenState<T, R>();
}

class _MessageSelectionScreenState<T extends Object, R extends Object>
    extends State<MessageSelectionScreen<T, R>> {
  MessageSelectionController<T, R> get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    widget.scopeChanges?.addListener(scopeChanged);
    unawaited(load());
  }

  Future<void> load() async {
    await c.refresh();
    if (!mounted) return;
    final group = c.snapshot?.groups
        .where(
          (group) =>
              group.messageIds.any((id) => '$id' == widget.initialMessageId),
        )
        .firstOrNull;
    if (group != null) c.toggle(group.id);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void scopeChanged() {
    if (c.valid() || !mounted) return;
    c.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    });
  }

  @override
  void dispose() {
    c.removeListener(changed);
    widget.scopeChanges?.removeListener(scopeChanged);
    c.dispose();
    super.dispose();
  }

  Future<void> confirm() async {
    final count = c.messageIds.length, groups = c.selectedGroups.length;
    final visible = widget.messages.map((m) => m.id).toSet();
    final hidden = c.messageIds.where((id) => !visible.contains('$id')).length;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('删除所选消息？')),
        content: Text(
          '${widget.title}\n${context.l10n.format("{0} 组，共 {1} 条记录", {'0': groups, '1': count})}\n${context.l10n.format("包含 {0} 条未展示或跨页记录", {'0': hidden})}\n${context.tr('来源被删除会移除关联任务；完成证据被删除会重开任务并清空证据。此操作无法撤销。')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('确认删除')),
          ),
        ],
      ),
    );
    if (!mounted || approved != true || !c.canDelete) return;
    if (await c.deleteConfirmed() && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !c.submitting,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('选择消息')),
          actions: [
            TextButton(
              onPressed: c.submitting
                  ? null
                  : () {
                      c.cancel();
                      Navigator.pop(context);
                    },
              child: Text(context.tr('取消')),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (c.loading || c.submitting)
              const LinearProgressIndicator(minHeight: 2),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context.tr(c.error!),
                  style: TextStyle(color: colors.error),
                ),
              ),
            if (c.snapshot == null && !c.loading)
              TextButton(
                onPressed: c.submitting ? null : c.refresh,
                child: Text(context.tr('刷新并重新选择')),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  for (final group in c.snapshot?.groups ?? [])
                    Builder(
                      builder: (context) {
                        final members = widget.messages
                            .where(
                              (message) => group.messageIds.any(
                                (id) => '$id' == message.id,
                              ),
                            )
                            .toList();
                        return CheckboxListTile(
                          value: c.selected.contains(group.id),
                          onChanged:
                              group.selectable && !c.submitting && !c.uncertain
                              ? (_) => c.toggle(group.id)
                              : null,
                          title: Text(
                            members.isEmpty
                                ? context.tr('未展示的记录')
                                : members
                                      .map(
                                        (m) => m.content.isEmpty
                                            ? context.tr('附件或工具记录')
                                            : m.content,
                                      )
                                      .join('\n'),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${context.tr(group.kind == 'run' ? '完整运行组' : '单条消息')} · ${group.messageIds.length}\n${group.blockedReason.isEmpty ? context.tr('将删除此组全部记录，包括隐藏或跨页记录') : context.tr(switch (group.blockedReason) {
                                    'compressed' => '压缩依赖记录不可删除',
                                    'summarized' => '摘要依赖记录不可删除',
                                    'compression_boundary_unknown' || 'summary_boundary_unknown' => '无法确认摘要依赖边界',
                                    _ => '此分组暂不可删除',
                                  })}',
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: c.canDelete ? confirm : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(
                      context.l10n.format('删除 {0} 组 / {1} 条记录', {
                        '0': c.selectedGroups.length,
                        '1': c.messageIds.length,
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
