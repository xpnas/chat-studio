import '../data/agent_catalog.dart';
import '../data/studio_protocol.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/server_address.dart';
import '../data/app_storage.dart';
import '../data/chat_transport.dart';
import '../data/models.dart';
import '../data/slash_commands.dart';
import '../data/queued_message.dart';
import '../data/speech_playback.dart';
import '../data/audio_transcription.dart';
import '../data/studio_api.dart';
import 'chat_timeline.dart';
import 'conversation_state.dart';

typedef ApiFactory = StudioApi Function(ServerAddress address);

class AppController extends ChangeNotifier {
  AppController({
    required this.storage,
    ChatTransport? transport,
    ApiFactory? apiFactory,
    SpeechPlayback? speech,
    AudioTranscription? transcription,
  }) : transcription = transcription ?? AudioTranscription(),
       speech = speech ?? SpeechPlayback(),
       transport = transport ?? SocketChatTransport(),
       _apiFactory = apiFactory ?? ((address) => StudioApi(address));
  final SpeechPlayback speech;
  final AudioTranscription transcription;
  bool foreground = true;
  void onBackground() {
    foreground = false;
    transcription.cancel();
    unawaited(speech.stop());
  }

  String audioAttachmentId(MessageAttachment file) =>
      'audio:$profile:$sessionId:${file.path}';
  void playAudioAttachment(MessageAttachment file) {
    if (!authenticated || api == null || !foreground || !file.isAudio) return;
    final id = audioAttachmentId(file);
    if (speech.activeId == id) {
      unawaited(speech.stop());
      return;
    }
    unawaited(speech.playAttachment(api!, id, file));
  }

  final AppStorage storage;
  final ChatTransport transport;
  final ApiFactory _apiFactory;
  StudioApi? api;
  ConversationState _view = ConversationState('default');
  final _states = <String, ConversationState>{};
  final _profileDrafts = <String, ConversationState>{};
  final _tasks = <String, ConversationTaskStatus>{};
  final _activityTimes = <String, int>{};
  int _navigationRevision = 0, _sessionOffset = 0;
  ChatTimeline get timeline => _view.timeline;
  ConversationDraft get draft => _view.draft;
  String _stateKey(String profile, String id) => '$profile::$id';
  String _key(ConversationState state) => _stateKey(state.profile, state.id!);
  ConversationState? _findState(String id) =>
      sessionId == id ? _view : _states[_stateKey(profile, id)];
  void _cacheView() {
    if (_view.id == null) {
      _profileDrafts[_view.profile] = _view;
      return;
    }
    _states.remove(_key(_view));
    _states[_key(_view)] = _view;
    final evictable = _states.entries
        .where(
          (entry) =>
              entry.value != _view &&
              !entry.value.timeline.working &&
              entry.value.timeline.interaction == null &&
              !(_tasks[entry.key]?.active ?? false) &&
              entry.value.draft.isEmpty,
        )
        .map((e) => e.key)
        .toList();
    for (final key in evictable) {
      if (_states.length <= 16) break;
      _states.remove(key)?.cancelTimers();
    }
  }

  ConversationTaskStatus taskStatus(Conversation conversation) {
    final key = _stateKey(conversation.profile, conversation.id);
    final state =
        conversation.id == sessionId && conversation.profile == profile
        ? _view
        : _states[key];
    var status = _tasks[key] ?? ConversationTaskStatus.idle;
    if (state?.timeline.interaction != null) {
      status = ConversationTaskStatus.waiting;
    } else if (state?.timeline.working == true &&
        status != ConversationTaskStatus.checking) {
      status = ConversationTaskStatus.running;
    }
    if (status.active &&
        (!connected ||
            conversation.profile != profile ||
            state?.syncing == true)) {
      return ConversationTaskStatus.checking;
    }
    return status;
  }

  bool get canConfigure =>
      authenticated && !busy && !working && !syncing && !loadingMessages;
  void _disposeStates() {
    transcription.clear();
    unawaited(speech.stop());
    for (final state in {..._states.values, _view}) {
      state.cancelTimers();
    }
    _states.clear();
    _profileDrafts.clear();
    _tasks.clear();
    _activityTimes.clear();
  }

  Account? account;
  List<String> profiles = [];
  List<ModelChoice> models = [];
  List<Conversation> conversations = [];
  ModelChoice? get selectedModel => _view.model;
  set selectedModel(ModelChoice? value) => _view.model = value;
  Conversation? get current => _view.conversation;
  set current(Conversation? value) => _view.conversation = value;
  String? get sessionId => _view.id;
  set sessionId(String? value) {
    _view.id = value;
    if (value != null) _cacheView();
  }

  String get engine => _view.engine;
  set engine(String value) => _view.engine = value;
  String get reasoningEffort => _view.reasoningEffort;
  set reasoningEffort(String value) => _view.reasoningEffort = value;
  ModelChoice? _newChatModel;
  String _newChatEngine = StudioProtocol.builtInAgentId, _newChatReasoning = '';
  String? workspaceNotice;
  String workspacePath = '';
  List<Map<String, dynamic>> workspaceFiles = const [];
  bool workspaceLoading = false;
  Future<void> refreshWorkspaceFiles({String? path}) async {
    if (api == null || sessionId == null) return;
    workspaceLoading = true;
    _notify();
    try {
      final data = await api!.workspaceFiles(sessionId!, path: path ?? '');
      workspacePath = text(data['current']).isEmpty
          ? (path ?? '')
          : text(data['current']);
      workspaceFiles = asList(
        data['files'] ?? data['entries'],
      ).map(asMap).toList();
    } catch (e) {
      reportError(e);
    } finally {
      workspaceLoading = false;
      _notify();
    }
  }

