import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/agent_catalog.dart';
import '../../state/app_controller.dart';
import 'agent_avatar.dart';

/// A compact dropdown-style entry with a touch-friendly, live-updating sheet.
class AgentPickerButton extends StatelessWidget {
  const AgentPickerButton({super.key, required this.controller});
  final AppController controller;

  Future<void> _open(BuildContext context) async {
    final c = controller;
    final revision = c.chatRevision;
    final client = c.api;
    final profile = c.profile;
    bool valid() =>
        c.chatRevision == revision &&
        c.api == client &&
        c.profile == profile &&
        c.sessionId == null;
    unawaited(c.refreshAgents());
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: c,
        builder: (_, _) {
          final colors = Theme.of(sheetContext).colorScheme;
          final choices = c.agents.where((a) => a.installed).toList()
            ..sort((a, b) {
              final selected = (b.id == c.engine ? 1 : 0).compareTo(
                a.id == c.engine ? 1 : 0,
              );
              return selected != 0
                  ? selected
                  : a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * .7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '选择 Agent',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '刷新 Agent',
                          onPressed: c.agentsLoading || !valid()
                              ? null
                              : c.refreshAgents,
                          icon: const Icon(Icons.refresh_rounded, size: 21),
                        ),
                      ],
                    ),
                  ),
                  if (c.agentsLoading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (!valid())
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('会话已切换，请关闭后重新选择。'),
                    )
                  else if (c.agentsError != null)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            c.agentsError!,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          TextButton.icon(
                            onPressed: c.agentsLoading ? null : c.refreshAgents,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('重新加载'),
                          ),
                        ],
                      ),
                    )
                  else if (choices.isEmpty && !c.agentsLoading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '服务端没有可用的 Agent。\n请在服务端 Agent 管理页面安装或启用。',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: choices.length,
                        itemBuilder: (_, i) {
                          final agent = choices[i];
                          final selected = agent.id == c.engine;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Material(
                              color: selected
                                  ? colors.primary.withValues(alpha: .07)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              child: ListTile(
                                key: ValueKey('agent-option:${agent.id}'),
                                dense: true,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                leading: AgentAvatar(
                                  controller: c,
                                  agentId: agent.id,
                                  size: 30,
                                ),
                                title: Text(
                                  agent.name,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                subtitle: agent.supported
                                    ? null
                                    : const Text(
                                        '当前服务协议暂不支持此 Agent',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                trailing: selected
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 20,
                                        color: colors.primary,
                                      )
                                    : null,
                                enabled: agent.selectable && !c.agentsLoading,
                                onTap: () {
                                  if (!valid()) return;
                                  c.chooseEngine(agent.id);
                                  Navigator.of(sheetContext).pop();
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (valid() && c.agentsError == null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Text(
                        '来自当前服务器 · 仅显示已安装 Agent',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final name = AgentChoice.metadata(c.engine).name;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          key: const ValueKey('agent-picker'),
          style: TextButton.styleFrom(
            foregroundColor: colors.onSurface,
            backgroundColor: colors.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          onPressed: c.working ? null : () => _open(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AgentAvatar(controller: c, agentId: c.engine, size: 23),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              if (c.agentsLoading)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
            ],
          ),
        ),
        if (c.agentsError != null ||
            (c.agentsLoaded && !c.agentsLoading && c.availableAgents.isEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              c.agentsError != null ? 'Agent 列表加载失败，点击重试' : '暂无可用 Agent，点击查看',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
