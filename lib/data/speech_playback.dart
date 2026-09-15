import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'studio_api.dart';

abstract class SpeechOutput {
  Future<void> play(Uint8List bytes, String mime);
  Future<void> stop();
  Future<void> dispose();
  Stream<void> get completed;
}

abstract class FileSpeechOutput {
  Future<void> playFile(String path, String mime);
}

class NativeSpeechOutput implements SpeechOutput, FileSpeechOutput {
  final _player = AudioPlayer();
  @override
  Stream<void> get completed => _player.onPlayerComplete;
  @override
  Future<void> play(Uint8List bytes, String mime) =>
      _player.play(BytesSource(bytes, mimeType: mime));
  @override
  Future<void> playFile(String path, String mime) =>
      _player.play(DeviceFileSource(path, mimeType: mime));
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

/// One speaker per App, latest request wins; never auto-retries after reconnect.
class SpeechPlayback extends ChangeNotifier {
  SpeechPlayback({
    SpeechOutput Function()? outputFactory,
    Future<Directory> Function()? tempDirectory,
  }) : _factory = outputFactory ?? NativeSpeechOutput.new,
       _tempDirectory = tempDirectory ?? getTemporaryDirectory;
  final Future<Directory> Function() _tempDirectory;
  Directory? _audioDirectory;
  final SpeechOutput Function() _factory;
  SpeechOutput? _output;
  StreamSubscription<void>? _completion;
  Completer<void>? _cancel;
  Future<void> _serial = Future.value();
  int _revision = 0;
  bool _disposed = false;
  String? activeId, error;
  bool loading = false;
  Future<void> stop() async {
    ++_revision;
    if (_cancel?.isCompleted == false) _cancel!.complete();
    activeId = null;
    loading = false;
    error = null;
    final directory = _audioDirectory;
    _audioDirectory = null;
    if (!_disposed) notifyListeners();
    _serial = _serial
        .then((_) async {
          await _output?.stop();
          if (directory != null && await directory.exists()) {
            await directory.delete(recursive: true);
          }
        })
        .catchError((Object _) {});
    await _serial;
  }

  Future<void> speak(StudioApi api, String id, String text) =>
      _start(id, (cancel, revision) async {
        final audio = await api.synthesizeSpeech(text, cancel: cancel);
        return () => _output!.play(audio.$1, audio.$2);
      });

  Future<void> playAttachment(
    StudioApi api,
    String id,
    MessageAttachment file,
  ) => _start(id, (cancel, revision) async {
    Directory? directory;
    var retained = false;
    try {
      final root = await _tempDirectory();
      if (_disposed || revision != _revision) throw const ApiException('已取消播放');
      directory = await root.createTemp('ekko-audio-');
      final downloaded = await api.downloadAttachment(
        file,
        directory,
        cancel: cancel,
      );
      if (_disposed || revision != _revision) throw const ApiException('已取消播放');
      final extension = switch (file.audioMime) {
        'audio/mpeg' => 'mp3',
        'audio/wav' || 'audio/x-wav' => 'wav',
        'audio/ogg' => 'ogg',
        'audio/mp4' || 'audio/x-m4a' => 'm4a',
        'audio/aac' => 'aac',
        'audio/flac' => 'flac',
        _ => 'audio',
      };
      final local = await downloaded.rename(
        '${directory.path}/reply.$extension',
      );
      if (_disposed || revision != _revision) throw const ApiException('已取消播放');
      _audioDirectory = directory;
      retained = true;
      return () async {
        if (_output is! FileSpeechOutput) {
          throw const ApiException('当前播放器不支持文件播放');
        }
        await (_output as FileSpeechOutput).playFile(
          local.path,
          file.audioMime,
        );
      };
    } finally {
      if (!retained && directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    }
  });

  Future<void> _start(
    String id,
    Future<Future<void> Function()> Function(Future<void>, int) prepare,
  ) async {
    final stopping = stop();
    final requestedRevision = _revision;
    await stopping;
    if (_disposed || requestedRevision != _revision) return;
    final revision = ++_revision;
    _cancel = Completer<void>();
    activeId = id;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final play = await prepare(_cancel!.future, revision);
      if (_disposed || revision != _revision) return;
      _output ??= _factory();
      _completion ??= _output!.completed.listen((_) {
        if (!_disposed && !loading) unawaited(stop());
      });
      _serial = _serial.then((_) async {
        if (!_disposed && revision == _revision) await play();
      });
      await _serial;
      if (!_disposed && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    } catch (e) {
      if (!_disposed && revision == _revision) {
        await stop();
        if (!_disposed && _revision == revision + 1) {
          error = '播放失败：$e';
          notifyListeners();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      stop().whenComplete(() async {
        await _completion?.cancel();
        await _output?.dispose();
      }),
    );
    super.dispose();
  }
}