  Future<void> chooseWorkspace(String path) async {
    if (api == null || sessionId == null) return;
    try {
      await api!.setWorkspace(sessionId!, path);
      await refreshWorkspaceFiles();
    } catch (e) {
      reportError(e);
    }
  }

  Future<List<Map<String, dynamic>>> workspaceFolders() async => api == null
      ? const []
      : (asList(
          (await api!.workspaceFolders())['folders'],
        ).map(asMap).toList());
  bool readingHintSeen = true;
  String? get retryInput => _view.retryInput;
  set retryInput(String? value) => _view.retryInput = value;
  List<Map<String, dynamic>> get retryAttachments => _view.retryAttachments;
  set retryAttachments(List<Map<String, dynamic>> value) =>
      _view.retryAttachments = value;
  int retryRevision = 0;
  String? get _lastSubmittedInput => _view.submittedInput;
  set _lastSubmittedInput(String? value) => _view.submittedInput = value;
  List<Map<String, dynamic>> get _lastSubmittedAttachments =>
      _view.submittedAttachments;
  set _lastSubmittedAttachments(List<Map<String, dynamic>> value) =>
      _view.submittedAttachments = value;
  Future<void> _choiceWrite = Future.value();
  String get _choiceScope => '${api!.address.value}|${account!.id}|$profile';

