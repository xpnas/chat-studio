import 'package:flutter/material.dart';
import '../../data/task_plan.dart';

/// A secondary, compact plan surface: no avatar, assistant bubble or tool log.
/// Stable page-storage identity keeps user expansion across stream updates.
class TaskPlanCard extends StatelessWidget {
  const TaskPlanCard({super.key, required this.plan});
  final TaskPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey(plan.key),
        initiallyExpanded: false,
        dense: true,
        visualDensity: VisualDensity.compact,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: colors.onSurfaceVariant,
        collapsedIconColor: colors.onSurfaceVariant,
        title: Row(
          children: [
            Icon(
              Icons.checklist_rounded,
              size: 17,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                '任务计划',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${plan.completed}/${plan.steps.length} 已完成',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: plan.completed / plan.steps.length,
                minHeight: 2,
                borderRadius: BorderRadius.circular(2),
                color: colors.primary.withValues(alpha: .65),
                backgroundColor: colors.onSurface.withValues(alpha: .06),
                semanticsLabel: '计划完成进度',
                semanticsValue:
                    '${(100 * plan.completed / plan.steps.length).round()}%',
              ),
              const SizedBox(height: 5),
              Text(
                plan.currentStep == null
                    ? plan.stateLabel
                    : '进行中 · ${plan.currentStep!.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        children: [
          for (final step in plan.steps)
            Padding(
              key: ValueKey('${plan.key}:${step.id}'),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    step.status == 'completed'
                        ? Icons.check_circle_outline_rounded
                        : step.status == 'in_progress' && plan.isRunning
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 15,
                    color:
                        step.status == 'completed' ||
                            (step.status == 'in_progress' && plan.isRunning)
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      step.title,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    step.status == 'completed'
                        ? '已完成'
                        : step.status == 'in_progress' && plan.isRunning
                        ? '进行中'
                        : '未完成',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.6,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          if (plan.explanation.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  plan.explanation,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
