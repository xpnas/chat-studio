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
  }) async {
    final scope = profile, credential = token;
    var canceled = false;
    cancel?.then((_) => canceled = true);
    final audio = await http.MultipartFile.fromPath(
      'audio',
      path,
      filename: 'voice.wav',
      contentType: http.MediaType('audio', 'wav'),
    );
    if (audio.length > 4 * 1024 * 1024) throw const ApiException('录音过长，请分段输入');
    if (canceled || scope != profile || credential != token) {
      throw const ApiException('已取消：会话或 Profile 已变化');
    }
    final data = await _multipart(
      '/api/studio/stt/transcribe',
      [audio],
      fields: {'provider': provider},
      cancel: cancel,
    );
    final result = text(data['text']).trim();
    if (result.isEmpty) throw const ApiException('未识别到语音，请重试');
    return result;
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
          ? 'Ekko Mobile · iOS'
          : 'Ekko Mobile · Android',
      'device_brand': Platform.isIOS ? 'Apple' : 'Android',
      'device_model': 'Ekko Mobile',
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
