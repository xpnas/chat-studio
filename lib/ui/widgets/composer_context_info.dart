import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/context_usage.dart';
import '../../data/studio_api.dart';
import '../../l10n.dart';
import '../../state/app_controller.dart';

/// A quiet, session-scoped readout. Group rooms have no shared context window
/// in Studio and must not accidentally show the last single chat's usage.
class ComposerContextInfo extends StatefulWidget {
  const ComposerContextInfo({
    super.key,
    required this.controller,
    required this.input,
  });
  final AppController controller;
  final TextEditingController input;
  @override
  State<ComposerContextInfo> createState() => _ComposerContextInfoState();
}

class _ComposerContextInfoState extends State<ComposerContextInfo> {
  Object? _scope;
  int? _limit;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _load();
  }

  @override
  void didUpdateWidget(ComposerContextInfo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _scope = null;
    }
    _load();
  }

  void _changed() {
    _load();
    if (mounted) setState(() {});
  }

  void _load() {
    final c = widget.controller;
    final api = c.api;
    final provider = c.selectedModel?.provider ?? c.current?.provider;
    final model = c.selectedModel?.id ?? c.current?.model;
    final scope = (api, c.profile, c.sessionId, provider, model);
    if (scope == _scope) return;
    _scope = scope;
    _limit = null;
    if (api == null || c.sessionId == null) return;
    unawaited(_fetch(api, scope, provider, model));
  }

  Future<void> _fetch(
    StudioApi api,
    Object scope,
    String? provider,
    String? model,
  ) async {
    try {
      final limit = await api.contextLength(provider: provider, model: model);
      if (mounted && _scope == scope) setState(() => _limit = limit);
    } catch (_) {
      // No invented window size and no disruptive chat error for old servers.
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.input,
        builder: (context, input, _) {
          if (input.text.isNotEmpty || widget.controller.sessionId == null) {
            return const SizedBox.shrink();
          }
          final used = widget.controller.timeline.contextUsage.used;
          final limit = _limit;
          final colors = Theme.of(context).colorScheme;
          final ratio = limit == null ? 0.0 : (used / limit).clamp(0.0, 1.0);
          final label = limit == null
              ? context.l10n.format('上下文 {0} · 上限未知', {
                  '0': ContextUsage.format(used),
                })
              : context.l10n.format('{0} / {1} · 剩余 {2}', {
                  '0': ContextUsage.format(used),
                  '1': ContextUsage.format(limit),
                  '2': ContextUsage.format((limit - used).clamp(0, limit)),
                });
          return Padding(
            key: const Key('composer-context-info'),
            padding: const EdgeInsets.fromLTRB(8, 3, 8, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: context.l10n.format('上下文已用 {0} tokens，上限 {1} tokens', {
                  '0': used,
                  '1': limit ?? context.tr('未知'),
                }),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        color: ratio > .8
                            ? colors.error
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    if (limit != null) ...[
                      const SizedBox(height: 3),
                      SizedBox(
                        width: 52,
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 2,
                          borderRadius: BorderRadius.circular(2),
                          color: ratio > .8
                              ? colors.error
                              : ratio > .6
                              ? colors.tertiary
                              : colors.outline,
                          backgroundColor: colors.outlineVariant.withValues(
                            alpha: .4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
}
