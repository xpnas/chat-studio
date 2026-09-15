import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../state/app_controller.dart';
import 'stable_markdown.dart';
import 'attachment_tile.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models.dart';
import '../../data/message_file_reference.dart';
import '../theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.controller,
    this.anchorKey,
    this.onRetry,
  });
  final AppController? controller;
  final Key Function(int)? anchorKey;
  final VoidCallback? onRetry;
  final ChatMessage message;
  Future<void> _openLink(BuildContext context, String? href) async {
    final file = messageFileReference(
      href ?? '',
      server: controller?.api?.address.uri,
    );
    if (file != null && controller?.api != null) {
      if (file.isAudio) {
        controller!.playAudioAttachment(file);
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (_) => AttachmentViewer(file: file, controller: controller!),
      );
      return;
    }
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
                if (!user && message.bodyText.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        if (message.role == 'command')
                          const Icon(Icons.terminal_rounded, size: 20)
                        else
                          const EkkoMark(size: 20),
                        const SizedBox(width: 9),
                        Text(
                          message.role == 'command' ? '命令' : 'Ekko',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                Container(
                  key: ValueKey('message-surface:${message.id}'),
                  padding: message.bodyText.isNotEmpty
                      ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                      : EdgeInsets.zero,
                  decoration: message.bodyText.isNotEmpty
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
                      if (message.tools.isNotEmpty)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          title: Text(
                            message.tools.every((t) => t.status == 'done')
                                ? '${message.tools.length} 项操作已完成'
                                : '${message.tools.length} 项工具操作${message.tools.any((t) => t.status == 'running') ? ' · 执行中' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                          children: [
                            for (final tool in message.tools)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    tool.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      if (message.bodyText.isNotEmpty)
                        if (user)
                          SelectableText(
                            message.bodyText,
                            style: const TextStyle(fontSize: 16, height: 1.5),
                          )
                        else
                          StableMarkdown(
                            data: message.bodyText,
                            anchorKey: anchorKey,
                            audioLinkBuilder: (href, label) {
                              final file = messageFileReference(
                                href,
                                server: controller?.api?.address.uri,
                                label: label,
                              );
                              if (file?.isAudio != true ||
                                  controller?.api == null) {
                                return null;
                              }
                              return AttachmentTile(
                                key: ValueKey(
                                  'audio-link:${controller!.profile}:${file!.path}',
                                ),
                                file: file,
                                controller: controller!,
                              );
                            },
                            imageBuilder: (uri, title, alt) {
                              final file = messageFileReference(
                                uri.toString(),
                                server: controller?.api?.address.uri,
                                label: alt,
                              );
                              if (file != null && controller?.api != null) {
                                return AttachmentTile(
                                  key: ValueKey(
                                    '${controller!.profile}:${file.path}',
                                  ),
                                  file: file,
                                  controller: controller!,
                                );
                              }
                              return TextButton.icon(
                                onPressed: () =>
                                    _openLink(context, uri.toString()),
                                icon: const Icon(Icons.image_outlined),
                                label: Text(
                                  '${alt?.isNotEmpty == true ? alt : '外部图片'} · 点击打开',
                                ),
                              );
                            },
                            onTapLink: (_, href, _) => _openLink(context, href),
                          ),
                      if (controller != null)
                        for (final file in message.attachments)
                          AttachmentTile(
                            key: ValueKey(
                              '${controller!.api?.address.value}|${controller!.profile}|${file.path}',
                            ),
                            file: file,
                            controller: controller!,
                          ),
                      if (message.delivery.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Row(
                            children: [
                              Icon(
                                message.delivery == 'failed'
                                    ? Icons.error_outline
                                    : message.delivery == 'uncertain'
                                    ? Icons.sync_rounded
                                    : Icons.check_rounded,
                                size: 13,
                                color: message.delivery == 'failed'
                                    ? colors.error
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  switch (message.delivery) {
                                    'sending' => '正在发送 · 等待服务端确认',
                                    'uncertain' => '正在核对发送状态 · 不会自动重发',
                                    'failed' =>
                                      message.failure.isEmpty
                                          ? '本次生成失败'
                                          : message.failure,
                                    'stopped' => '已停止生成',
                                    _ => message.delivery,
                                  },
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: message.delivery == 'failed'
                                        ? colors.error
                                        : colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (message.delivery == 'failed' &&
                                  onRetry != null)
                                TextButton(
                                  onPressed: onRetry,
                                  child: const Text(
                                    '编辑后重试',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                              if (message.delivery == 'uncertain' &&
                                  controller != null)
                                TextButton(
                                  onPressed: controller!.reconnect,
                                  child: const Text(
                                    '核对',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ),
                            ],
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
