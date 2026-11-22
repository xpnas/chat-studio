import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../data/structured_interaction.dart';
import '../../l10n.dart';
import 'structured_interaction_card.dart';

/// Shared approval and clarification card for single, group and BOT chats.
class ChatInteractionCard extends StatefulWidget {
  const ChatInteractionCard({
    super.key,
    required this.data,
    required this.enabled,
    required this.submitting,
    required this.onRespond,
    this.error,
    this.onSync,
    this.canSync = false,
    this.allowPermanent = true,
    this.maxHeight,
    this.margin = const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
  });

  final Map<String, dynamic> data;
  final bool enabled;
  final bool submitting;
  final ValueChanged<String> onRespond;
  final String? error;
  final VoidCallback? onSync;
  final bool canSync;
  final bool allowPermanent;
  final double? maxHeight;
  final EdgeInsetsGeometry margin;

  @override
  State<ChatInteractionCard> createState() => _ChatInteractionCardState();
}

class _ChatInteractionCardState extends State<ChatInteractionCard> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submitText() {
    final value = _field.text.trim();
    if (!widget.enabled || widget.submitting || value.isEmpty) return;
    widget.onRespond(value);
    _field.clear();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final approval = data['kind'] == 'approval.requested';
    final canRespond = widget.enabled && !widget.submitting;
    final choices = asList(data['choices']).whereType<String>().toList();
    final questionSet = approval
        ? null
        : StructuredQuestionSet.parse(data['questions']) ??
              StructuredQuestionSet.parse(data['question']);
    final prompt = approval
        ? (text(data['description']).isNotEmpty
              ? text(data['description'])
              : text(data['question']))
        : (text(data['question']).isNotEmpty
              ? text(data['question'])
              : text(data['description']));
    final command = approval ? text(data['command']) : '';
    final canPermanent =
        widget.allowPermanent &&
        data['allow_permanent'] == true &&
        data['durable'] != true &&
        choices.contains('always');
    final showOnce = choices.isEmpty || choices.contains('once');
    final showDeny = choices.isEmpty || choices.contains('deny');
    final extraApprovalChoices = choices
        .where((c) => c != 'once' && c != 'deny' && c != 'always')
        .toList();
    final colors = Theme.of(context).colorScheme;
    final limit = widget.maxHeight ?? (questionSet == null ? 270.0 : 500.0);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: limit),
      child: SingleChildScrollView(
        child: Container(
          margin: widget.margin,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approval ? context.tr('需要你的授权') : context.tr('需要你补充信息'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (questionSet == null && prompt.isNotEmpty)
                SelectableText(prompt),
              if (command.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SelectableText(
                    command,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              if (questionSet == null) const SizedBox(height: 8),
              if (widget.error != null) ...[
                Text(widget.error!, style: TextStyle(color: colors.error)),
                if (widget.onSync != null)
                  TextButton(
                    onPressed: widget.canSync ? widget.onSync : null,
                    child: Text(context.tr('同步审批状态')),
                  ),
              ],
              if (widget.submitting) ...[
                Text(context.tr('等待服务器确认…')),
                const SizedBox(height: 6),
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 6),
              ],
              if (approval)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (showDeny)
                      OutlinedButton(
                        onPressed: canRespond
                            ? () => widget.onRespond('deny')
                            : null,
                        child: Text(context.tr('拒绝')),
                      ),
                    if (showOnce)
                      FilledButton(
                        onPressed: canRespond
                            ? () => widget.onRespond('once')
                            : null,
                        child: Text(context.tr('仅允许本次')),
                      ),
                    if (canPermanent)
                      OutlinedButton(
                        onPressed: !canRespond
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(context.tr('确认永久授权？')),
                                    content: Text(
                                      context.l10n.format(
                                        '同类操作后续可能不再询问。授权范围与撤销方式由服务端控制。\n{0}',
                                        {
                                          '0': text(
                                            data['permission_key'] ??
                                                data['description'] ??
                                                data['question'],
                                          ),
                                        },
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(context.tr('取消')),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(context.tr('永久允许')),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && mounted) {
                                  widget.onRespond('always');
                                }
                              },
                        child: Text(context.tr('永久允许')),
                      ),
                    for (final choice in extraApprovalChoices)
                      ActionChip(
                        label: Text(choice),
                        onPressed: canRespond
                            ? () => widget.onRespond(choice)
                            : null,
                      ),
                  ],
                )
              else if (questionSet != null)
                StructuredInteractionCard(
                  questionSet: questionSet,
                  enabled: canRespond,
                  submitting: widget.submitting,
                  onSubmit: widget.onRespond,
                )
              else ...[
                if (choices.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final choice in choices)
                        ActionChip(
                          label: Text(choice),
                          onPressed: canRespond
                              ? () => widget.onRespond(choice)
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                TextField(
                  controller: _field,
                  enabled: canRespond,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submitText(),
                  decoration: InputDecoration(
                    hintText: context.tr('补充说明'),
                    suffixIcon: IconButton(
                      tooltip: context.tr('提交说明'),
                      icon: const Icon(Icons.send_rounded),
                      onPressed: canRespond && _field.text.trim().isNotEmpty
                          ? _submitText
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
