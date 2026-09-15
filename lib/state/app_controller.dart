import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/server_address.dart';
import '../data/app_storage.dart';
import '../data/chat_transport.dart';
import '../data/models.dart';
import '../data/studio_api.dart';
import 'chat_timeline.dart';

typedef ApiFactory = StudioApi Function(ServerAddress address);

class AppController extends ChangeNotifier {
  AppController({
    required this.storage,
    ChatTransport? transport,
    ApiFactory? apiFactory,
  }) : transport = transport ?? SocketChatTransport(),
       _apiFactory = apiFactory ?? ((address) => StudioApi(address));
  final AppStorage storage;
  final ChatTransport transport;
  final ApiFactory _apiFactory;
  StudioApi? api;
  final timeline = ChatTimeline();
  Account? account;
  List<String> profiles = [];
  List<ModelChoice> models = [];
  List<Conversation> conversations = [];
  ModelChoice? selectedModel;
  Conversation? current;
  String? sessionId;
  String engine = 'ekko-agent';
  ModelChoice? _newChatModel;
  String _newChatEngine = 'ekko-agent';
  String? workspaceNotice;
  bool readingHintSeen = true;
  String? retryInput;
  List<Map<String, dynamic>> retryAttachments = [];
  int retryRevision = 0;
  String? _lastSubmittedInput;
  List<Map<String, dynamic>> _lastSubmittedAttachments = [];
  Future<void> _choiceWrite = Future.value();
  String get _choiceScope => '${api!.address.value}|${account!.id}|$profile';

  Future<void> _rememberChoice() async {
    if (api == null || account == null) return;
    _newChatModel = selectedModel;
    _newChatEngine = engine;
    final scope = _choiceScope;
    final choice = {
      'model': selectedModel?.id,
      'provider': selectedModel?.provider,
      'engine': engine,
    };
    _choiceWrite = _choiceWrite
        .then((_) => storage.saveChoice(scope, choice))
        .catchError((Object _) {});
    await _choiceWrite;
  }

  Future<void> markReadingHintSeen() async {
    readingHintSeen = true;
    try {
      await storage.markReadingHintSeen();
    } catch (_) {
      /* Optional hint. */
    }
  }

  bool canRetryMessage(ChatMessage message) =>
      canSend &&
      _lastSubmittedInput != null &&
      message.delivery == 'failed' &&
      timeline.messages.where((m) => m.role == 'user').lastOrNull?.renderKey ==
          message.renderKey;

  void prepareRetry() {
    if (!canSend ||
        _lastSubmittedInput == null ||
        timeline.messages.where((m) => m.role == 'user').lastOrNull?.delivery !=
            'failed') {
      return;
    }
    retryInput = _lastSubmittedInput;
    retryAttachments = List.of(_lastSubmittedAttachments);
    retryRevision++;
    _notify();
  }

  bool? codexInstalled;
  String? sttProvider;
  String voiceHint = '请在服务端配置语音识别（STT）；仅配置 TTS 不能语音输入';
  int get chatRevision => _chatEpoch;
  String theme = 'system';
  String serverInput = '';
  String search = '';
  String? error;
  bool booting = true,
      busy = false,
      loadingSessions = false,
      loadingMessages = false;
  bool connected = false,
      syncing = false,
      hasMoreSessions = false,
      hasMoreMessages = false;
  int _epoch = 0, _chatEpoch = 0, _searchEpoch = 0, _historyOffset = 0;
  bool _disposed = false;
  Timer? _paintTimer, _runTimer, _syncTimer;
  bool get authenticated => account != null;
  bool get working => timeline.working;
  bool get canSend =>
      authenticated &&
      profiles.isNotEmpty &&
      connected &&
      !syncing &&
      !loadingMessages &&
      !working &&
      !busy &&
      current?.canContinue != false;
  String get profile => api?.profile ?? 'default';
  String get title => current?.title ?? '新对话';
  bool get allowLocalHttp => api?.address.allowLocalHttp ?? false;

  void _notify({bool batch = false}) {
    if (_disposed) return;
    if (batch) {
      _paintTimer ??= Timer(const Duration(milliseconds: 40), () {
        _paintTimer = null;
        _notify();
      });
    } else {
      _paintTimer?.cancel();
      _paintTimer = null;
      notifyListeners();
    }
  }

  void dismissError() {
    error = null;
    _notify();
  }

  void reportError(Object value) {
    error = value.toString().replaceFirst('FormatException: ', '');
    _notify();
  }

  bool _valid(int epoch) => !_disposed && epoch == _epoch;
  void _bind(StudioApi value) {
    api?.close();
    api = value;
    value.onUnauthorized = () {
      unawaited(logout(expired: true));
    };
  }

