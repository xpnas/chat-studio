import 'server_workspace.dart';
import 'task_plan.dart';
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

  final _agentIcons = <String, Future<Uint8List?>>{};
  final _failedAgentIcons = <String>{};
  void retryAgentIcons() {
    for (final file in _failedAgentIcons) {
      _agentIcons.remove(file);
    }
    _failedAgentIcons.clear();
  }

  Future<Uint8List?> agentIcon(String file) => _agentIcons.putIfAbsent(
    file,
    () => _loadAgentIcon(file).then((bytes) {
      if (bytes == null) _failedAgentIcons.add(file);
      return bytes;
    }),
  );
  Future<Uint8List?> _loadAgentIcon(String file) async {
    // Static Agent Manager assets are public. Never attach credentials or follow
    // redirects, and bound the response before decoding an icon.
    if (!RegExp(r'^[a-z0-9_-]+\.(png|svg)$').hasMatch(file)) return null;
    try {
      final request = http.Request(
        'GET',
        address.uri.resolve('/coding-agents/$file'),
      )..followRedirects = false;
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        await response.stream.listen(null).cancel();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final part in response.stream.timeout(
        const Duration(seconds: 10),
      )) {
        if (bytes.length + part.length > 2 * 1024 * 1024) return null;
        bytes.add(part);
      }
      final result = bytes.takeBytes();
      if (result.isEmpty) return null;
      if (file.endsWith('.svg') &&
          !RegExp(
            r'<svg(?:\s|>)',
          ).hasMatch(utf8.decode(result, allowMalformed: false))) {
        return null;
      }
      if (file.endsWith('.png') &&
          (result.length < 8 ||
              result[0] != 137 ||
              result[1] != 80 ||
              result[2] != 78 ||
              result[3] != 71)) {
        return null;
      }
      return result;
    } catch (_) {
      return null;
    }
  }

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
    String? groupRoomId,
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
      groupRoomId == null
          ? '/api/studio/uploads'
          : '/api/studio/group-chat/rooms/${Uri.encodeComponent(groupRoomId)}/attachments',
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

  Uri _attachmentUri(MessageAttachment file, {bool thumbnail = false}) {
    if (file.groupRoomId.isNotEmpty) {
      final storedName = file.path.replaceAll('\\', '/').split('/').last;
      return address.uri.replace(
        pathSegments: [
          '',
          'api',
          'studio',
          'group-chat',
          'rooms',
          file.groupRoomId,
          'attachments',
          storedName,
        ],
        queryParameters: {'name': file.name},
      );
    }
    return address.uri.replace(
      path: '/api/studio/files/download',
      queryParameters: {
        'path': file.path,
        'name': file.name,
        if (thumbnail) 'variant': 'app-image',
      },
    );
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
            _attachmentUri(file),
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
  }) => _previewBytes(
    _attachmentUri(file, thumbnail: thumbnail),
    cacheKey: '${file.groupRoomId}|${file.path}',
    thumbnail: thumbnail,
    cancel: cancel,
  );

  Future<Uint8List> groupWorkspaceBytes(
    String roomId,
    String path,
  ) => _previewBytes(
    address.uri.replace(
      path:
          '/api/studio/group-chat/rooms/${Uri.encodeComponent(roomId)}/workspace-file/content',
      queryParameters: {'path': path},
    ),
  );

  Future<Uint8List> _previewBytes(
    Uri uri, {
    String cacheKey = '',
    bool thumbnail = false,
    Future<void>? cancel,
  }) async {
    // Never navigate to a URL or use arbitrary response headers as destinations.
    final scope = profile, credential = token;
    final key = '$scope|$credential|$cacheKey|$thumbnail';
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
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
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

  /// Authenticates with the same credential endpoint as the web client.
  ///
  /// Mobile deliberately does not use the legacy app-specific login endpoint
  /// endpoint or send device metadata. The returned JWT is the regular web
  /// access token and is used by both REST and Socket.IO requests.
  Future<Map<String, dynamic>> login(String username, String password) =>
      request(
        '/api/auth/login',
        method: 'POST',
        public: true,
        body: {'username': username.trim(), 'password': password},
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

  // Management APIs mirror the v1.0.3 Studio web client. These methods keep
  // credentials on the server and return only the fields needed by mobile UI.
  Future<Map<String, dynamic>> agentAvailability() =>
      request('/api/agents/availability');

  Future<Map<String, dynamic>> codingAgents() => request('/api/coding-agents');

  Future<Map<String, dynamic>> installCodingAgent(String id) => request(
    '/api/coding-agents/${Uri.encodeComponent(id)}/install',
    method: 'POST',
  );

  Future<Map<String, dynamic>> checkCodingAgentUpdate(String id) => request(
    '/api/coding-agents/${Uri.encodeComponent(id)}/check-update',
    method: 'POST',
  );

  Future<Map<String, dynamic>> deleteCodingAgent(String id) => request(
    '/api/coding-agents/${Uri.encodeComponent(id)}',
    method: 'DELETE',
  );

  Future<Map<String, dynamic>> codingAgentConfig(
    String id,
    String key,
  ) => request(
    '/api/coding-agents/${Uri.encodeComponent(id)}/config-files/${Uri.encodeComponent(key)}',
  );

  Future<Map<String, dynamic>> saveCodingAgentConfig(
    String id,
    String key,
    String content,
  ) => request(
    '/api/coding-agents/${Uri.encodeComponent(id)}/config-files/${Uri.encodeComponent(key)}',
    method: 'PUT',
    body: {'content': content},
  );

  Future<Map<String, dynamic>> refreshModelCache() =>
      request('/api/hermes/provider-models/cache/refresh', method: 'POST');

  Future<Map<String, dynamic>> providerEditor(String poolKey) => request(
    '/api/hermes/config/providers/${Uri.encodeComponent(poolKey)}/editor',
  );

  Future<Map<String, dynamic>> patchProviderEditor(
    String poolKey,
    String revision,
    Map<String, dynamic> values,
  ) => request(
    '/api/hermes/config/providers/${Uri.encodeComponent(poolKey)}/editor',
    method: 'PATCH',
    body: {...values, 'revision': revision},
  );

  Future<Map<String, dynamic>> testProviderEditor(
    String poolKey,
    Map<String, dynamic> values,
  ) => request(
    '/api/hermes/config/providers/${Uri.encodeComponent(poolKey)}/editor/test',
    method: 'POST',
    body: values,
  );

  Future<Map<String, dynamic>> refreshProviderModels(
    String poolKey, {
    bool confirm = false,
  }) => request(
    '/api/hermes/config/providers/${Uri.encodeComponent(poolKey)}/models/refresh',
    method: 'POST',
    body: {'confirm': confirm},
  );

  Future<Map<String, dynamic>> restoreProviderModels(String poolKey) => request(
    '/api/hermes/config/providers/${Uri.encodeComponent(poolKey)}/models/restore',
    method: 'POST',
    body: const {},
  );

  Future<Map<String, dynamic>> codingAgentUpdatePolicies() =>
      request('/api/coding-agents/update-policies');

  Future<Map<String, dynamic>> setCodingAgentAutoUpdate(
    String id,
    bool enabled,
  ) => request(
    '/api/coding-agents/${Uri.encodeComponent(id)}/update-policy',
    method: 'PUT',
    body: {'autoUpdate': enabled},
  );

  Future<Map<String, dynamic>> codingAgentMcpServers(String id) =>
      request('/api/coding-agents/${Uri.encodeComponent(id)}/mcp/servers');

  Future<Map<String, dynamic>> addCodingAgentMcpServer(
    String id,
    String name,
    Map<String, dynamic> config,
  ) => request(
    '/api/coding-agents/${Uri.encodeComponent(id)}/mcp/servers',
    method: 'POST',
    body: {'name': name, 'config': config},
  );

  Future<Map<String, dynamic>> testCodingAgentMcpServer(
    String id,
    String name,
  ) => request(
    '/api/coding-agents/${Uri.encodeComponent(id)}/mcp/servers/${Uri.encodeComponent(name)}/test',
    method: 'POST',
  );

  Future<void> deleteCodingAgentMcpServer(String id, String name) async {
    await request(
      '/api/coding-agents/${Uri.encodeComponent(id)}/mcp/servers/${Uri.encodeComponent(name)}',
      method: 'DELETE',
    );
  }

  Future<void> setDefaultModel(String model, String provider) async {
    await request(
      '/api/hermes/config/model',
      method: 'PUT',
      body: {'default': model, 'provider': provider},
    );
  }

  Future<void> addProvider({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String model,
    String apiMode = 'chat_completions',
  }) async {
    await request(
      '/api/hermes/config/providers',
      method: 'POST',
      body: {
        'name': name,
        'base_url': baseUrl,
        'api_key': apiKey,
        'model': model,
        'api_mode': apiMode,
      },
    );
  }

  Future<void> removeProvider(
    String provider, {
    String? source,
    String? providerKey,
  }) async {
    await request(
      '/api/hermes/config/providers/${Uri.encodeComponent(provider)}',
      method: 'DELETE',
      query: {
        ...(source == null ? const <String, String>{} : {'source': source}),
        ...(providerKey == null
            ? const <String, String>{}
            : {'providerKey': providerKey}),
      },
    );
  }

  Future<Map<String, dynamic>> fetchConfig({List<String>? sections}) => request(
    '/api/hermes/config',
    query: {if (sections != null) 'sections': sections.join(',')},
  );

  Future<void> updateConfigSection(
    String section,
    Map<String, dynamic> values,
  ) async {
    await request(
      '/api/hermes/config',
      method: 'PUT',
      body: {'section': section, 'values': values, 'restart': false},
    );
  }

  Future<Map<String, dynamic>> auxiliaryModels() =>
      request('/api/hermes/config/auxiliary-models');

  Future<void> saveAuxiliaryModels(Map<String, dynamic> auxiliary) async {
    await request(
      '/api/hermes/config/auxiliary-models',
      method: 'PUT',
      body: {'auxiliary': auxiliary},
    );
  }

  Future<Map<String, dynamic>> delegationModel() =>
      request('/api/hermes/config/delegation-model');

  Future<void> saveDelegationModel(Map<String, dynamic> delegation) async {
    await request(
      '/api/hermes/config/delegation-model',
      method: 'PUT',
      body: {'delegation': delegation},
    );
  }

  Future<Map<String, dynamic>> combinationModels() =>
      request('/api/hermes/config/moa');

  Future<void> saveCombinationModels(Map<String, dynamic> moa) async {
    await request('/api/hermes/config/moa', method: 'PUT', body: {'moa': moa});
  }

  Future<Map<String, dynamic>> usageStats({int days = 30}) =>
      request('/api/studio/usage/stats', query: {'days': '$days'});

  Future<List<Map<String, dynamic>>> logFiles() async =>
      asList((await request('/api/studio/logs'))['files']).map(asMap).toList();

  Future<List<Map<String, dynamic>>> logs(
    String name, {
    int lines = 100,
    String level = '',
  }) async => asList(
    (await request(
      '/api/studio/logs/${Uri.encodeComponent(name)}',
      query: {'lines': '$lines', if (level.isNotEmpty) 'level': level},
    ))['entries'],
  ).map(asMap).toList();

  Future<Map<String, dynamic>> performanceRuntime() =>
      request('/api/studio/performance/runtime');

  Future<Map<String, dynamic>> skillUsageStats({int days = 7}) =>
      request('/api/hermes/skills/usage/stats', query: {'days': '$days'});

  Future<Map<String, dynamic>> sttSettings() =>
      request('/api/studio/stt/settings');

  Future<Map<String, dynamic>> ttsSettings() =>
      request('/api/studio/tts/settings');

  Future<void> setActiveVoiceProvider(String kind, String provider) async {
    await request(
      '/api/studio/$kind/settings/active',
      method: 'PUT',
      body: {'provider': provider},
    );
  }

  Future<void> deleteVoiceProvider(String kind, String provider) async {
    await request(
      '/api/studio/$kind/settings/${Uri.encodeComponent(provider)}',
      method: 'DELETE',
    );
  }

  Future<void> saveVoiceProvider(
    String kind,
    String provider,
    Map<String, dynamic> settings, {
    String apiKey = '',
  }) async {
    await request(
      '/api/studio/$kind/settings/${Uri.encodeComponent(provider)}',
      method: 'PUT',
      body: {
        'settings': settings,
        if (apiKey.isNotEmpty) 'secrets': {'apiKey': apiKey},
      },
    );
  }

  Future<Map<String, dynamic>> sessions({
    int offset = 0,
    String search = '',
    bool includeArchived = false,
  }) => search.isNotEmpty
      ? request(
          '/api/studio/search/sessions',
          query: {
            'profile': profile,
            'q': search,
            'limit': '100',
            if (includeArchived) 'includeArchived': 'true',
          },
        )
      : request(
          '/api/studio/sessions',
          query: {
            'profile': profile,
            'offset': '$offset',
            'limit': '40',
            if (includeArchived) 'includeArchived': 'true',
          },
        );
  Future<List<GroupRoom>> groupRooms() async {
    final data = await request('/api/studio/group-chat/rooms');
    return asList(data['rooms'])
        .map((item) => GroupRoom.fromJson(asMap(item)))
        .where((room) => room.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<GroupRoomDetail> groupRoomDetail(
    String roomId, {
    int offset = 0,
    int limit = 150,
    String? before,
    bool history = false,
  }) async {
    final data = await request(
      '/api/studio/group-chat/rooms/${Uri.encodeComponent(roomId)}',
      query: {
        'offset': '$offset',
        'limit': '${limit.clamp(1, 150)}',
        if (before != null && before.isNotEmpty) 'before': before,
        if (history) 'history': '1',
      },
    );
    final room = GroupRoom.fromJson(asMap(data['room']));
    final agents = asList(data['agents'])
        .map((item) => GroupAgentSummary.fromJson(asMap(item)))
        .where((agent) => agent.id.isNotEmpty || agent.agent.isNotEmpty)
        .toList(growable: false);
    return GroupRoomDetail(
      room: room,
      agents: agents.isEmpty ? room.agents : agents,
      messages: asList(data['messages'])
          .map(
            (item) =>
                GroupChatMessage.fromJson({'roomId': roomId, ...asMap(item)}),
          )
          .where((message) => message.id.isNotEmpty)
          .toList(growable: false),
      total: integer(data['total']),
      hasMore: flag(data['hasMore']),
    );
  }

  Future<List<ConversationCategory>> conversationCategories() async {
    final data = await request('/api/studio/session-categories');
    return asList(data['categories'])
        .map((item) => ConversationCategory.fromJson(asMap(item)))
        .where((category) => category.id > 0 && category.name.isNotEmpty)
        .toList();
  }

  Future<ConversationCategory> createConversationCategory(String name) async {
    final data = await request(
      '/api/studio/session-categories',
      method: 'POST',
      body: {'name': name},
    );
    return ConversationCategory.fromJson(asMap(data['category']));
  }

  Future<void> deleteConversationCategory(int id) async {
    await request(
      '/api/studio/session-categories/${Uri.encodeComponent('$id')}',
      method: 'DELETE',
    );
  }

  Future<void> setConversationPinned(String id, bool value) async {
    // The current Studio API uses one /pin endpoint for both operations and
    // requires an actual JSON boolean in the request body. Do not use the
    // legacy /unpin route: newer servers reject a missing is_pinned field.
    await request(
      '/api/studio/sessions/${Uri.encodeComponent(id)}/pin',
      method: 'POST',
      body: {'is_pinned': value},
    );
  }

  Future<void> setConversationArchived(String id, bool value) async {
    await request(
      '/api/studio/sessions/${Uri.encodeComponent(id)}/${value ? 'archive' : 'unarchive'}',
      method: 'POST',
    );
  }

  Future<void> setConversationCategory(String id, int? categoryId) async {
    await request(
      '/api/studio/sessions/${Uri.encodeComponent(id)}/category',
      method: 'POST',
      body: {'categoryId': categoryId},
    );
  }

  Future<int> contextLength({String? provider, String? model}) async {
    final data = await request(
      '/api/studio/sessions/context-length',
      query: {
        'profile': profile,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
        if (model != null && model.isNotEmpty) 'model': model,
      },
    );
    final value = integer(data['context_length']);
    if (value <= 0) throw const ApiException('无效的上下文上限');
    return value;
  }

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
      taskPlans: TaskPlan.parseList(data['taskPlans'], sessionId: id),
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

  Future<Map<String, dynamic>> workspaceFiles(String id, {String path = ''}) =>
      request(
        '/api/studio/sessions/${Uri.encodeComponent(id)}/workspace-files/list',
        query: {'path': path},
      );

  Future<Map<String, dynamic>> readWorkspaceFile(String id, String path) =>
      request(
        '/api/studio/sessions/${Uri.encodeComponent(id)}/workspace-file/read',
        query: {'path': path},
      );

  Future<void> writeWorkspaceFile(
    String id,
    String path,
    String content,
  ) async {
    await request(
      '/api/studio/sessions/${Uri.encodeComponent(id)}/workspace-file/write',
      method: 'PUT',
      body: {'path': path, 'content': content},
    );
  }

  Future<Map<String, dynamic>> workspaceFolders({String path = ''}) =>
      request('/api/studio/workspace/folders', query: {'path': path});

  Future<void> setWorkspace(String id, String path) async {
    if (!isAbsoluteServerPath(path)) {
      throw const ApiException('请从服务器目录中选择有效的绝对路径');
    }
    await request(
      '/api/studio/sessions/${Uri.encodeComponent(id)}/workspace',
      method: 'POST',
      body: {'workspace': path},
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
