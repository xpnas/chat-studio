import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/server_address.dart';
import 'models.dart';
import 'mobile_media.dart';

class StudioApi {
  StudioApi(this.address, {http.Client? client})
    : _client = client ?? http.Client();
  final ServerAddress address;
  final http.Client _client;
  String token = '';
  String profile = 'default';
  void Function()? onUnauthorized;
  final _images = <String, Uint8List>{};
  int _imageBytes = 0;

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool public = false,
  }) async {
    final uri = address.uri.replace(path: path, queryParameters: query);
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (!public) 'Authorization': 'Bearer $token',
      if (!public) 'X-Hermes-Profile': profile,
    });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(const Duration(seconds: 25));
      Map<String, dynamic> data;
      try {
        data = asMap(jsonDecode(utf8.decode(response.bodyBytes)));
      } on FormatException {
        throw ApiException('服务返回了非 JSON 内容，请检查地址和反向代理', response.statusCode);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 && !public) onUnauthorized?.call();
        throw ApiException(
          text(data['error']).isEmpty
              ? '请求失败 (${response.statusCode})'
              : text(data['error']),
          response.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiException('连接超时，请检查服务器是否在线');
    } on SocketException {
      throw const ApiException('无法连接服务器，请检查网络、地址和局域网权限');
    } on http.ClientException {
      throw const ApiException('网络连接失败，请检查地址与 HTTPS 证书');
    }
  }

  Future<Map<String, dynamic>> _multipart(
    String path,
    List<http.MultipartFile> files, {
    Map<String, String> fields = const {},
    Future<void>? cancel,
    void Function(double)? onProgress,
  }) async {
    final abort = Completer<void>();
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    cancel?.then((_) => stop());
    final request =
        ProgressMultipartRequest(
            'POST',
            address.uri.replace(path: path),
            abortTrigger: abort.future,
            onProgress: onProgress,
          )
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'X-Hermes-Profile': profile,
            'Accept': 'application/json',
          })
          ..fields.addAll(fields)
          ..files.addAll(files);
    try {
      final response =
          await (() async => http.Response.fromStream(
            await _client.send(request),
          ))().timeout(
            const Duration(seconds: 120),
            onTimeout: () {
              stop();
              throw const ApiException('上传或识别超时，请重试');
            },
          );
      if (response.statusCode == 401) onUnauthorized?.call();
      Map<String, dynamic> data;
      try {
        data = asMap(jsonDecode(utf8.decode(response.bodyBytes)));
      } on FormatException {
        throw ApiException(
          '服务返回了无效内容 (${response.statusCode})',
          response.statusCode,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          text(data['error']).isEmpty
              ? '上传失败 (${response.statusCode})'
              : text(data['error']),
          response.statusCode,
        );
      }
      return data;
    } on http.RequestAbortedException {
      throw const ApiException('已取消');
    } on SocketException {
      throw const ApiException('网络连接失败，请重试');
    } on http.ClientException {
      throw const ApiException('上传连接失败，请检查网络和证书');
    }
  }

  Future<List<Map<String, dynamic>>> uploadAttachments(
    List<LocalAttachment> attachments, {
    Future<void>? cancel,
    void Function(double)? onProgress,
  }) async {
    if (attachments.isEmpty ||
        attachments.length > LocalAttachment.maxCount ||
        attachments.any(
          (f) => f.size <= 0 || f.size > LocalAttachment.maxBytes,
        ) ||
        attachments.fold<int>(0, (sum, f) => sum + f.size) >
            LocalAttachment.maxTotalBytes) {
      throw const ApiException('最多 5 个附件，单个不超过 20 MB，总计不超过 40 MB');
    }
    final scope = profile, credential = token;
    var canceled = false;
    cancel?.then((_) => canceled = true);
    final files = <http.MultipartFile>[];
    for (final file in attachments) {
      final part = await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: file.name,
      );
      if (part.length != file.size) throw const ApiException('附件已发生变化，请重新选择');
      files.add(part);
    }
    if (canceled || scope != profile || credential != token) {
      throw const ApiException('已取消：会话或 Profile 已变化');
    }
    final data = await _multipart(
      '/api/studio/uploads',
      files,
      cancel: cancel,
      onProgress: onProgress,
    );
    final rows = asList(data['files']).map(asMap).toList();
    if (rows.length != attachments.length ||
        rows.any((f) => text(f['path']).isEmpty)) {
      throw const ApiException('服务端未返回完整附件，请重试');
    }
    return List.generate(
      rows.length,
      (i) => {
        'type': attachments[i].isImage ? 'image' : 'file',
        'name': attachments[i].name,
        'path': text(rows[i]['path']),
        'media_type': attachments[i].mimeType,
        'size': attachments[i].size,
      },
    );
  }

  Future<String> transcribe(
    String path,
    String provider, {
    Future<void>? cancel,
    String fileName = 'voice.wav',
    String mimeType = 'audio/wav',
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    final scope = profile, credential = token;
    var canceled = false;
    cancel?.then((_) => canceled = true);
    final audio = await http.MultipartFile.fromPath(
      'audio',
      path,
      filename: fileName,
      contentType: http.MediaType.parse(mimeType),
    );
    if (audio.length > maxBytes) throw const ApiException('音频超出转文字大小限制，请先分段');
    if (canceled || scope != profile || credential != token) {
      throw const ApiException('已取消：会话或 Profile 已变化');
    }
    final data = await _multipart(
      '/api/studio/stt/transcribe',
      [audio],
      fields: {'provider': provider},
      cancel: cancel,
    );
    if (canceled || scope != profile || credential != token) {
      throw const ApiException('已取消：会话或 Profile 已变化');
    }
    final result = text(data['text']).trim();
    if (result.isEmpty) throw const ApiException('未识别到语音，请重试');
    return result;
  }

  /// Download to a unique temporary file, with bounded memory and backpressure.
  /// The caller owns cleanup after export; never writes to a server-supplied path.
  Future<File> downloadAttachment(
    MessageAttachment file,
    Directory directory, {
    Future<void>? cancel,
    void Function(int received, int? total)? onProgress,
    int? maxBytes,
  }) async {
    final scope = profile, credential = token;
    final abort = Completer<void>();
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    cancel?.then((_) => stop());
    final target = File('${directory.path}/download.part');
    final req =
        http.AbortableRequest(
            'GET',
            address.uri.replace(
              path: '/api/studio/files/download',
              queryParameters: {'path': file.path, 'name': file.name},
            ),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $credential',
            'X-Hermes-Profile': scope,
          });
    RandomAccessFile? output;
    final timer = Timer(const Duration(minutes: 30), stop);
    var success = false;
    void check() {
      if (abort.isCompleted || scope != profile || credential != token) {
        stop();
        throw const ApiException('下载已取消或登录状态已变化');
      }
    }

    try {
      check();
      final response = await _client
          .send(req)
          .timeout(const Duration(seconds: 45));
      if (response.statusCode == 401) onUnauthorized?.call();
      if (response.statusCode != 200) {
        stop();
        throw ApiException(
          response.statusCode == 403
              ? '没有权限下载此文件'
              : response.statusCode == 404
              ? '文件已失效或被删除'
              : '下载失败（${response.statusCode}）',
          response.statusCode,
        );
      }
      final total = response.contentLength;
      if (maxBytes != null && total != null && total > maxBytes) {
        throw const ApiException('音频过大，转文字最多支持 49 MB，请先分段');
      }
      output = await target.open(mode: FileMode.writeOnly);
      var received = 0;
      final clock = Stopwatch()..start();
      onProgress?.call(0, total);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        check();
        if (maxBytes != null && received + chunk.length > maxBytes) {
          throw const ApiException('音频过大，转文字最多支持 49 MB，请先分段');
        }
        await output.writeFrom(chunk);
        received += chunk.length;
        if (total != null && received > total) {
          throw const ApiException('下载大小与服务端声明不一致');
        }
        if (clock.elapsedMilliseconds >= 100) {
          onProgress?.call(received, total);
          clock.reset();
        }
      }
      check();
      if (total != null && received != total) {
        throw const ApiException('下载不完整，请重试');
      }
      await output.close();
      output = null;
      onProgress?.call(received, total);
      success = true;
      return target;
    } on TimeoutException {
      stop();
      throw const ApiException('下载超时，请检查网络后重试');
    } on http.RequestAbortedException {
      throw const ApiException('下载已取消');
    } on http.ClientException {
      throw const ApiException('下载连接中断，请重试');
    } on SocketException {
      throw const ApiException('无法连接下载服务器');
    } on FileSystemException {
      throw const ApiException('无法写入文件，请检查剩余存储空间');
    } finally {
      timer.cancel();
      stop();
      await output?.close();
      if (!success && await target.exists()) await target.delete();
    }
  }

  Future<Uint8List> attachmentBytes(
    MessageAttachment file, {
    bool thumbnail = false,
    Future<void>? cancel,
  }) async {
    // Never navigate to a URL or use arbitrary response headers as destinations.
    final scope = profile, credential = token;
    final key = '$scope|$credential|${file.path}|$thumbnail';
    final cached = thumbnail ? _images.remove(key) : null;
    if (cached != null) {
      _images[key] = cached;
      return cached;
    }
    final abort = Completer<void>();
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    cancel?.then((_) => stop());
    final request =
        http.AbortableRequest(
            'GET',
            address.uri.replace(
              path: '/api/studio/files/download',
              queryParameters: {
                'path': file.path,
                'name': file.name,
                if (thumbnail) 'variant': 'app-image',
              },
            ),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $credential',
            'X-Hermes-Profile': scope,
          });
    final limit = thumbnail ? 8 * 1024 * 1024 : 25 * 1024 * 1024;
    try {
      return await (() async {
        final response = await _client.send(request);
        if (response.statusCode == 401) onUnauthorized?.call();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          stop();
          throw ApiException(
            response.statusCode == 404
                ? '附件已失效或被删除'
                : response.statusCode == 403
                ? '没有权限查看此附件'
                : '附件读取失败 (${response.statusCode})',
            response.statusCode,
          );
        }
        if ((response.contentLength ?? 0) > limit) {
          stop();
          throw const ApiException('附件过大，请在 Studio 查看');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > limit) {
            stop();
            throw const ApiException('附件过大，请在 Studio 查看');
          }
          bytes.add(chunk);
        }
        if (scope != profile || credential != token) {
          throw const ApiException('会话已切换');
        }
        final result = bytes.takeBytes();
        if (thumbnail && result.isNotEmpty) {
          while (_images.isNotEmpty &&
              (_imageBytes + result.length > 12 * 1024 * 1024 ||
                  _images.length >= 12)) {
            _imageBytes -= _images.remove(_images.keys.first)!.length;
          }
          _images[key] = result;
          _imageBytes += result.length;
        }
        return result;
      })().timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          stop();
          throw const ApiException('附件读取超时，点击重试');
        },
      );
    } on http.RequestAbortedException {
      throw const ApiException('已取消读取附件');
    } on http.ClientException {
      throw const ApiException('附件下载连接失败');
    } on SocketException {
      throw const ApiException('无法连接附件服务器');
    }
  }

  /// Official profile/user configured TTS. No provider credentials in the App.
  Future<(Uint8List, String)> synthesizeSpeech(
    String text, {
    Future<void>? cancel,
  }) async {
    if (text.trim().isEmpty || text.length > 12000) {
      throw const ApiException('语音回复需为 1–12000 字符，请选择较短回复');
    }
    final scope = profile, credential = token;
    final abort = Completer<void>();
    void stop() {
      if (!abort.isCompleted) abort.complete();
    }

    cancel?.then((_) => stop());
    final req =
        http.AbortableRequest(
            'POST',
            address.uri.replace(path: '/api/studio/tts/synthesize'),
            abortTrigger: abort.future,
          )
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $credential',
            'X-Hermes-Profile': scope,
            'Content-Type': 'application/json',
            'Accept': 'audio/*, application/json',
          })
          ..body = jsonEncode({'text': text});
    try {
      return await (() async {
        final response = await _client.send(req);
        if (response.statusCode == 401) onUnauthorized?.call();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          stop();
          throw ApiException(
            '语音合成失败（${response.statusCode}），请在 Web 配置 TTS 服务',
            response.statusCode,
          );
        }
        const limit = 20 * 1024 * 1024;
        final mime = (response.headers['content-type'] ?? '').split(';').first;
        if (!mime.startsWith('audio/') ||
            (response.contentLength ?? 0) > limit) {
          stop();
          throw const ApiException('语音响应格式无效或文件过大');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > limit) {
            stop();
            throw const ApiException('语音文件超过 20 MB');
          }
          bytes.add(chunk);
        }
        if (scope != profile || credential != token || abort.isCompleted) {
          throw const ApiException('已取消语音回复');
        }
        if (bytes.isEmpty) throw const ApiException('服务端未返回音频');
        return (bytes.takeBytes(), mime);
      })().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          stop();
          throw const ApiException('语音合成超时');
        },
      );
    } on http.RequestAbortedException {
      throw const ApiException('已取消语音回复');
    } on http.ClientException {
      throw const ApiException('语音服务连接失败');
    } on SocketException {
      throw const ApiException('语音服务连接失败');
    }
  }

  Future<Map<String, dynamic>> login(
    String username,
    String password,
    String deviceId,
  ) => request(
    '/api/auth/app-login',
    method: 'POST',
    public: true,
    body: {
      'username': username.trim(),
      'password': password,
      'device_code': deviceId,
      'device_name': Platform.isIOS
          ? 'Chat Studio · iOS'
          : 'Chat Studio · Android',
      'device_brand': Platform.isIOS ? 'Apple' : 'Android',
      'device_model': 'Chat Studio',
    },
  );
  Future<Account> me() async =>
      Account.fromJson(asMap((await request('/api/auth/me'))['user']));
  Future<List<String>> profiles() async =>
      asList((await request('/api/app/profiles'))['profiles'])
          .map((p) => p is String ? p : text(asMap(p)['name']))
          .where((p) => p.isNotEmpty)
          .toList();
  Future<Map<String, dynamic>> models() =>
      request('/api/hermes/available-models', query: {'profile': profile});
  Future<Map<String, dynamic>> sessions({int offset = 0, String search = ''}) =>
      search.isNotEmpty
      ? request(
          '/api/studio/search/sessions',
          query: {'profile': profile, 'q': search, 'limit': '100'},
        )
      : request(
          '/api/studio/sessions',
          query: {'profile': profile, 'offset': '$offset', 'limit': '40'},
        );
  Future<MessagePage> messages(String id, {int offset = 0}) async {
    final data = await request(
      '/api/studio/sessions/conversations/${Uri.encodeComponent(id)}/messages/paginated',
      query: {'profile': profile, 'offset': '$offset', 'limit': '60'},
    );
    final rows = asList(data['messages']);
    return MessagePage(
      rows.map((m) => ChatMessage.fromJson(asMap(m))).toList(),
      integer(data['offset']) + rows.length,
      integer(data['total']),
      flag(data['hasMore']),
    );
  }

  // Contracts verified against official v1.0.3 api/hermes/{skills,skill-bundles}.ts.
  Future<List<Map<String, dynamic>>> commandSkills() async {
    final data = await request(
      '/api/hermes/skills',
      query: {'profile': profile},
    );
    final unique = <String, Map<String, dynamic>>{};
    for (final category in asList(data['categories'])) {
      for (final item in asList(asMap(category)['skills'])) {
        final skill = asMap(item);
        if (skill['enabled'] != false && text(skill['name']).isNotEmpty) {
          unique.putIfAbsent(text(skill['name']), () => skill);
        }
      }
    }
    return unique.values.toList();
  }

  Future<List<Map<String, dynamic>>> commandBundles() async => asList(
    (await request(
      '/api/hermes/bundles',
      query: {'profile': profile},
    ))['bundles'],
  ).map(asMap).toList();

  Future<Map<String, dynamic>> createCommandBundle(
    String name,
    String description,
    List<String> skills,
  ) async {
    final data = await request(
      '/api/hermes/bundles',
      method: 'POST',
      query: {'profile': profile},
      body: {'name': name, 'description': description, 'skills': skills},
    );
    final bundle = asMap(data['bundle']);
    if (text(bundle['commandName']).isEmpty) {
      throw const ApiException('服务端未返回 Bundle 命令名称');
    }
    return bundle;
  }

  Future<void> rename(String id, String title) async {
    await request(
      '/api/studio/sessions/${Uri.encodeComponent(id)}/rename',
      method: 'POST',
      body: {'title': title},
    );
  }

  Future<void> delete(String id) async {
    await request(
      '/api/studio/sessions/${Uri.encodeComponent(id)}',
      method: 'DELETE',
    );
  }

  Future<void> setReasoningEffort(String id, String effort) async {
    if (!reasoningEffortLabels.containsKey(effort)) {
      throw const ApiException('无效的思考深度');
    }
    await request(
      '/api/studio/sessions/${Uri.encodeComponent(id)}/reasoning-effort',
      method: 'POST',
      body: {'reasoningEffort': effort},
    );
  }

  Future<void> setModel(String id, ModelChoice model) async {
    await request(
      '/api/studio/sessions/${Uri.encodeComponent(id)}/model',
      method: 'POST',
      body: {
        'model': model.id,
        'provider': model.provider,
        if (model.apiMode.isNotEmpty) 'api_mode': model.apiMode,
      },
    );
  }

  Future<void> changePassword(String current, String replacement) async {
    await request(
      '/api/auth/change-password',
      method: 'POST',
      body: {'currentPassword': current, 'newPassword': replacement},
    );
  }

  Future<void> changeUsername(String password, String username) async {
    await request(
      '/api/auth/change-username',
      method: 'POST',
      body: {'currentPassword': password, 'newUsername': username},
    );
  }

  void close() {
    _images.clear();
    _imageBytes = 0;
    _client.close();
  }
}

class ProgressMultipartRequest extends http.MultipartRequest
    with http.Abortable {
  ProgressMultipartRequest(
    super.method,
    super.url, {
    this.abortTrigger,
    this.onProgress,
  });
  @override
  final Future<void>? abortTrigger;
  final void Function(double)? onProgress;
  @override
  http.ByteStream finalize() {
    final total = contentLength;
    var sent = 0, lastPercent = -1;
    return http.ByteStream(
      super.finalize().map((chunk) {
        sent += chunk.length;
        final progress = total == 0 ? 0.0 : (sent / total).clamp(0.0, 1.0);
        final percent = (progress * 100).floor();
        if (percent != lastPercent) {
          lastPercent = percent;
          onProgress?.call(progress);
        }
        return chunk;
      }),
    );
  }
}
