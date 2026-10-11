import 'package:flutter/material.dart';

import '../../data/structured_interaction.dart';
import '../../l10n.dart';

class StructuredInteractionCard extends StatefulWidget {
  const StructuredInteractionCard({
    super.key,
    required this.questionSet,
    required this.enabled,
    required this.submitting,
    required this.onSubmit,
  });

  final StructuredQuestionSet questionSet;
  final bool enabled;
  final bool submitting;
  final ValueChanged<String> onSubmit;

  @override
  State<StructuredInteractionCard> createState() =>
      _StructuredInteractionCardState();
}

class _StructuredInteractionCardState extends State<StructuredInteractionCard> {
  final _selected = <String, Set<String>>{};
  final _fields = <String, TextEditingController>{};
  String? _error;

  @override
  void initState() {
    super.initState();
    _resetFields();
  }

  @override
  void didUpdateWidget(covariant StructuredInteractionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameQuestions(oldWidget.questionSet, widget.questionSet)) {
      _resetFields();
    }
  }

  bool _sameQuestions(StructuredQuestionSet a, StructuredQuestionSet b) {
    if (a.questions.length != b.questions.length) return false;
    for (var index = 0; index < a.questions.length; index++) {
      if (a.questions[index].id != b.questions[index].id) return false;
    }
    return true;
  }

  void _resetFields() {
    for (final field in _fields.values) {
      field.dispose();
    }
    _fields.clear();
    _selected.clear();
    _error = null;
    for (final question in widget.questionSet.questions.where(
      (q) => q.isOpen,
    )) {
      _fields[question.id] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  bool _complete() => widget.questionSet.questions.every((question) {
    if (question.isOpen) return _fields[question.id]!.text.trim().isNotEmpty;
    return _selected[question.id]?.isNotEmpty == true;
  });

  void _submit() {
    if (!widget.enabled || widget.submitting) return;
    if (!_complete()) {
      setState(() => _error = context.tr('请完成所有问题后再提交'));
      return;
    }
    final answers = <String, dynamic>{};
    for (final question in widget.questionSet.questions) {
      if (question.isOpen) {
        answers[question.id] = _fields[question.id]!.text.trim();
      } else if (question.multiSelect) {
        answers[question.id] = _selected[question.id]!.toList();
      } else {
        answers[question.id] = _selected[question.id]!.single;
      }
    }
    setState(() => _error = null);
    widget.onSubmit(widget.questionSet.encodeResponses(answers));
  }

  void _select(StructuredQuestion question, String value) {
    setState(() {
      final selected = _selected.putIfAbsent(question.id, () => <String>{});
      if (question.multiSelect) {
        selected.contains(value) ? selected.remove(value) : selected.add(value);
      } else {
        selected
          ..clear()
          ..add(value);
      }
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = widget.questionSet.questions.where((question) {
      if (question.isOpen) return _fields[question.id]!.text.trim().isNotEmpty;
      return _selected[question.id]?.isNotEmpty == true;
    }).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.view_list_rounded, size: 17, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              context.tr('请逐项回答'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '$completed/${widget.questionSet.questions.length}',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (
          var index = 0;
          index < widget.questionSet.questions.length;
          index++
        )
          _question(context, widget.questionSet.questions[index], index + 1),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: widget.enabled && !widget.submitting ? _submit : null,
            icon: widget.submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, size: 17),
            label: Text(
              widget.submitting ? context.tr('等待服务器确认…') : context.tr('提交回答'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _question(
    BuildContext context,
    StructuredQuestion question,
    int index,
  ) {
    final colors = Theme.of(context).colorScheme;
    final selected = _selected[question.id] ?? const <String>{};
    return Padding(
      padding: EdgeInsets.only(
        bottom: index == widget.questionSet.questions.length ? 0 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$index. ${question.question}',
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
          ),
          const SizedBox(height: 6),
          if (question.isOpen)
            TextField(
              controller: _fields[question.id],
              enabled: widget.enabled && !widget.submitting,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                hintText: context.tr('输入你的回答…'),
                filled: true,
                fillColor: colors.surface,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            )
          else
            Wrap(
              spacing: 7,
              runSpacing: 6,
              children: [
                for (final choice in question.choices)
                  FilterChip(
                    selected: selected.contains(choice.value),
                    onSelected: widget.enabled && !widget.submitting
                        ? (_) => _select(question, choice.value)
                        : null,
                    avatar: choice.recommended
                        ? Icon(
                            Icons.star_rounded,
                            size: 15,
                            color: colors.primary,
                          )
                        : null,
                    label: Text(choice.label),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: true,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
