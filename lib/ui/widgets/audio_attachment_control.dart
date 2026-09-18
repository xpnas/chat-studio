import '../../l10n.dart';
import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';

class AudioAttachmentControl extends StatelessWidget {
  const AudioAttachmentControl({
    super.key,
    required this.file,
    required this.controller,
  });
  final MessageAttachment file;
  final AppController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.speech,
    builder: (context, _) {
      final active =
          controller.speech.activeId == controller.audioAttachmentId(file);
      return TextButton.icon(
        key: ValueKey('play-audio:${file.path}'),
        onPressed: () => controller.playAudioAttachment(file),
        icon: Icon(
          active ? Icons.stop_rounded : Icons.play_arrow_rounded,
          size: 20,
        ),
        label: Text(
          active
              ? (controller.speech.loading
                    ? context.tr("取消加载语音")
                    : context.tr("停止播放"))
              : context.tr("播放语音"),
        ),
      );
    },
  );
}
