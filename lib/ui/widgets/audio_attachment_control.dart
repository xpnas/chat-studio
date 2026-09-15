import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';

class AudioAttachmentControl extends StatefulWidget {
  const AudioAttachmentControl({
    super.key,
    required this.file,
    required this.controller,
  });
  final MessageAttachment file;
  final AppController controller;
  @override
  State<AudioAttachmentControl> createState() => _AudioAttachmentControlState();
}

class _AudioAttachmentControlState extends State<AudioAttachmentControl> {
  bool showText = true;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller.speech,
      widget.controller.transcription,
    ]),
    builder: (context, _) {
      final c = widget.controller, file = widget.file;
      final id = c.audioAttachmentId(file);
      final active = c.speech.activeId == id;
      final transcribing = c.transcription.activeId == id;
      final result = c.transcription.resultFor(id),
          error = c.transcription.errorFor(id);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                key: ValueKey('play-audio:${file.path}'),
                onPressed: () => c.playAudioAttachment(file),
                icon: Icon(
                  active ? Icons.stop_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(
                  active ? (c.speech.loading ? '取消加载语音' : '停止播放') : '播放语音',
                ),
              ),
              TextButton(
                key: ValueKey('transcribe-audio:${file.path}'),
                onPressed: () {
                  if (result != null) {
                    setState(() => showText = !showText);
                  } else {
                    setState(() => showText = true);
                    c.transcribeAudioAttachment(file);
                  }
                },
                child: Text(
                  transcribing
                      ? '取消转文字'
                      : result != null
                      ? (showText ? '收起文字' : '显示文字')
                      : error != null
                      ? '重试转文字'
                      : '转文字',
                ),
              ),
            ],
          ),
          if (transcribing)
            Text(c.transcription.phase, style: const TextStyle(fontSize: 12)),
          if (error != null)
            Text(
              error,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          if (result != null && showText) ...[
            const Text('语音转文字 · 识别结果仅供参考', style: TextStyle(fontSize: 11)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  result,
                  key: ValueKey('transcript:${file.path}'),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}