  Future<void> _rememberChoice() async {
    if (api == null || account == null) return;
    _newChatModel = selectedModel;
    _newChatEngine = engine;
    _newChatReasoning = reasoningEffort;
    final scope = _choiceScope;
    final choice = {
      'model': selectedModel?.id,
      'provider': selectedModel?.provider,
      'engine': engine,
      'reasoning_effort': reasoningEffort,
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

  List<AgentChoice> agents = const [];
  bool agentsLoaded = false, agentsLoading = false;
  String? agentsError;
  int _agentsRequest = 0;
  List<AgentChoice> get availableAgents =>
      agents.where((a) => a.selectable).toList();
  bool? get codexInstalled =>
      agentsLoaded ? agents.any((a) => a.id == 'codex' && a.installed) : null;
  bool get newChatAgentAvailable =>
      agentsLoaded &&
      agentsError == null &&
      availableAgents.any((a) => a.id == engine);
  void _clearAgents() {
    _agentsRequest++;
    agents = const [];
    agentsLoaded = false;
    agentsLoading = false;
    agentsError = null;
  }

  Future<void> refreshAgents() async {
    final client = api;
    if (client == null || !authenticated) return;
    final epoch = _epoch, activeProfile = profile, request = ++_agentsRequest;
    bool valid() =>
        _valid(epoch) &&
        api == client &&
        profile == activeProfile &&
        request == _agentsRequest;
    agentsLoading = true;
    agentsError = null;
    _notify();
    try {
      final data = await client.request('/api/agents/availability');
      if (!valid()) return;
      agents = AgentChoice.parse(data['agents']);
      client.retryAgentIcons();
      agentsLoaded = true;
      final choices = availableAgents;
      if (!choices.any((a) => a.id == _newChatEngine) && choices.isNotEmpty) {
        _newChatEngine =
            choices
                .where((a) => a.id == StudioProtocol.builtInAgentId)
                .firstOrNull
                ?.id ??
            choices.first.id;
      }
      if (sessionId == null &&
          !choices.any((a) => a.id == engine) &&
          choices.isNotEmpty) {
        engine = _newChatEngine;
        workspaceNotice =
            '原 Agent 已不可用，新对话已改用 ${AgentChoice.metadata(engine).name}。';
      }
    } catch (_) {
      if (valid()) agentsError = '无法读取服务端 Agent，请重试';
    } finally {
      if (valid()) {
        agentsLoading = false;
        _notify();
      }
    }
  }

  String? sttProvider;
  String voiceHint = '请在服务端配置语音识别（STT）；仅配置 TTS 不能语音输入';
  int get chatRevision => _navigationRevision;
  String theme = 'system';
  String serverInput = '';
  bool savedLocalHttp = false;
  List<Map<String, dynamic>> servers = [];
  Future<void> _storageQueue = Future.value();
  Future<void> _writeStorage(Future<void> Function() action) {
    final next = _storageQueue.then((_) => action());
    _storageQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _persistSession() {
    final saved = _saved();
    servers = [saved, ...servers.where((s) => s['server'] != saved['server'])];
    final records = List<Map<String, dynamic>>.of(servers);
    return _writeStorage(() async {
      await storage.saveServers(records);
      await storage.saveSession(saved);
    });
  }

  Future<void> removeServer(String server) async {
    if (busy || (authenticated && api?.address.value == server)) return;
    if (api?.address.value == server) {
      api?.close();
      api = null;
    }
    final previous = servers;
    servers = servers.where((s) => s['server'] != server).toList();
    final updated = servers;
    final records = List<Map<String, dynamic>>.of(servers);
    try {
      await _writeStorage(() => storage.saveServers(records));
    } catch (e) {
      if (identical(servers, updated)) servers = previous;
      reportError('删除服务器记录失败：$e');
    }
    _notify();
  }

  Future<void> addServer() async {
    if (busy) return;
    await logout(preserveServer: true);
    serverInput = '';
    busy = false;
    savedLocalHttp = false;
    _notify();
  }

  Future<void> switchServer(String server) async {
    if (busy || (authenticated && api?.address.value == server)) return;
    final saved = servers.where((s) => s['server'] == server).firstOrNull;
    if (saved == null) return;
    // Invalidate socket callbacks, drafts, timers and media before changing origin.
    await logout(preserveServer: true);
    if (_disposed) return;
    final epoch = ++_epoch;
    serverInput = server;
    savedLocalHttp = flag(saved['allowLocalHttp']);
    if (text(saved['token']).isEmpty) {
      busy = false;
      _notify();
      return;
    }
    busy = true;
    _notify();
    try {
      final client =
          _apiFactory(
              ServerAddress.parse(server, allowLocalHttp: savedLocalHttp),
            )
            ..token = text(saved['token'])
            ..profile = text(saved['profile']).isEmpty
                ? 'default'
                : text(saved['profile']);
      _bind(client);
      final user = await client.me();
      if (!_valid(epoch)) return;
      await _persistSession();
      if (!_valid(epoch)) return;
      account = user;
      await _loadWorkspace(epoch);
    } catch (e) {
      if (_valid(epoch)) reportError('连接未完成，可重试或重新登录。$e');
    } finally {
      if (_valid(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  String search = '';
  String? error;
  bool booting = true, busy = false, loadingSessions = false;
  bool connected = false, hasMoreSessions = false;
  bool get loadingMessages => _view.loading;
  set loadingMessages(bool value) => _view.loading = value;
  bool get syncing => _view.syncing;
  set syncing(bool value) => _view.syncing = value;
  String? get historyPageError => _view.historyPageError;
  bool get canLoadEarlier =>
      authenticated &&
      connected &&
      !busy &&
      !syncing &&
      !loadingMessages &&
      sessionId != null &&
      hasMoreMessages &&
      historyPageError == null;
  bool get hasMoreMessages => _view.hasMore;
  set hasMoreMessages(bool value) => _view.hasMore = value;
  int _epoch = 0, _chatEpoch = 0, _searchEpoch = 0;
  bool _disposed = false;
  Timer? _paintTimer;
  bool get authenticated => account != null;
  bool get working => timeline.working;
  bool get canSend =>
      authenticated &&
      profiles.isNotEmpty &&
      connected &&
      !syncing &&
      !loadingMessages &&
      !working &&
      !(_tasks[sessionId == null ? '' : _stateKey(profile, sessionId!)]
              ?.active ??
          false) &&
      !busy &&
      current?.canContinue != false &&
      (sessionId != null || newChatAgentAvailable);
  String get profile => api?.profile ?? 'default';
  String get title => current?.title ?? '新对话';
  bool get allowLocalHttp => api?.address.allowLocalHttp ?? savedLocalHttp;

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
      if (api != value) return;
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
      servers = await storage.readServers();
      final saved = await storage.readSession();
      if (saved != null &&
          !servers.any((s) => s['server'] == saved['server'])) {
        servers = [saved, ...servers];
        await storage.saveServers(servers);
      }
      if (saved != null && _valid(epoch)) {
        serverInput = text(saved['server']);
        savedLocalHttp = flag(saved['allowLocalHttp']);
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
      await _persistSession();
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
      if (sessionId == null && _view.profile != profile) {
        _view = ConversationState(profile);
        _navigationRevision++;
      }
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
      _newChatReasoning = storedModel == null
          ? ''
          : normalizeReasoningEffort(remembered?['reasoning_effort']);
      final rememberedAgent = AgentChoice.canonicalId(
        text(remembered?['engine']),
      );
      _newChatEngine = AgentChoice.supportedIds.contains(rememberedAgent)
          ? rememberedAgent
          : StudioProtocol.builtInAgentId;
      workspaceNotice = remembered?['model'] != null && storedModel == null
          ? '上次使用的模型已不可用，新对话已改用服务端默认模型。'
          : null;
      if (sessionId == null) {
        selectedModel = _newChatModel;
        engine = _newChatEngine;
        reasoningEffort = _newChatReasoning;
      }
      await refreshCapabilities();
      if (!_valid(epoch)) return;
      await _persistSession();
      if (!_valid(epoch)) return;
      reconnect();
      await refreshSessions();
    } catch (e) {
      if (_valid(epoch)) reportError(e);
    }
  }

  Future<void> refreshCapabilities({bool includeAgents = true}) async {
    final client = api;
    if (client == null) return;
    final epoch = _epoch, activeProfile = profile;
    bool valid() => _valid(epoch) && api == client && profile == activeProfile;
    await Future.wait([
      if (includeAgents) refreshAgents(),
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
    final socketProfile = profile;
    for (final state in {..._states.values, _view}) {
      state.cancelTimers();
      state.syncing = false;
      if (state.timeline.working) state.timeline.markUncertain();
    }
    transport.connect(api!, (event, data) {
      if (_valid(epoch) && profile == socketProfile) _event(event, data);
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
    if (busy || value == profile || !profiles.contains(value)) {
      return;
    }
    _cacheView();
    for (final state in _states.values) {
      state.cancelTimers();
      state.syncing = false;
      state.loading = false;
    }
    final epoch = ++_epoch;
    transport.dispose();
    connected = false;
    syncing = false;
    busy = true;
    api!.profile = value;
    _view = _profileDrafts.remove(value) ?? ConversationState(value);
    _navigationRevision++;
    _chatEpoch++;
    _sessionOffset = 0;
    search = '';
    _searchEpoch++;
    conversations = [];
    models = [];
    selectedModel = null;
    sttProvider = null;
    _clearAgents();
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
        offset: more ? _sessionOffset : 0,
        search: search,
      );
      if (!_valid(epoch) || searchEpoch != _searchEpoch) return;
      final rows = asList(
        data[search.isEmpty ? 'sessions' : 'results'],
      ).map((s) => Conversation.fromJson(asMap(s))).toList();
      _sessionOffset = (more ? _sessionOffset : 0) + rows.length;
      if (!more) _sessionOffset = rows.length;
      final local = _states.values
          .where(
            (s) =>
                s.profile == profile &&
                s.conversation != null &&
                (_tasks[_key(s)]?.active ?? s.timeline.working) &&
                !rows.any((r) => r.id == s.id) &&
                (search.isEmpty ||
                    s.conversation!.title.toLowerCase().contains(
                      search.toLowerCase(),
                    )),
          )
          .map((s) => s.conversation!);
      // A normal refresh is authoritative: do not retain deleted server rows.
      // Only locally active runs are merged because they may not be indexed yet.
      final merged = [if (more) ...conversations, ...local, ...rows];
      conversations = {for (final s in merged) s.id: s}.values.toList();
      for (final row in rows) {
        final state = _findState(row.id);
        if (state != null) state.conversation = row;
      }
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

  void _resetChat({bool preserve = true}) {
    transcription.cancel();
    unawaited(speech.stop());
    if (preserve) _cacheView();
    _chatEpoch++;
    _navigationRevision++;
    _view = ConversationState(profile);
  }

  void newChat() {
    if (busy) return;
    _resetChat();
    selectedModel = _newChatModel;
    engine = _newChatEngine;
    reasoningEffort = _newChatReasoning;
    error = null;
    unawaited(refreshAgents());
    _notify();
  }

  Future<void> openConversation(Conversation conversation) async {
    if (busy) return;
    transcription.cancel();
    unawaited(speech.stop());
    if (conversation.profile != profile) {
      await switchProfile(conversation.profile);
      if (!authenticated || conversation.profile != profile) return;
    }
    _cacheView();
    _chatEpoch++;
    _navigationRevision++;
    final state = _states.putIfAbsent(
      _stateKey(profile, conversation.id),
      () => ConversationState(profile)..id = conversation.id,
    );
    _view = state;
    current = conversation;
    engine = conversation.agent.isEmpty
        ? 'hermes'
        : AgentChoice.canonicalId(conversation.agent);
    if (state.model == null) {
      selectedModel =
          models
              .where(
                (m) =>
                    m.id == conversation.model &&
                    m.provider == conversation.provider,
              )
              .firstOrNull ??
          (conversation.model.isEmpty
              ? _newChatModel
              : ModelChoice(
                  id: conversation.model,
                  provider: conversation.provider,
                  label: conversation.model,
                ));
      reasoningEffort = normalizeReasoningEffort(conversation.reasoningEffort);
    }
    error = null;
    _notify();
    // An active conversation must be hydrated by a single snapshot + replay,
    // not first painted from a partial DB page then immediately replaced.
    final active =
        state.timeline.working || (_tasks[_key(state)]?.active ?? false);
    if (state.timeline.messages.isEmpty && !(connected && active)) {
      await _loadHistoryState(state);
    }
    if (_view != state || !authenticated || state.profile != profile) return;
    if (connected) _resumeState(state);
  }

  Future<void> loadHistory({bool more = false}) =>
      _loadHistoryState(_view, more: more);

  Future<void> retryEarlierHistory() async {
    if (!authenticated ||
        !connected ||
        syncing ||
        loadingMessages ||
        !hasMoreMessages) {
      return;
    }
    _view.historyPageError = null;
    await _loadHistoryState(_view, more: true);
  }

  Future<void> _loadHistoryState(
    ConversationState state, {
    bool more = false,
  }) async {
    final sid = state.id, client = api;
    if (sid == null ||
        state.loading ||
        client == null ||
        state.profile != profile ||
        state.syncing ||
        (more &&
            (!connected || !state.hasMore || state.historyPageError != null))) {
      return;
    }
    final epoch = _epoch,
        revision = state.revision,
        requestId = ++state.loadRequest;
    state.loading = true;
    if (state == _view) _notify();
    try {
      final page = await client.messages(sid, offset: more ? state.offset : 0);
      if (!_valid(epoch) ||
          state.loadRequest != requestId ||
          (!more && state.revision != revision) ||
          client != api) {
        return;
      }
      if (more && page.hasMore && page.offset <= state.offset) {
        // Malformed/non-advancing pages must not cause an automatic request loop.
        state.historyPageError = '历史分页未推进，请重试';
        return;
      }
      if (more) {
        state.historyPageError = null;
        state.timeline.prepend(page.messages);
      } else {
        state.timeline.replace(page.messages, keepOlder: page.hasMore);
      }
      state.timeline.mergeTaskPlans(page.taskPlans);
      if (more ||
          state.offset <= page.offset ||
          state.timeline.messages.length <= page.messages.length) {
        state.offset = page.offset;
        state.hasMore = page.hasMore;
      }
    } catch (e) {
      if (_valid(epoch) && state.loadRequest == requestId && client == api) {
        if (more) {
          state.historyPageError = '较早消息加载失败，请重试';
        } else if (state == _view && state.revision == revision) {
          reportError(e);
        }
      }
    } finally {
      if (_valid(epoch) && state.loadRequest == requestId) {
        state.loading = false;
        if (state == _view) _notify();
      }
    }
  }

  Future<void> chooseReasoningEffort(String value) async {
    if (!canConfigure || !reasoningEffortLabels.containsKey(value)) return;
    final state = _view, epoch = _epoch;
    busy = true;
    _notify();
    try {
      if (state.id != null) await api!.setReasoningEffort(state.id!, value);
      if (!_valid(epoch) || _view != state) return;
      reasoningEffort = value;
      await _rememberChoice();
    } catch (e) {
      if (_valid(epoch) && _view == state) reportError(e);
    } finally {
      if (_valid(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> chooseModel(ModelChoice model) async {
    if (!canConfigure) return;
    final epoch = _epoch, chatEpoch = _chatEpoch;
    busy = true;
    _notify();
    try {
      if (current != null) await api!.setModel(current!.id, model);
      if (_valid(epoch) && chatEpoch == _chatEpoch) {
        selectedModel = model;
        reasoningEffort = '';
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
        !agentsLoading &&
        agentsError == null &&
        availableAgents.any((a) => a.id == value)) {
      engine = value;
      unawaited(_rememberChoice());
      _notify();
    }
  }

  bool isBridgeCommand(String input) =>
      engine == 'hermes' && readCommandName(input) != null;

  bool get canQueue =>
      authenticated &&
      profiles.isNotEmpty &&
      connected &&
      !syncing &&
      !loadingMessages &&
      !busy &&
      current?.canContinue != false &&
      working &&
      !_view.awaitingStart;

  bool canSubmit(String input) =>
      canSend ||
      canQueue ||
      (isBridgeCommand(input) &&
          authenticated &&
          profiles.isNotEmpty &&
          connected &&
          !syncing &&
          !loadingMessages &&
          !busy &&
          current?.canContinue != false &&
          working);

  bool send(String input, {List<Map<String, dynamic>> attachments = const []}) {
    input = input.trim();
    if ((input.isEmpty && attachments.isEmpty) || !canSubmit(input)) {
      return false;
    }
    if (input.length > 64000) {
      reportError('消息过长，请拆分后发送（最多 64000 字符）');
      return false;
    }
    final queued = working && !isBridgeCommand(input);
    if (queued && !canQueue) return false;
    if (working && isBridgeCommand(input) && attachments.isNotEmpty) {
      return false;
    }
    final command = isBridgeCommand(input) && attachments.isEmpty;
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
        if (engine != 'hermes' && engine != StudioProtocol.builtInAgentId)
          'mode': 'scoped',
        'reasoning_effort': reasoningEffort,
        if (selectedModel != null) 'model': selectedModel!.id,
        if (selectedModel != null) 'provider': selectedModel!.provider,
        if (selectedModel?.apiMode.isNotEmpty == true)
          'api_mode': selectedModel!.apiMode,
      });
      _chatEpoch++;
      _view.revision++;
      if (queued) {
        timeline.queue = [
          ...timeline.queue,
          QueuedMessage(
            queueId,
            input,
            status: 'sending',
            attachments: MessageAttachment.parse(attachments),
          ),
        ];
        final state = _view;
        state.queueTimer?.cancel();
        state.queueTimer = Timer(const Duration(seconds: 15), () {
          if (_disposed || state.profile != profile) return;
          state.timeline.queue = state.timeline.queue
              .map((q) => q.status == 'sending' ? q.withStatus('uncertain') : q)
              .toList();
          if (connected) _resumeState(state);
          _notify();
        });
        _notify();
        return true;
      }
      if (!command) {
        _lastSubmittedInput = input;
        _lastSubmittedAttachments = List.of(attachments);
      }
      sessionId = sid;
      if (command) {
        timeline.messages = [
          ...timeline.messages,
          ChatMessage(id: 'local:$queueId', role: 'command', content: input),
        ];
      } else {
        timeline.begin(
          [
            input,
            if (attachments.isNotEmpty) messageText(attachments),
          ].where((s) => s.isNotEmpty).join('\n'),
          'local:$queueId',
          attachments: MessageAttachment.parse(attachments),
        );
      }
      final state = _view;
      state.conversation ??= Conversation(
        id: sid,
        title: input.isEmpty
            ? '附件对话'
            : String.fromCharCodes(input.runes.take(48)),
        profile: profile,
        agent: engine,
        source: engine == 'hermes' ? '' : 'coding_agent',
        model: selectedModel?.id ?? '',
        provider: selectedModel?.provider ?? '',
        reasoningEffort: reasoningEffort,
      );
      if (!conversations.any((c) => c.id == sid)) {
        conversations = [state.conversation!, ...conversations];
      }
      _tasks[_key(state)] = timeline.working
          ? ConversationTaskStatus.running
          : ConversationTaskStatus.idle;
      error = null;
      if (!command) {
        state.awaitingStart = true;
        state.submittedAt = DateTime.now();
        state.runTimer?.cancel();
        final epoch = _epoch;
        state.runTimer = Timer(const Duration(seconds: 25), () {
          if (!_valid(epoch) || !state.timeline.working) return;
          state.awaitingStart = false;
          state.timeline.markUncertain();
          _tasks[_key(state)] = ConversationTaskStatus.checking;
          if (connected && state.profile == profile) _resumeState(state);
          _notify();
        });
      }
      _notify();
      return true;
    } catch (e) {
      reportError(e);
      return false;
    }
  }

  void stop({String? expectedSession}) {
    if (!connected ||
        sessionId == null ||
        current?.canContinue == false ||
        (expectedSession != null && expectedSession != sessionId)) {
      return;
    }
    try {
      transport.emit('abort', {'session_id': sessionId});
      timeline.activity = '正在停止';
      _notify();
    } catch (e) {
      reportError(e);
    }
  }

  void _resumeState(ConversationState state) {
    if (state.id == null ||
        !connected ||
        state.profile != profile ||
        state.syncing ||
        state.awaitingStart) {
      return;
    }
    state.syncing = true;
    state.loadRequest++;
    state.loading = false;
    state.timeline.markUncertain();
    state.syncTimer?.cancel();
    final epoch = _epoch;
    state.syncTimer = Timer(const Duration(seconds: 20), () {
      if (!_valid(epoch)) return;
      state.syncing = false;
      state.timeline.markUncertain();
      _tasks[_key(state)] = ConversationTaskStatus.checking;
      if (state == _view) error = '同步超时，请重新连接；消息不会自动重发。';
      _notify();
    });
    try {
      transport.emit('resume', {'session_id': state.id});
    } catch (e) {
      state.syncing = false;
      state.syncTimer?.cancel();
      if (state == _view) reportError(e);
    }
    _notify();
  }

  void _recoverSessions() {
    for (final state in _states.values.toList()) {
      if (state != _view &&
          state.profile == profile &&
          (state.timeline.working ||
              state.timeline.interaction != null ||
              (_tasks[_key(state)]?.active ?? false))) {
        _resumeState(state);
      }
    }
    _resumeState(_view);
  }

  void onForeground() {
    foreground = true;
    if (!authenticated) return;
    if (sessionId == null) unawaited(refreshAgents());
    if (connected) {
      _recoverSessions();
    } else {
      reconnect();
    }
  }

  void _activity(
    String id,
    ConversationTaskStatus status, {
    int timestamp = 0,
  }) {
    if (id.isEmpty) return;
    final key = _stateKey(profile, id);
    if (timestamp > 0 && timestamp < (_activityTimes[key] ?? 0)) return;
    if (timestamp > 0) _activityTimes[key] = timestamp;
    _tasks[key] = status;
  }

  void _event(String event, Map<String, dynamic> data) {
    if (event == 'connected') {
      connected = true;
      for (final state in {..._states.values, _view}) {
        state.syncing = false;
      }
      _recoverSessions();
      _notify();
      return;
    }
    if (event == 'disconnected' || event == 'connection.error') {
      connected = false;
      for (final state in {..._states.values, _view}) {
        state.timeline.markUncertain();
        state.awaitingStart = false;
        state.timeline.queue = state.timeline.queue
            .map((q) => q.status == 'sending' ? q.withStatus('uncertain') : q)
            .toList();
        state.cancelTimers();
        state.syncing = false;
      }
      if (event == 'connection.error') {
        if (text(data['error']).toLowerCase().contains('auth')) {
          unawaited(logout(expired: true));
          return;
        }
        error = '聊天连接失败，请检查 WebSocket 代理和 Profile 权限';
      }
      _notify();
      return;
    }
    if (text(data['profile']).isNotEmpty && text(data['profile']) != profile) {
      return;
    }
    if (event == 'session.activity.snapshot') {
      final timestamp = integer(data['timestamp']);
      final running = <String>{};
      for (final row in asList(data['sessions']).map(asMap)) {
        final id = text(row['session_id']);
        if (id.isEmpty || row['status'] != 'running') continue;
        running.add(id);
        _activity(id, ConversationTaskStatus.running, timestamp: timestamp);
      }
      // A snapshot is a point-in-time view. Missing cached runs are unknown,
      // never proof of completion; reconcile them via resume.
      for (final state in _states.values.toList()) {
        if (state.profile != profile ||
            state.id == null ||
            running.contains(state.id) ||
            state.awaitingStart ||
            (state.submittedAt != null &&
                timestamp > 0 &&
                timestamp < state.submittedAt!.millisecondsSinceEpoch)) {
          continue;
        }
        if (state.timeline.working || (_tasks[_key(state)]?.active ?? false)) {
          _activity(
            state.id!,
            ConversationTaskStatus.checking,
            timestamp: timestamp,
          );
          _resumeState(state);
        }
      }
      _notify();
      return;
    }
    final sid = text(data['session_id']);
    if (event == 'session.activity') {
      final status = switch (text(data['status'])) {
        'running' => ConversationTaskStatus.running,
        'completed' => ConversationTaskStatus.completed,
        'failed' => ConversationTaskStatus.failed,
        _ => null,
      };
      if (status == null || sid.isEmpty) return;
      final stamp = integer(data['timestamp']);
      if (stamp > 0 && stamp < (_activityTimes[_stateKey(profile, sid)] ?? 0)) {
        return;
      }
      final state = _findState(sid);
      if (state?.submittedAt != null &&
          stamp > 0 &&
          stamp < state!.submittedAt!.millisecondsSinceEpoch) {
        return;
      }
      _activity(sid, status, timestamp: stamp);
      if (state != null &&
          !state.syncing &&
          ((status == ConversationTaskStatus.running &&
                  !state.timeline.working) ||
              (!status.active && state.timeline.working))) {
        _resumeState(state);
      }
      _notify();
      return;
    }
    final state = _findState(sid);
    if (state == null || state.profile != profile) {
      if (['approval.resolved', 'clarify.resolved'].contains(event) &&
          _tasks[_stateKey(profile, sid)] == ConversationTaskStatus.waiting) {
        _activity(sid, ConversationTaskStatus.running);
        _notify();
      }
      // Profile-wide interaction broadcasts can arrive before a conversation
      // has been opened. Mark its list entry; resume hydrates the prompt on tap.
      if (['approval.requested', 'clarify.requested'].contains(event) &&
          conversations.any((c) => c.id == sid) &&
          (data['remaining_timeout_ms'] == null ||
              integer(data['remaining_timeout_ms']) > 0)) {
        _activity(sid, ConversationTaskStatus.waiting);
        _notify();
      }
      return;
    }
    if (event == 'session.command') {
      state.awaitingStart = false;
      state.timeline.apply(event, data);
      state.revision++;
      state.runTimer?.cancel();
      _activity(
        sid,
        state.timeline.working
            ? ConversationTaskStatus.running
            : data['ok'] == false
            ? ConversationTaskStatus.failed
            : ConversationTaskStatus.idle,
      );
      if (data['ok'] != false &&
          data['action'] == 'title' &&
          data['title'] is String) {
        final old = state.conversation;
        if (old != null) {
          final renamed = Conversation(
            id: old.id,
            title: text(data['title']),
            profile: old.profile,
            agent: old.agent,
            source: old.source,
            model: old.model,
            provider: old.provider,
            reasoningEffort: old.reasoningEffort,
          );
          state.conversation = renamed;
          conversations = conversations
              .map((c) => c.id == sid ? renamed : c)
              .toList();
        }
      }
      if (data['ok'] != false && data['action'] == 'clear') {
        state.loadRequest++;
        state.loading = false;
        if (flag(data['clearHistory'])) {
          state.offset = 0;
          state.hasMore = false;
        }
      }
      if (data['ok'] != false && data['action'] == 'branch') {
        final branch = asMap(data['branchSession']);
        final id = text(data['newSessionId'] ?? branch['id']);
        if (id.isNotEmpty) {
          final conversation = Conversation.fromJson({
            ...branch,
            'id': id,
            'profile': state.profile,
            'title': data['newSessionTitle'] ?? branch['title'] ?? 'Branch',
          });
          conversations = [
            conversation,
            ...conversations.where((c) => c.id != id),
          ];
          // A late response must not hijack a different conversation.
          if (state == _view) unawaited(openConversation(conversation));
        }
      }
      _notify();
      return;
    }
    if (event == 'resumed') {
      state.awaitingStart = false;
      state.syncTimer?.cancel();
      state.runTimer?.cancel();
      state.syncing = false;
      state.loading = false;
      state.revision++;
      state.loadRequest++;
      if (state == _view) _chatEpoch++;
      state.queueTimer?.cancel();
      state.timeline.resume(data);
      _armInteraction(state);
      final loaded = integer(data['messageLoadedCount']);
      state.offset = loaded == 0 ? asList(data['messages']).length : loaded;
      state.hasMore = flag(data['hasMoreBefore']);
      if (data.containsKey('reasoning_effort')) {
        state.reasoningEffort = normalizeReasoningEffort(
          data['reasoning_effort'],
        );
      }
      final model = text(data['model']), provider = text(data['provider']);
      if (model.isNotEmpty) {
        state.model =
            models
                .where((m) => m.id == model && m.provider == provider)
                .firstOrNull ??
            ModelChoice(
              id: model,
              provider: provider,
              label: model,
              apiMode: text(data['api_mode']),
            );
      }
      final status = state.timeline.interaction != null
          ? ConversationTaskStatus.waiting
          : state.timeline.working || integer(data['queueLength']) > 0
          ? ConversationTaskStatus.running
          : state.timeline.messages.any((m) => m.delivery == 'uncertain')
          ? ConversationTaskStatus.checking
          : state.timeline.messages
                    .where((m) => m.role == 'user')
                    .lastOrNull
                    ?.delivery ==
                'failed'
          ? ConversationTaskStatus.failed
          : ConversationTaskStatus.idle;
      _activity(sid, status);
      _notify();
      return;
    }
    if (event == 'run.failed' &&
        state.syncing &&
        text(data['run_id']).isEmpty) {
      state.syncing = false;
      state.syncTimer?.cancel();
      _activity(sid, ConversationTaskStatus.checking);
      if (state == _view) {
        error = text(data['error']).isEmpty
            ? '同步会话失败，请重新连接核对'
            : text(data['error']);
      }
      _notify();
      return;
    }
    final failedQueued =
        event == 'run.failed' &&
        state.timeline.queue.any((q) => q.id == text(data['queue_id']));
    if (!state.timeline.apply(event, data)) return;
    if (failedQueued) {
      _notify();
      return;
    }
    if (event == 'run.queued') {
      state.queueTimer?.cancel();
      _notify();
      return;
    }
    if (['run.started', 'message.delta', 'message.interim'].contains(event)) {
      state.awaitingStart = false;
      state.revision++;
      state.runTimer?.cancel();
      _activity(sid, ConversationTaskStatus.running);
    }
    if (['approval.requested', 'clarify.requested'].contains(event) &&
        state.timeline.interaction != null) {
      state.awaitingStart = false;
      state.runTimer?.cancel();
      _armInteraction(state);
      _activity(sid, ConversationTaskStatus.waiting);
    }
    if (['approval.resolved', 'clarify.resolved'].contains(event)) {
      state.responseTimer?.cancel();
      _armInteraction(state);
      _activity(
        sid,
        state.timeline.interaction != null
            ? ConversationTaskStatus.waiting
            : ConversationTaskStatus.running,
      );
    }
    if (['run.completed', 'run.failed', 'abort.completed'].contains(event)) {
      state.awaitingStart = false;
      state.runTimer?.cancel();
      state.syncing = false;
      state.syncTimer?.cancel();
      state.revision++;
      final queued =
          integer(data['queue_remaining'] ?? data['queue_length']) > 0 ||
          state.timeline.queue.isNotEmpty;
      if (queued) state.timeline.working = true;
      _activity(
        sid,
        queued
            ? ConversationTaskStatus.running
            : event == 'run.failed'
            ? ConversationTaskStatus.failed
            : ConversationTaskStatus.completed,
      );
      if (state == _view &&
          event != 'run.failed' &&
          !queued &&
          state.timeline.queue.isEmpty) {
        unawaited(_loadHistoryState(state));
      }
      unawaited(refreshSessions());
    }
    final streaming = [
      'message.delta',
      'message.interim',
      'reasoning.delta',
      'thinking.delta',
    ].contains(event);
    if (state != _view && streaming) return;
    _notify(batch: streaming);
  }

  void respondToInteraction(
    String response, {
    String? expectedSession,
    String? expectedInteraction,
  }) {
    final pending = timeline.interaction;
    if (pending == null ||
        !connected ||
        syncing ||
        !timeline.canApprove(response) ||
        current?.canContinue == false ||
        (expectedSession != null && expectedSession != sessionId)) {
      return;
    }
    final approval = pending['kind'] == 'approval.requested';
    if (expectedInteraction != null &&
        expectedInteraction !=
            text(pending[approval ? 'approval_id' : 'clarify_id'])) {
      return;
    }
    try {
      transport.emit(approval ? 'approval.respond' : 'clarify.respond', {
        'session_id': sessionId,
        if (approval) 'approval_id': pending['approval_id'],
        if (!approval) 'clarify_id': pending['clarify_id'],
        approval ? 'choice' : 'response': response,
      });
      // Keep prompt locked until authoritative success/failure; do not double-submit.
      timeline.interactionSubmitting = true;
      timeline.interactionError = null;
      final state = _view;
      state.responseTimer?.cancel();
      state.responseTimer = Timer(const Duration(seconds: 15), () {
        if (_disposed || state.timeline.interaction != pending) return;
        // Outcome unknown: stay locked until authoritative resume/result.
        state.timeline.interactionSubmitting = true;
        state.timeline.interactionError = '审批响应超时，请同步状态后重试；不会自动重发';
        _notify();
      });
      timeline.activity = '等待服务器确认';
      _notify();
    } catch (e) {
      reportError(e);
    }
  }

  void _armInteraction(ConversationState state) {
    state.interactionTimer?.cancel();
    final deadline = state.timeline.interactionDeadline;
    if (state.timeline.interaction == null || deadline == null) return;
    final duration = deadline.difference(DateTime.now());
    state.interactionTimer = Timer(
      duration.isNegative ? Duration.zero : duration,
      () {
        if (_disposed || state.timeline.interaction == null) return;
        state.timeline.interactionSubmitting = false;
        state.timeline.interactionError = '审批已过期，请同步会话';
        _notify();
      },
    );
  }

  void syncCurrentConversation() => _resumeState(_view);

  void cancelQueued(String id, {required String expectedSession}) {
    if (!connected ||
        syncing ||
        expectedSession != sessionId ||
        current?.canContinue == false) {
      return;
    }
    if (!timeline.queue.any((q) => q.id == id && q.status == 'queued')) return;
    try {
      timeline.queue = timeline.queue
          .map((q) => q.id == id ? q.withStatus('canceling') : q)
          .toList();
      _notify();
      transport.emit('cancel_queued_run', {
        'session_id': sessionId,
        'queue_id': id,
      });
      final state = _view;
      state.queueTimer?.cancel();
      state.queueTimer = Timer(const Duration(seconds: 15), () {
        if (!_disposed && state.profile == profile && connected) {
          _resumeState(state);
        }
      });
    } catch (e) {
      timeline.queue = timeline.queue
          .map((q) => q.id == id ? q.withStatus('queued') : q)
          .toList();
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
          reasoningEffort: conversation.reasoningEffort,
        );
      }
      await refreshSessions();
    } catch (e) {
      if (_valid(epoch)) reportError(e);
    }
  }

  Future<void> deleteConversation(Conversation conversation) async {
    if (taskStatus(conversation).active) return;
    final epoch = _epoch;
    try {
      await api!.delete(conversation.id);
      if (!_valid(epoch)) return;
      final removed = _states.remove(
        _stateKey(conversation.profile, conversation.id),
      );
      removed?.cancelTimers();
      _tasks.remove(_stateKey(conversation.profile, conversation.id));
      if (sessionId == conversation.id) _resetChat(preserve: false);
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

  Future<void> logout({
    bool expired = false,
    bool preserveServer = false,
  }) async {
    final oldServer = api?.address.value;
    if (api != null) savedLocalHttp = api!.address.allowLocalHttp;
    if (!preserveServer && oldServer != null) {
      servers = [
        for (final record in servers)
          if (record['server'] == oldServer)
            {...record, 'token': ''}
          else
            record,
      ];
    }
    final records = List<Map<String, dynamic>>.of(servers);
    _epoch++;
    _searchEpoch++;
    transport.dispose();
    _disposeStates();
    api?.close();
    api = null;
    account = null;
    profiles = [];
    models = [];
    _newChatModel = null;
    _newChatEngine = StudioProtocol.builtInAgentId;
    _newChatReasoning = '';
    workspaceNotice = null;
    conversations = [];
    selectedModel = null;
    sttProvider = null;
    _clearAgents();
    _resetChat(preserve: false);
    connected = false;
    busy = preserveServer;
    loadingSessions = false;
    search = '';
    error = expired ? '登录已过期或设备授权已撤销，请重新登录' : null;
    _notify();
    try {
      await _writeStorage(() async {
        try {
          await storage.saveServers(records);
        } finally {
          // Still attempt to remove the active session if the record write fails.
          await storage.clearSession();
        }
      });
    } catch (e) {
      reportError('本地凭据清理失败，请在系统设置中清除应用数据');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _paintTimer?.cancel();
    _disposeStates();
    transport.dispose();
    api?.close();
    transcription.dispose();
    speech.dispose();
    super.dispose();
  }
}
