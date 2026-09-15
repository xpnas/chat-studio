import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Split only at safe block boundaries. Fenced code and multiline lists remain
/// intact. The trailing block alone is parsed repeatedly while it is streaming.
List<String> markdownSegments(String source) {
  final lines = source.split('\n');
  final blocks = <String>[];
  final buffer = <String>[];
  String? fence;
  var list = false;
  void flush() {
    final value = buffer.join('\n').trimRight();
    if (value.isNotEmpty) blocks.add(value);
    buffer.clear();
    list = false;
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    final opening = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed)?.group(1);
    if (fence == null && opening != null) {
      if (buffer.isNotEmpty && !list) flush();
      fence = opening;
    } else if (fence != null && trimmed.startsWith(fence)) {
      buffer.add(line);
      if (!list) flush();
      fence = null;
      continue;
    }
    buffer.add(line);
    if (fence != null) continue;
    if (RegExp(r'^\s*(?:[-*+] |\d+[.)] )').hasMatch(line)) list = true;
    if (line.trim().isEmpty) {
      final next = i + 1 < lines.length ? lines[i + 1] : '';
      if (list &&
          (next.startsWith(' ') ||
              RegExp(r'^(?:[-*+] |\d+[.)] )').hasMatch(next) ||
              next.isEmpty)) {
        continue;
      }
      flush();
    }
  }
  flush();
  return blocks;
}

class StableMarkdown extends StatefulWidget {
  const StableMarkdown({
    super.key,
    required this.data,
    this.onTapLink,
    this.anchorKey,
  });
  final String data;
  final void Function(String?, String?, String?)? onTapLink;
  final Key Function(int)? anchorKey;
  @override
  State<StableMarkdown> createState() => _StableMarkdownState();
}

class _StableMarkdownState extends State<StableMarkdown> {
  final _cache = <int, (String, Widget)>{};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cache.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final blocks = markdownSegments(widget.data);
    _cache.removeWhere((index, _) => index >= blocks.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            key: widget.anchorKey?.call(i) ?? ValueKey(i),
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _cache[i]?.$1 == blocks[i]
                ? _cache[i]!.$2
                : (_cache[i] = (
                    blocks[i],
                    MarkdownBody(
                      data: blocks[i],
                      selectable: true,
                      softLineBreak: true,
                      onTapLink: widget.onTapLink,
                      imageBuilder: (_, _, _) => Text(
                        '[外部图片未自动加载]',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                        p: TextStyle(
                          fontSize: 16,
                          height: 1.45,
                          color: colors.onSurface,
                        ),
                        code: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: colors.primary,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: colors.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        codeblockPadding: const EdgeInsets.all(12),
                        blockSpacing: 8,
                        tableColumnWidth: const IntrinsicColumnWidth(),
                      ),
                    ),
                  )).$2,
          ),
      ],
    );
  }
}
