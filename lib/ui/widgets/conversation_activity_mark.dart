import 'package:flutter/material.dart';
import '../../state/conversation_state.dart';
import '../../l10n.dart';

class ConversationActivityMark extends StatelessWidget {
  const ConversationActivityMark({super.key, required this.status});
  final ConversationTaskStatus status;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (status == ConversationTaskStatus.idle) return const SizedBox(width: 18);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final label = context.tr(status.label);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: SizedBox(
          width: 18,
          height: 18,
          child: switch (status) {
            ConversationTaskStatus.running => CircularProgressIndicator(
              key: const Key('task-running-animation'),
              strokeWidth: 1.7,
              value: reduceMotion ? .7 : null,
              color: colors.primary,
            ),
            ConversationTaskStatus.waiting => Icon(
              Icons.pending_actions_rounded,
              size: 18,
              color: colors.tertiary,
            ),
            ConversationTaskStatus.checking => Icon(
              Icons.sync_problem_rounded,
              size: 17,
              color: colors.onSurfaceVariant,
            ),
            ConversationTaskStatus.completed => Icon(
              Icons.check_circle_outline_rounded,
              size: 17,
              color: colors.primary,
            ),
            ConversationTaskStatus.failed => Icon(
              Icons.error_outline_rounded,
              size: 17,
              color: colors.error,
            ),
            ConversationTaskStatus.idle => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}
