import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../state/app_controller.dart';
import '../state/conversation_state.dart';
import 'profile_screen.dart';
import 'theme.dart';
import 'widgets/message_bubble.dart';
import 'widgets/chat_composer.dart';
import 'widgets/reading_handle.dart';
import 'widgets/reading_anchor.dart';
import 'widgets/conversation_activity_mark.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _input = TextEditingController(), _search = TextEditingController();
  final _scroll = ScrollController();
  final _readingProgress = ValueNotifier<double>(0);
  Timer? _searchTimer;
  String? _lastSession;
  ConversationDraft? _lastDraft;
  bool _restoringView = false;
  bool _historyCheckScheduled = false;
  int _lastLength = 0, _liveRevision = 0;
  bool _hasNewContent = false;
  final _anchors = ReadingAnchor();
  final _stage = GlobalKey();
  int _gestureRevision = 0;
  bool _hintOffered = false;
  int _hintSerial = 0;
  bool _showReadingHint = false;
  Timer? _hintTimer;
  bool _showJump = false;
  bool _composerCollapsed = false, _userScrolling = false;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    _lastDraft = c.draft;
    _lastSession = c.sessionId;
    c.addListener(_changed);
    _scroll.addListener(_scrollChanged);
    _scheduleEarlierHistory();
  }

  void _scrollChanged() {
    if (!mounted || !_scroll.hasClients) return;
    _updateReadingProgress();
    _scheduleEarlierHistory();
    if (!_restoringView && identical(_lastDraft, c.draft)) {
      c.draft.scrollOffset = _scroll.offset;
    }
    final pixels = _scroll.position.pixels.clamp(
      _scroll.position.minScrollExtent,
      _scroll.position.maxScrollExtent,
    );
    final showJump = pixels > 220;
    final restore = _composerCollapsed && pixels <= 24;
    if (showJump != _showJump || restore || (pixels <= 24 && _hasNewContent)) {
      setState(() {
        if (pixels <= 24) _hasNewContent = false;
        _showJump = showJump;
        if (restore) _composerCollapsed = false;
      });
    }
  }

  void _scheduleEarlierHistory() {
    if (!mounted || _historyCheckScheduled) return;
    _historyCheckScheduled = true;
    final draft = c.draft;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyCheckScheduled = false;
      if (!mounted ||
          !identical(draft, c.draft) ||
          _restoringView ||
          !_scroll.hasClients ||
          !_scroll.position.hasContentDimensions ||
          !c.canLoadEarlier) {
        return;
      }
      // reverse:true: older messages live at maxScrollExtent, not at zero.
      // Also fill a viewport with short/hidden-only pages until it can scroll.
      if (_scroll.position.extentAfter <= 240) {
        unawaited(c.loadHistory(more: true));
      }
    });
  }

  void _updateReadingProgress() {
    if (mounted &&
        _scroll.hasClients &&
        _scroll.position.hasContentDimensions) {
      _readingProgress.value = historyReadProgress(_scroll.position);
    }
  }

  bool _chatScrolled(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _gestureRevision++;
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _userScrolling = false;
    } else if (notification is ScrollUpdateNotification &&
        _userScrolling &&
        (notification.scrollDelta ?? 0) > 0 &&
        notification.metrics.pixels > 160 &&
        !_composerCollapsed &&
        c.timeline.messages.isNotEmpty) {
      // reverse:true: increasing offset means browsing older messages. Ignore
      // programmatic restores, pagination and streaming layout changes.
      setState(() => _composerCollapsed = true);
      _offerReadingHint();
    }
    return false;
  }

  void _offerReadingHint() {
    if (_hintOffered || c.readingHintSeen) return;
    _hintOffered = true;
    final serial = ++_hintSerial;
    unawaited(c.markReadingHintSeen());
    setState(() => _showReadingHint = true);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && serial == _hintSerial) {
        setState(() => _showReadingHint = false);
      }
    });
  }

  void _expandComposer() {
    // Expanding while a fling is settling should not immediately fold again.
    _userScrolling = false;
    setState(() => _composerCollapsed = false);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _scheduleEarlierHistory();
    final session = c.sessionId, gesture = _gestureRevision;
    if (session == _lastSession &&
        !_userScrolling &&
        _stage.currentContext != null) {
      final box = _stage.currentContext!.findRenderObject() as RenderBox;
      _anchors.preserve(
        _scroll,
        box.localToGlobal(Offset.zero).dy,
        () =>
            mounted &&
            c.sessionId == session &&
            gesture == _gestureRevision &&
            !_userScrolling,
      );
    }
    if (c.timeline.liveRevision != _liveRevision) {
      if (_scroll.hasClients && _scroll.offset > 120) _hasNewContent = true;
      _liveRevision = c.timeline.liveRevision;
    }
    if (_lastSession != c.sessionId || !identical(_lastDraft, c.draft)) {
      if (_scroll.hasClients && !_restoringView) {
        _lastDraft?.scrollOffset = _scroll.offset;
      }
      _lastSession = c.sessionId;
      _lastDraft = c.draft;
      _restoringView = true;
      _liveRevision = c.timeline.liveRevision;
      _anchors.clear();
      _hasNewContent = false;
      _showReadingHint = false;
      _hintSerial++;
      _readingProgress.value = 0;
      _composerCollapsed = false;
      _userScrolling = false;
      _lastLength = c.timeline.messages.length;
      final restoredDraft = c.draft;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(c.draft, restoredDraft)) return;
        if (_scroll.hasClients) {
          _scroll.jumpTo(
            restoredDraft.scrollOffset.clamp(
              0,
              _scroll.position.maxScrollExtent,
            ),
          );
        }
        _restoringView = false;
        _scheduleEarlierHistory();
      });
      return;
    }
    if (c.timeline.messages.length != _lastLength) {
      _lastLength = c.timeline.messages.length;
      // A reversed list stays anchored while streaming; never force-scroll a reader.
      if (_scroll.hasClients && _scroll.position.pixels < 120) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _input.dispose();
    _search.dispose();
    _scroll.dispose();
    _readingProgress.dispose();
    _hintTimer?.cancel();
    _hintSerial++;
    _searchTimer?.cancel();
    super.dispose();
  }

  Future<void> _manage(Conversation conversation) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                conversation.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('删除对话'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final field = TextEditingController(text: conversation.title);
      final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重命名对话'),
          content: TextField(
            controller: field,
            autofocus: true,
            maxLength: 100,
            decoration: const InputDecoration(labelText: '对话名称'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, field.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (title != null) await c.renameConversation(conversation, title);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      field.dispose();
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除这段对话？'),
          content: const Text('会同时删除服务端的对话记录，无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (ok == true) await c.deleteConversation(conversation);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: _scaffold,
      drawer: _drawer(context),
      appBar: AppBar(
        leading: IconButton(
          tooltip: '对话记录',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffold.currentState!.openDrawer(),
        ),
        title: Text(
          c.title,
          key: const Key('chat-title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: '新建对话',
            onPressed: c.busy ? null : c.newChat,
            icon: const Icon(Icons.edit_square, size: 22),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              children: [
                if (!c.connected || c.syncing)
                  Material(
                    color: colors.surfaceContainer,
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        c.connected
                            ? Icons.sync_rounded
                            : Icons.wifi_off_rounded,
                        size: 18,
                      ),
                      title: Text(
                        c.syncing && c.connected
                            ? '正在同步对话状态…'
                            : '聊天未连接 · 不会自动重发消息',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: TextButton(
                        onPressed: c.reconnect,
                        child: const Text('重连'),
                      ),
                    ),
                  ),
                if (c.workspaceNotice != null)
                  ErrorNotice(
                    message: c.workspaceNotice!,
                    onDismiss: () {
                      c.workspaceNotice = null;
                      c.dismissError();
                    },
                  ),
                if (c.error != null)
                  ErrorNotice(message: c.error!, onDismiss: c.dismissError),
                if (c.current?.canContinue == false)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      '此会话由工作流、群聊或其他 Agent 管理。移动端仅供查看，请新建普通对话。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                Expanded(
                  child: NotificationListener<ScrollMetricsNotification>(
                    onNotification: (_) {
                      _scrollChanged();
                      return false;
                    },
                    child: _composer(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _readingLayout(Widget editor, Widget? handle, Widget? stop) {
    final colors = Theme.of(context).colorScheme;
    final rows = c.timeline.displayMessages;
    final indices = <Key, int>{
      for (var i = 0; i < rows.length; i++)
        ValueKey(rows[i].renderKey): rows.length - i - 1,
    };
    _anchors.prune(rows.map((m) => m.renderKey).toSet());
    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _chatScrolled,
            child: SizedBox.expand(
              key: const Key('reading-stage'),
              child: Stack(
                key: _stage,
                children: [
                  if (c.timeline.messages.isEmpty &&
                      !c.loadingMessages &&
                      !c.hasMoreMessages)
                    _welcome(context)
                  else if (c.loadingMessages &&
                      c.timeline.messages.isEmpty &&
                      !c.hasMoreMessages)
                    const Center(child: CircularProgressIndicator.adaptive())
                  else
                    SelectionArea(
                      child: ListView.builder(
                        key: const Key('message-list'),
                        controller: _scroll,
                        reverse: true,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.only(bottom: 8, top: 8),
                        itemCount: rows.length + (c.hasMoreMessages ? 1 : 0),
                        findChildIndexCallback: (key) => indices[key],
                        itemBuilder: (context, index) {
                          if (index == rows.length) {
                            return SizedBox(
                              key: const Key('history-loading-edge'),
                              height: 48,
                              child: Center(
                                child: c.historyPageError != null
                                    ? TextButton.icon(
                                        key: const Key('retry-earlier-history'),
                                        onPressed:
                                            c.connected &&
                                                !c.syncing &&
                                                !c.loadingMessages
                                            ? c.retryEarlierHistory
                                            : null,
                                        icon: const Icon(
                                          Icons.refresh_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          c.historyPageError!,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      )
                                    : c.loadingMessages
                                    ? const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '正在加载更早的消息…',
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        c.connected
                                            ? '继续上滑查看更早消息'
                                            : '连接恢复后加载历史',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                              ),
                            );
                          }
                          final message = rows[rows.length - index - 1];
                          return Container(
                            key: ValueKey(message.renderKey),
                            child: MessageBubble(
                              key: _anchors.keyFor(message.renderKey),
                              message: message,
                              controller: c,
                              anchorKey: (block) => _anchors.keyFor(
                                '${message.renderKey}:$block',
                              ),
                              onRetry: c.canRetryMessage(message)
                                  ? c.prepareRetry
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  if (_showReadingHint && handle != null)
                    Positioned(
                      left: 45,
                      right: 45,
                      bottom: 72,
                      child: IgnorePointer(
                        child: Center(
                          child: Material(
                            color: colors.surfaceContainerHighest.withValues(
                              alpha: .94,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Text(
                                '轻点底部线条，继续输入',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (handle != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 10,
                      child: Center(child: RepaintBoundary(child: handle)),
                    ),
                  if (stop != null)
                    Positioned(
                      right: 20,
                      bottom: _showJump ? 70 : 12,
                      child: stop,
                    ),
                  if (_showJump)
                    Positioned(
                      bottom: 12,
                      right: 20,
                      child: FloatingActionButton.small(
                        heroTag: 'jump',
                        tooltip: '回到最新消息',
                        onPressed: () => _scroll.animateTo(
                          0,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                        child: Badge(
                          isLabelVisible: _hasNewContent,
                          label: const Text('新'),
                          child: const Icon(Icons.arrow_downward_rounded),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: c.speech,
          builder: (context, _) => c.speech.activeId != null
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.audiotrack_rounded, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(c.speech.loading ? '正在加载语音…' : '正在播放语音'),
                      ),
                      TextButton(
                        onPressed: () => c.speech.stop(),
                        child: Text(c.speech.loading ? '取消' : '停止播放'),
                      ),
                    ],
                  ),
                )
              : c.speech.error == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    c.speech.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
        ),
        if (c.timeline.queue.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 130),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final q in c.timeline.queue)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.playlist_play),
                    title: Text(
                      q.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(switch (q.status) {
                      'sending' => '正在加入队列',
                      'canceling' => '正在取消排队',
                      'uncertain' => '状态待同步',
                      'failed' => '排队失败，消息已保留',
                      _ => '排队中',
                    }),
                    trailing: IconButton(
                      tooltip: '取消排队',
                      icon: const Icon(Icons.close),
                      onPressed:
                          !c.connected || c.syncing || q.status != 'queued'
                          ? null
                          : () => c.cancelQueued(
                              q.id,
                              expectedSession: c.sessionId!,
                            ),
                    ),
                  ),
              ],
            ),
          ),
        if (c.timeline.interaction != null)
          _InteractionCard(
            key: ValueKey(
              '${c.profile}:${c.sessionId}:${c.timeline.interaction?["approval_id"] ?? c.timeline.interaction?["clarify_id"]}',
            ),
            controller: c,
          ),
        if (c.working && c.timeline.activity.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.timeline.activity,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        editor,
      ],
    );
  }

  Widget _welcome(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EkkoMark(size: 68),
            const SizedBox(height: 24),
            const Text(
              '今天，想聊些什么？',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w600,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '一个问题，一个念头，或者一个新的开始。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 30),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _prompt(
                  Icons.lightbulb_outline_rounded,
                  '激发灵感',
                  '帮我为一个新项目进行头脑风暴，先问我几个问题。',
                ),
                _prompt(
                  Icons.auto_stories_outlined,
                  '学习新知',
                  '用简单的语言解释一个有趣的科学概念。',
                ),
                _prompt(Icons.edit_note_rounded, '帮我写作', '我想写一篇文章，请先帮我梳理写作思路。'),
                _prompt(Icons.code_rounded, '一起编程', '帮我分析一个编程问题，我会提供背景和代码。'),
              ],
            ),
            const SizedBox(height: 26),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '引擎',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: c.engine,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  isDense: true,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    color: colors.onSurface,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'ekko-agent',
                      child: Text(
                        'Ekko Agent',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const DropdownMenuItem(
                      value: 'hermes',
                      child: Text(
                        'Hermes Agent',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'codex',
                      child: Text(
                        c.codexInstalled == false
                            ? 'Codex · 服务端未安装'
                            : 'Codex Agent',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: c.working
                      ? null
                      : (v) {
                          if (v != null) c.chooseEngine(v);
                        },
                ),
              ],
            ),
            if (c.models.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  '未发现可选模型，将使用服务端默认配置。\n请先在 Studio 配置模型提供商与 Agent 运行环境。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _prompt(IconData icon, String label, String prompt) => ActionChip(
    avatar: Icon(icon, size: 18),
    label: Text(label),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    onPressed: () {
      _input.text = prompt;
      _input.selection = TextSelection.collapsed(offset: prompt.length);
    },
  );
  Widget _composer(BuildContext context) => ChatComposer(
    controller: c,
    input: _input,
    collapsed: _composerCollapsed,
    onExpand: _expandComposer,
    readingProgress: _readingProgress,
    layoutBuilder: _readingLayout,
  );

  Widget _drawer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Drawer(
      width: 330,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Row(
                children: [
                  EkkoMark(size: 34),
                  SizedBox(width: 12),
                  Text(
                    'ekko',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.8,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: c.busy
                      ? null
                      : () {
                          c.newChat();
                          Navigator.pop(context);
                        },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('新建对话'),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  hintText: '搜索全部对话',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (value) {
                  _searchTimer?.cancel();
                  _searchTimer = Timer(
                    const Duration(milliseconds: 350),
                    () => c.refreshSessions(query: value),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '对话记录',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新记录',
                    onPressed: c.loadingSessions
                        ? null
                        : () => c.refreshSessions(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                  ),
                ],
              ),
            ),
            if (c.loadingSessions) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: c.conversations.isEmpty
                  ? Center(
                      child: Text(
                        c.search.isEmpty ? '还没有对话\n从一个问题开始吧' : '没有找到相关对话',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          height: 1.8,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: c.refreshSessions,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount:
                            c.conversations.length +
                            (c.hasMoreSessions ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == c.conversations.length) {
                            return TextButton(
                              onPressed: c.loadingSessions
                                  ? null
                                  : () => c.refreshSessions(more: true),
                              child: const Text('加载更多'),
                            );
                          }
                          final conversation = c.conversations[index];
                          final task = c.taskStatus(conversation);
                          return ListTile(
                            key: ValueKey('history:${conversation.id}'),
                            dense: true,
                            minTileHeight: 54,
                            visualDensity: const VisualDensity(
                              horizontal: -2,
                              vertical: -2,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            horizontalTitleGap: 8,
                            selected: conversation.id == c.sessionId,
                            selectedTileColor: colors.primaryContainer
                                .withValues(alpha: .4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            title: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, height: 1.2),
                            ),
                            subtitle: Text(
                              conversation.preview.isNotEmpty
                                  ? conversation.preview
                                  : conversation.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                height: 1.15,
                              ),
                            ),
                            onTap: c.busy
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    c.openConversation(conversation);
                                  },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (task != ConversationTaskStatus.idle) ...[
                                  ConversationActivityMark(status: task),
                                  const SizedBox(width: 6),
                                ],
                                IconButton(
                                  tooltip: '管理对话',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 48,
                                    minHeight: 48,
                                  ),
                                  icon: const Icon(
                                    Icons.more_horiz_rounded,
                                    size: 17,
                                  ),
                                  onPressed: task.active
                                      ? null
                                      : () => _manage(conversation),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.layers_outlined, size: 19),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      value: c.profiles.contains(c.profile) ? c.profile : null,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      hint: const Text('无可用 Profile'),
                      items: c.profiles
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(p, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: c.busy
                          ? null
                          : (v) {
                              if (v != null) {
                                _search.clear();
                                c.search = '';
                                c.switchProfile(v);
                              }
                            },
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: colors.primaryContainer,
                child: Text(
                  c.account?.username.characters.firstOrNull?.toUpperCase() ??
                      'E',
                ),
              ),
              title: Text(
                c.account?.username ?? '',
                style: const TextStyle(fontSize: 14),
              ),
              subtitle: const Text('个人信息与设置', style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.settings_outlined, size: 20),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => ProfileScreen(controller: c),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractionCard extends StatefulWidget {
  const _InteractionCard({super.key, required this.controller});
  final AppController controller;
  @override
  State<_InteractionCard> createState() => _InteractionCardState();
}

class _InteractionCardState extends State<_InteractionCard> {
  final field = TextEditingController();
  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.controller.timeline.interaction!,
        approval = data['kind'] == 'approval.requested';
    final owner = widget.controller.sessionId;
    final interactionId = text(data[approval ? 'approval_id' : 'clarify_id']);
    final canRespond =
        widget.controller.connected &&
        !widget.controller.syncing &&
        !widget.controller.timeline.interactionSubmitting &&
        !widget.controller.timeline.interactionExpired &&
        widget.controller.current?.canContinue != false;
    void respond(String value) => widget.controller.respondToInteraction(
      value,
      expectedSession: owner,
      expectedInteraction: interactionId,
    );
    final choices = asList(data['choices']).whereType<String>().toList();
    final colors = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 270),
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                approval ? '需要你的授权' : '需要你补充信息',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SelectableText(
                approval ? text(data['description']) : text(data['question']),
              ),
              if (approval && text(data['command']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SelectableText(
                    text(data['command']),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              if (widget.controller.timeline.interactionError != null)
                Text(
                  widget.controller.timeline.interactionError!,
                  style: TextStyle(color: colors.error),
                ),
              if (widget.controller.timeline.interactionError != null)
                TextButton(
                  onPressed:
                      !widget.controller.connected || widget.controller.syncing
                      ? null
                      : widget.controller.syncCurrentConversation,
                  child: const Text('同步审批状态'),
                ),
              if (widget.controller.timeline.interactionSubmitting)
                const Text('等待服务器确认…'),
              if (approval)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: canRespond ? () => respond('deny') : null,
                      child: const Text('拒绝'),
                    ),
                    if (choices.contains('once'))
                      FilledButton(
                        onPressed: canRespond ? () => respond('once') : null,
                        child: const Text('仅允许本次'),
                      ),
                    if (choices.contains('always') &&
                        data['allow_permanent'] == true)
                      OutlinedButton(
                        onPressed: !canRespond
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('确认永久授权？'),
                                    content: Text(
                                      '同类操作后续可能不再询问。授权范围与撤销方式由服务端控制。\n${text(data['permission_key'] ?? data['description'])}',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('取消'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('永久允许'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && mounted) {
                                  respond('always');
                                }
                              },
                        child: const Text('永久允许'),
                      ),
                  ],
                )
              else ...[
                if (choices.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: choices
                        .map(
                          (v) => ActionChip(
                            label: Text(v),
                            onPressed: canRespond ? () => respond(v) : null,
                          ),
                        )
                        .toList(),
                  ),
                TextField(
                  controller: field,
                  decoration: InputDecoration(
                    hintText: '补充说明',
                    suffixIcon: IconButton(
                      tooltip: '提交说明',
                      icon: const Icon(Icons.send_rounded),
                      onPressed: !canRespond
                          ? null
                          : () {
                              if (field.text.trim().isNotEmpty) {
                                respond(field.text.trim());
                                field.clear();
                              }
                            },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
