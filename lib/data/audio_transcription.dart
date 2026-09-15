import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'studio_api.dart';

/// Audio-only, explicit STT. Results are local display state, never messages
/// sent to the AI. One cancellable request, bounded per-account/session cache.
class AudioTranscription extends ChangeNotifier {
  AudioTranscription({Future<Directory> Function()? tempDirectory})
    : _tempDirectory = tempDirectory ?? getTemporaryDirectory;
  final Future<Directory> Function() _tempDirectory;
  final _results = <String, String>{};
  final _errors = <String, String>{};
  String? activeId;
  String phase = '';
  Completer<void>? _cancel;
  int _revision = 0;
  bool _disposed = false;
  String? resultFor(String id) => _results[id];
  String? errorFor(String id) => _errors[id];
  void cancel() {
    ++_revision;
    if (_cancel?.isCompleted == false) _cancel!.complete();
    _cancel = null;
    activeId = null;
    phase = '';
    if (!_disposed) notifyListeners();
  }

  void clear() {
    _results.clear();
    _errors.clear();
    cancel();
  }

  Future<void> transcribe(
    StudioApi api,
    String id,
    MessageAttachment file,
  ) async {
    if (_disposed ||
        !file.isAudio ||
        _results.containsKey(id) ||
        activeId == id) {
      return;
    }
    cancel();
    final revision = ++_revision, profile = api.profile, credential = api.token;
    final canceler = Completer<void>();
    _cancel = canceler;
    bool valid() =>
        !_disposed &&
        revision == _revision &&
        profile == api.profile &&
        credential == api.token;
    activeId = id;
    phase = '检查语音识别配置';
    _errors.remove(id);
    notifyListeners();
    Directory? directory;
    try {
      final status = await api.request('/api/studio/stt/profile-status');
      if (!valid()) return;
      final provider = text(status['activeProvider']);
      if (!flag(status['configured']) ||
          provider.isEmpty ||
          provider == 'browser') {
        throw const ApiException('请先在 Web 当前 Profile 配置语音识别 STT（不是 TTS）');
      }
      const limit =
          49 * 1024 * 1024; // Official server multipart total <= 50 MB.
      if (file.size > limit) {
        throw const ApiException('音频过大，转文字最多支持 49 MB，请先分段');
      }
      final root = await _tempDirectory();
      if (!valid()) return;
      directory = await root.createTemp('chatstudio-transcribe-');
      phase = '读取语音';
      notifyListeners();
      final audio = await api.downloadAttachment(
        file,
        directory,
        maxBytes: limit,
        cancel: canceler.future,
      );
      if (!valid()) return;
      phase = '正在转文字';
      notifyListeners();
      final name = file.name.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
      final result = await api.transcribe(
        audio.path,
        provider,
        fileName: name.isEmpty ? 'audio' : name,
        mimeType: file.audioMime,
        maxBytes: limit,
        cancel: canceler.future,
      );
      if (!valid()) return;
      while (_results.length >= 16) {
        _results.remove(_results.keys.first);
      }
      _results[id] = result;
    } catch (e) {
      if (valid()) {
        while (_errors.length >= 16) {
          _errors.remove(_errors.keys.first);
        }
        _errors[id] = '$e';
      }
    } finally {
      if (directory != null) {
        try {
          if (await directory.exists()) await directory.delete(recursive: true);
        } catch (_) {
          /* App temporary cache can be reclaimed by OS. */
        }
      }
      if (!_disposed && revision == _revision) {
        activeId = null;
        phase = '';
        _cancel = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    super.dispose();
  }
}