  Map<String, dynamic> _saved() => {
    'server': api!.address.value,
    'allowLocalHttp': api!.address.allowLocalHttp,
    'token': api!.token,
    'profile': profile,
  };

  Future<void> initialize() async {
    final epoch = ++_epoch;
    try {
      theme = await storage.readTheme();
      final saved = await storage.readSession();
      if (saved != null && _valid(epoch)) {
        serverInput = text(saved['server']);
        final client =
            _apiFactory(
                ServerAddress.parse(
                  serverInput,
                  allowLocalHttp: flag(saved['allowLocalHttp']),
                ),
              )
              ..token = text(saved['token'])
              ..profile = text(saved['profile']).isEmpty
                  ? 'default'
                  : text(saved['profile']);
        _bind(client);
        final user = await client.me();
        if (!_valid(epoch)) return;
        account = user;
        await _loadWorkspace(epoch);
      }
    } catch (e) {
      if (_valid(epoch)) error = '自动连接未完成，可重新登录。${e.toString()}';
    } finally {
      if (!_disposed) {
        booting = false;
        _notify();
      }
    }
  }

  Future<bool> login(
    String server,
    String username,
    String password,
    bool localHttp,
  ) async {
    if (busy) return false;
    final epoch = ++_epoch;
    busy = true;
    error = null;
    _notify();
    try {
      final client = _apiFactory(
        ServerAddress.parse(server, allowLocalHttp: localHttp),
      );
      _bind(client);
      final result = await client.login(
        username,
        password,
        await storage.deviceId(),
      );
      if (!_valid(epoch)) return false;
      client.token = text(result['token']);
      if (client.token.isEmpty) throw const ApiException('服务器没有返回登录令牌');
      final allowed = asList(result['profiles']).whereType<String>().toList();
      client.profile = allowed.isNotEmpty ? allowed.first : 'default';
      final user = await client.me();
      if (!_valid(epoch)) return false;
      serverInput = client.address.value;
      await storage.saveSession(_saved());
      if (!_valid(epoch)) return false;
      account = user;
      await _loadWorkspace(epoch);
      return true;
    } catch (e) {
      if (_valid(epoch)) reportError(e);
      return false;
    } finally {
      if (_valid(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> _loadWorkspace(int epoch) async {
    try {
      final available = await api!.profiles();
      if (!_valid(epoch)) return;
      profiles = available;
      if (available.isEmpty) {
        throw const ApiException('账号没有可访问的 Profile，请联系服务管理员');
      }
      if (!available.contains(profile)) api!.profile = available.first;
      final catalog = await api!.models();
      if (!_valid(epoch)) return;
      models = ModelChoice.parseGroups(catalog['groups']);
      final fallback =
          models
              .where(
                (m) =>
                    m.id == catalog['default'] &&
                    m.provider == catalog['default_provider'],
              )
              .firstOrNull ??
          models.firstOrNull;
      final remembered = await storage.readChoice(_choiceScope);
      if (!_valid(epoch)) return;
      readingHintSeen = await storage.readReadingHintSeen();
      if (!_valid(epoch)) return;
      final storedModel = models
          .where(
            (m) =>
                m.id == remembered?['model'] &&
                m.provider == remembered?['provider'],
          )
          .firstOrNull;
      _newChatModel = storedModel ?? fallback;
      _newChatEngine =
          ['ekko-agent', 'hermes', 'codex'].contains(remembered?['engine'])
          ? remembered!['engine'] as String
          : 'ekko-agent';
      workspaceNotice = remembered?['model'] != null && storedModel == null
          ? '上次使用的模型已不可用，新对话已改用服务端默认模型。'
          : null;
      if (sessionId == null) {
        selectedModel = _newChatModel;
        engine = _newChatEngine;
      }
      await refreshCapabilities();
      if (!_valid(epoch)) return;
      if (_newChatEngine == 'codex' && codexInstalled == false) {
        _newChatEngine = 'ekko-agent';
        if (sessionId == null) engine = _newChatEngine;
        workspaceNotice = '服务端 Codex 尚未安装，新对话已改用 Ekko Agent。';
      }
      await storage.saveSession(_saved());
      if (!_valid(epoch)) return;
      reconnect();
      await refreshSessions();
    } catch (e) {
      if (_valid(epoch)) reportError(e);
    }
  }

  Future<void> refreshCapabilities() async {
    final client = api;
    if (client == null) return;
    final epoch = _epoch, activeProfile = profile;
    bool valid() => _valid(epoch) && api == client && profile == activeProfile;
    await Future.wait([
      (() async {
        try {
          final data = await client.request('/api/coding-agents');
          if (!valid()) return;
          final tool = asList(
            data['tools'],
          ).map(asMap).where((t) => t['id'] == 'codex').firstOrNull;
          codexInstalled = tool == null ? null : flag(tool['installed']);
        } catch (_) {
          if (valid()) codexInstalled = null;
        }
      })(),
      (() async {
        try {
          final data = await client.request('/api/studio/stt/profile-status');
          if (!valid()) return;
          sttProvider =
              flag(data['configured']) &&
                  text(data['activeProvider']).isNotEmpty
              ? text(data['activeProvider'])
              : null;
          voiceHint = sttProvider == null
              ? '请在当前 Profile 配置语音识别（STT）；仅配置 TTS 不能语音输入'
              : '语音输入';
        } catch (_) {
          if (valid()) {
            sttProvider = null;
            voiceHint = '无法读取语音识别配置，请检查服务端权限后重试';
          }
        }
      })(),
    ]);
    if (valid()) _notify();
  }

  void reconnect() {
    if (!authenticated || api == null) return;
    connected = false;
    syncing = sessionId != null;
    error = null;
    final epoch = _epoch;
    transport.connect(api!, (event, data) {
      if (_valid(epoch)) _event(event, data);
    });
    _notify();
  }

  Future<void> refreshWorkspace() async {
    if (busy || working) return;
    busy = true;
    _notify();
    await _loadWorkspace(_epoch);
    busy = false;
    _notify();
  }

  Future<void> switchProfile(String value) async {
    if (working || busy || value == profile || !profiles.contains(value)) {
      return;
    }
    final epoch = ++_epoch;
    transport.dispose();
    connected = false;
    syncing = false;
    busy = true;
    api!.profile = value;
    conversations = [];
    models = [];
    selectedModel = null;
    sttProvider = null;
    codexInstalled = null;
    _resetChat();
    _notify();
    await _loadWorkspace(epoch);
    if (_valid(epoch)) {
      busy = false;
      _notify();
    }
  }

  Future<void> refreshSessions({String? query, bool more = false}) async {
    if (!authenticated || (more && loadingSessions)) return;
    final client = api!;
    final epoch = _epoch, searchEpoch = ++_searchEpoch;
    if (query != null) search = query.trim();
    loadingSessions = true;
    _notify();
    try {
      final data = await client.sessions(
        offset: more ? conversations.length : 0,
        search: search,
      );
      if (!_valid(epoch) || searchEpoch != _searchEpoch) return;
      final rows = asList(
        data[search.isEmpty ? 'sessions' : 'results'],
      ).map((s) => Conversation.fromJson(asMap(s))).toList();
      final merged = [if (more) ...conversations, ...rows];
      conversations = {for (final s in merged) s.id: s}.values.toList();
      hasMoreSessions = search.isEmpty && flag(data['hasMore']);
    } catch (e) {
      if (_valid(epoch) && searchEpoch == _searchEpoch) reportError(e);
    } finally {
      if (_valid(epoch) && searchEpoch == _searchEpoch) {
        loadingSessions = false;
        _notify();
      }
    }
  }

  void _resetChat() {
    _chatEpoch++;
    _runTimer?.cancel();
    _syncTimer?.cancel();
    sessionId = null;
    current = null;
    timeline.clear();
    _lastSubmittedInput = null;
    _lastSubmittedAttachments = [];
    retryInput = null;
    retryAttachments = [];
    hasMoreMessages = false;
    _historyOffset = 0;
    syncing = false;
    loadingMessages = false;
  }

  void newChat() {
    if (working || busy) return;
    _resetChat();
    selectedModel = _newChatModel ?? selectedModel;
    engine = _newChatEngine;
    error = null;
    _notify();
  }

  Future<void> openConversation(Conversation conversation) async {
    if (working || busy) return;
    if (conversation.profile != profile) {
      await switchProfile(conversation.profile);
    }
    _resetChat();
    current = conversation;
    sessionId = conversation.id;
    engine = ['ekko-agent', 'codex'].contains(conversation.agent)
        ? conversation.agent
        : 'hermes';
    selectedModel =
        models
            .where(
              (m) =>
                  m.id == conversation.model &&
                  m.provider == conversation.provider,
            )
            .firstOrNull ??
        (conversation.model.isEmpty
            ? selectedModel
            : ModelChoice(
                id: conversation.model,
                provider: conversation.provider,
                label: conversation.model,
              ));
    await loadHistory();
    if (sessionId == conversation.id && connected) _resume();
  }

  Future<void> loadHistory({bool more = false}) async {
    final sid = sessionId;
    if (sid == null || loadingMessages) return;
    final epoch = _epoch, chatEpoch = _chatEpoch;
    loadingMessages = true;
    _notify();
    try {
      final page = await api!.messages(sid, offset: more ? _historyOffset : 0);
      if (!_valid(epoch) || chatEpoch != _chatEpoch) return;
      if (more) {
        timeline.prepend(page.messages);
      } else {
        timeline.replace(page.messages, keepOlder: page.hasMore);
      }
      if (more ||
          _historyOffset <= page.offset ||
          timeline.messages.length <= page.messages.length) {
        _historyOffset = page.offset;
        hasMoreMessages = page.hasMore;
      }
    } catch (e) {
      if (_valid(epoch) && chatEpoch == _chatEpoch) reportError(e);
    } finally {
      if (_valid(epoch) && chatEpoch == _chatEpoch) {
        loadingMessages = false;
        _notify();
      }
    }
  }

  Future<void> chooseModel(ModelChoice model) async {
    if (working || busy) return;
    final epoch = _epoch, chatEpoch = _chatEpoch;
    busy = true;
    _notify();
    try {
      if (current != null) await api!.setModel(current!.id, model);
      if (_valid(epoch) && chatEpoch == _chatEpoch) {
        selectedModel = model;
        await _rememberChoice();
      }
    } catch (e) {
      if (_valid(epoch)) reportError(e);
    } finally {
      if (_valid(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  void chooseEngine(String value) {
    if (sessionId == null &&
        !working &&
        ['ekko-agent', 'hermes', 'codex'].contains(value)) {
      engine = value;
      unawaited(_rememberChoice());
      _notify();
    }
  }

  bool send(String input, {List<Map<String, dynamic>> attachments = const []}) {
    input = input.trim();
    if ((input.isEmpty && attachments.isEmpty) || !canSend) return false;
    if (input.length > 64000) {
      reportError('消息过长，请拆分后发送（最多 64000 字符）');
      return false;
    }
    final sid = sessionId ?? const Uuid().v4();
    final queueId = const Uuid().v4();
    try {
      transport.emit('run', {
        'input': attachments.isEmpty
            ? input
            : [
                if (input.isNotEmpty) {'type': 'text', 'text': input},
                ...attachments,
              ],
        'session_id': sid,
        'profile': profile,
        'queue_id': queueId,
        if (engine != 'hermes') 'agent_id': engine,
        if (engine != 'hermes') 'source': 'coding_agent',
        if (engine == 'codex') 'mode': 'scoped',
        if (selectedModel != null) 'model': selectedModel!.id,
        if (selectedModel != null) 'provider': selectedModel!.provider,
        if (selectedModel?.apiMode.isNotEmpty == true)
          'api_mode': selectedModel!.apiMode,
      });
      _chatEpoch++;
      _lastSubmittedInput = input;
      _lastSubmittedAttachments = List.of(attachments);
      sessionId = sid;
      timeline.begin(
        [
          input,
          if (attachments.isNotEmpty) messageText(attachments),
        ].where((s) => s.isNotEmpty).join('\n'),
        'local:$queueId',
        attachments: MessageAttachment.parse(attachments),
      );
      error = null;
      _runTimer?.cancel();
      _runTimer = Timer(const Duration(seconds: 25), () {
        if (working) {
          timeline.markUncertain();
          _notify();
          if (connected) _resume();
        }
      });
      _notify();
      return true;
    } catch (e) {
      reportError(e);
      return false;
    }
  }

  void stop() {
    if (!connected || sessionId == null) return;
    try {
      transport.emit('abort', {'session_id': sessionId});
      timeline.activity = '正在停止';
      _notify();
    } catch (e) {
      reportError(e);
    }
  }

  void _resume() {
    if (sessionId == null || !connected) return;
    syncing = true;
    timeline.markUncertain();
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 20), () {
      timeline.markUncertain();
      error = '同步超时，请重新连接；消息不会自动重发。';
      _notify();
    });
    try {
      transport.emit('resume', {'session_id': sessionId});
    } catch (e) {
      reportError(e);
    }
    _notify();
  }

  void onForeground() {
    if (authenticated) {
      if (connected) {
        _resume();
      } else {
        reconnect();
      }
    }
  }

  void _event(String event, Map<String, dynamic> data) {
    if (event == 'connected') {
      connected = true;
      if (sessionId != null) {
        _resume();
      } else {
        syncing = false;
        _notify();
      }
      return;
    }
    if (event == 'disconnected' || event == 'connection.error') {
      connected = false;
      timeline.markUncertain();
      if (event == 'connection.error') {
        final message = text(data['error']);
        if (message.toLowerCase().contains('auth')) {
          unawaited(logout(expired: true));
          return;
        }
        error = '聊天连接失败，请检查 WebSocket 代理和 Profile 权限';
      }
      _notify();
      return;
    }
    if (sessionId == null || text(data['session_id']) != sessionId) return;
    if (event == 'resumed') {
      _syncTimer?.cancel();
      _runTimer?.cancel();
      syncing = false;
      _chatEpoch++;
      loadingMessages = false;
      timeline.resume(data);
      _historyOffset = integer(data['messageLoadedCount']);
      if (_historyOffset == 0) _historyOffset = asList(data['messages']).length;
      hasMoreMessages = flag(data['hasMoreBefore']);
      _notify();
      return;
    }
    if (event == 'run.failed' && syncing) {
      syncing = false;
      _syncTimer?.cancel();
    }
    if (!timeline.apply(event, data)) return;
    if (event == 'run.started' || event == 'message.delta') _runTimer?.cancel();
    if (['run.completed', 'run.failed', 'abort.completed'].contains(event)) {
      _runTimer?.cancel();
      if (event != 'run.failed') unawaited(loadHistory());
      unawaited(refreshSessions());
    }
    _notify(batch: event == 'message.delta' || event == 'reasoning.delta');
  }

  void respondToInteraction(String response) {
    final pending = timeline.interaction;
    if (pending == null || !connected) return;
    final approval = pending['kind'] == 'approval.requested';
    try {
      transport.emit(approval ? 'approval.respond' : 'clarify.respond', {
        'session_id': sessionId,
        if (approval) 'approval_id': pending['approval_id'],
        if (!approval) 'clarify_id': pending['clarify_id'],
        approval ? 'choice' : 'response': response,
      });
      // Keep the prompt until server resolution, not optimistic authorization.
      timeline.activity = '等待服务器确认';
      _notify();
    } catch (e) {
      reportError(e);
    }
  }

  Future<void> renameConversation(
    Conversation conversation,
    String title,
  ) async {
    if (title.trim().isEmpty) return;
    final epoch = _epoch;
    try {
      await api!.rename(conversation.id, title.trim());
      if (!_valid(epoch)) return;
      if (current?.id == conversation.id) {
        current = Conversation(
          id: conversation.id,
          title: title.trim(),
          profile: conversation.profile,
          agent: conversation.agent,
          source: conversation.source,
          model: conversation.model,
          provider: conversation.provider,
        );
      }
      await refreshSessions();
    } catch (e) {
      if (_valid(epoch)) reportError(e);
    }
  }

  Future<void> deleteConversation(Conversation conversation) async {
    if (working && sessionId == conversation.id) return;
    final epoch = _epoch;
    try {
      await api!.delete(conversation.id);
      if (!_valid(epoch)) return;
      if (sessionId == conversation.id) _resetChat();
      await refreshSessions();
    } catch (e) {
      if (_valid(epoch)) reportError(e);
    }
  }

  Future<bool> updateCredentials(
    String currentPassword,
    String replacement, {
    bool username = false,
  }) async {
    if (busy) return false;
    busy = true;
    _notify();
    final epoch = _epoch;
    try {
      if (username) {
        await api!.changeUsername(currentPassword, replacement.trim());
      } else {
        await api!.changePassword(currentPassword, replacement);
      }
      if (!_valid(epoch)) return false;
      await logout();
      error = '账号信息已更新，请使用新凭据登录';
      _notify();
      return true;
    } catch (e) {
      if (_valid(epoch)) reportError(e);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> setTheme(String value) async {
    theme = value;
    _notify();
    await storage.saveTheme(value);
  }

  Future<void> logout({bool expired = false}) async {
    _epoch++;
    _searchEpoch++;
    transport.dispose();
    api?.close();
    api = null;
    account = null;
    profiles = [];
    models = [];
    _newChatModel = null;
    _newChatEngine = 'ekko-agent';
    workspaceNotice = null;
    conversations = [];
    selectedModel = null;
    sttProvider = null;
    codexInstalled = null;
    _resetChat();
    connected = false;
    busy = false;
    loadingSessions = false;
    search = '';
    error = expired ? '登录已过期或设备授权已撤销，请重新登录' : null;
    _notify();
    try {
      await storage.clearSession();
    } catch (e) {
      reportError('本地凭据清理失败，请在系统设置中清除应用数据');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _paintTimer?.cancel();
    _runTimer?.cancel();
    _syncTimer?.cancel();
    transport.dispose();
    api?.close();
    super.dispose();
  }
}
