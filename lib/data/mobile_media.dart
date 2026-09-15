import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

class LocalAttachment {
  const LocalAttachment({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
  });
  final String path, name, mimeType;
  final int size;
  bool get isImage => mimeType.startsWith('image/');
  static const maxBytes = 20 * 1024 * 1024;
  static const maxCount = 5;
  static const maxTotalBytes = 40 * 1024 * 1024;
  static Future<LocalAttachment> fromPath(String path, String name) async =>
      LocalAttachment(
        path: path,
        name: name,
        size: await File(path).length(),
        mimeType: lookupMimeType(name) ?? 'application/octet-stream',
      );
}

abstract class MediaAccess {
  Future<List<LocalAttachment>> pick({required bool images});
  Future<void> startRecording();
  Future<String?> stopRecording();
  Future<void> cancelRecording();
  Future<void> dispose();
}

abstract class AudioLevelSource {
  Stream<double> get audioLevels;
}

class NativeMediaAccess implements MediaAccess, AudioLevelSource {
  @override
  Stream<double> get audioLevels => (_recorder ??= AudioRecorder())
      .onAmplitudeChanged(const Duration(milliseconds: 120))
      .map(
        (amplitude) => amplitude.current.isFinite
            ? ((amplitude.current + 60) / 60).clamp(0.0, 1.0)
            : 0.0,
      );

  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  AudioRecorder? _recorder;
  String? _audioPath;
  @override
  Future<List<LocalAttachment>> pick({required bool images}) async {
    if (images) {
      final files = await ImagePicker().pickMultiImage(
        requestFullMetadata: false,
      );
      return Future.wait(
        files.map((f) => LocalAttachment.fromPath(f.path, f.name)),
      );
    }
    final files = await FilePicker.pickFiles();
    return Future.wait(
      files
          .where((f) => f.path != null)
          .map((f) => LocalAttachment.fromPath(f.path!, f.name)),
    );
  }

  @override
  Future<void> startRecording() => _serial(() async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      throw StateError('麦克风权限被拒绝，请在系统设置中允许 Ekko 使用麦克风');
    }
    final temp = await getTemporaryDirectory();
    _audioPath = '${temp.path}/ekko-voice-${const Uuid().v4()}.wav';
    await recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _audioPath!,
    );
  });

  @override
  Future<String?> stopRecording() => _serial(() async => _recorder?.stop());
  @override
  Future<void> cancelRecording() => _serial(_cancelRecording);
  Future<void> _cancelRecording() async {
    try {
      await _recorder?.cancel();
    } finally {
      final path = _audioPath;
      _audioPath = null;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  @override
  Future<void> dispose() => _serial(() async {
    try {
      await _cancelRecording();
    } finally {
      await _recorder?.dispose();
    }
  });
}
