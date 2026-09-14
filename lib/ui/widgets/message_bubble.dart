import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models.dart';
import '../theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});
  final ChatMessage message;
  Future<void> _openLink(BuildContext context, String? href) async {
    final uri = Uri.tryParse(href ?? '');
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        !uri.hasAuthority) {
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('打开外部链接？'),
        content: SelectableText(uri.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('在浏览器打开'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!opened && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
        }
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法打开链接')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!message.visible) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme, user = message.role == 'user';
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        child: Align(
          alignment: user ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: user ? 620 : 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!user && message.content.trim().isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        EkkoMark(size: 20),
                        SizedBox(width: 9),
                        Text(
                          'Ekko',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                Container(
                  key: ValueKey('message-surface:${message.id}'),
                  padding: message.content.trim().isNotEmpty
                      ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                      : EdgeInsets.zero,
                  decoration: message.content.trim().isNotEmpty
                      ? BoxDecoration(
                          color: user
                              ? colors.primaryContainer.withValues(alpha: .42)
                              : colors.surfaceContainerLow.withValues(
                                  alpha: .8,
                                ),
                          borderRadius: BorderRadius.circular(20),
                        )
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.reasoning.isNotEmpty)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          childrenPadding: const EdgeInsets.only(bottom: 4),
                          title: Text(
                            message.pending ? '思考中…' : '思考过程',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          children: [
                            SelectableText(
                              message.reasoning,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      if (message.content.trim().isNotEmpty &&
                          (user || message.pending))
                        SelectableText(
                          message.content,
                          style: const TextStyle(fontSize: 16, height: 1.5),
                        )
                      else if (message.content.trim().isNotEmpty)
                        MarkdownBody(
                          data: message.content,
                          selectable: true,
                          softLineBreak: true,
                          onTapLink: (_, href, _) => _openLink(context, href),
                          // Never fetch model-provided remote images: prevents tracking/IP leakage.
                          imageBuilder: (_, _, _) => Text(
                            '[图片附件请在 Studio 查看]',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(
                                Theme.of(context),
                              ).copyWith(
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
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                codeblockPadding: const EdgeInsets.all(12),
                                blockSpacing: 8,
                              ),
                        ),
                    ],
                  ),
                ),
                if (!user && !message.pending && message.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: IconButton(
                      tooltip: '复制回答',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: message.content));
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text('已复制回答')));
                      },
                      icon: Icon(
                        Icons.copy_outlined,
                        size: 17,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
