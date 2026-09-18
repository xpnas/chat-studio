import '../l10n.dart';
import 'widgets/chat_swipe_region.dart';
import 'widgets/workspace_drawer.dart';
import 'widgets/agent_picker.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../state/app_controller.dart';
import '../state/conversation_state.dart';
import 'profile_screen.dart';
import 'theme.dart';
import 'widgets/agent_avatar.dart';
import 'widgets/message_bubble.dart';
import 'widgets/chat_composer.dart';
import 'widgets/reading_handle.dart';
import 'widgets/reading_anchor.dart';
import 'widgets/conversation_activity_mark.dart';

class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final active = !controller.connected || controller.syncing;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: controller.syncing
          ? context.tr('正在同步对话状态…')
          : controller.connected
          ? context.tr('聊天已连接')
          : context.tr('正在连接聊天服务…'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: controller.connected ? null : controller.reconnect,
        child: LinearProgressIndicator(
          // Keep the indicator finite so opening/resuming the app never
          // leaves widget tests (or reduced-motion users) with a perpetual
          // animation. The color and fill communicate the connection state.
          value: active ? (controller.syncing ? .62 : .22) : 0,
          minHeight: 2,
          color: active
              ? controller.syncing
                    ? colors.primary
                    : colors.tertiary
              : colors.primary.withValues(alpha: .18),
          backgroundColor: colors.surfaceContainerHighest.withValues(
            alpha: .32,
          ),
        ),
      ),
    );
  }
}

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
  String _historyFilter = 'all';
  String _historyCategory = '';
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
    final liveChanged = c.timeline.liveRevision != _liveRevision;
    if (session == _lastSession &&
        !liveChanged &&
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
    if (liveChanged) {
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
    final pinned = c.isConversationPinned(conversation);
    final archived = c.isConversationArchived(conversation);
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
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: Text(
                conversation.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                c.conversationCategory(conversation).isEmpty
                    ? context.tr('未分类')
                    : c.conversationCategory(conversation),
              ),
            ),
            ListTile(
              leading: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(pinned ? context.tr('取消置顶') : context.tr('置顶对话')),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: Icon(
                archived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              title: Text(archived ? context.tr('移出归档') : context.tr('归档对话')),
              onTap: () => Navigator.pop(context, 'archive'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text(context.tr('移动到分类')),
              onTap: () => Navigator.pop(context, 'category'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(context.tr('重命名')),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(context.tr('删除对话')),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'pin') {
      await c.setConversationPinned(conversation, !pinned);
      return;
    }
    if (action == 'archive') {
      await c.setConversationArchived(conversation, !archived);
      return;
    }
    if (action == 'category') {
      await _chooseConversationCategory(conversation);
      return;
    }
    if (action == 'rename') {
      final field = TextEditingController(text: conversation.title);
      final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('重命名对话')),
          content: TextField(
            controller: field,
            autofocus: true,
            maxLength: 100,
            decoration: InputDecoration(labelText: context.tr('对话名称')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, field.text),
              child: Text(context.tr('保存')),
            ),
          ],
        ),
      );
      if (title != null) await c.renameConversation(conversation, title);
      field.dispose();
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('删除这段对话？')),
          content: Text(context.tr('会同时删除服务端的对话记录，无法撤销。')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('删除')),
            ),
          ],
        ),
      );
      if (ok == true) await c.deleteConversation(conversation);
    }
  }

  Future<void> _chooseConversationCategory(Conversation conversation) async {
    final categories = c.conversationCategoryNames.toList()..sort();
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(context.tr('移动到分类')),
              subtitle: Text(context.tr('分类会同步到服务器，网页端也会立即显示')),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(context.tr('创建新分类')),
              onTap: () => Navigator.pop(context, '__create__'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_off_outlined),
              title: Text(context.tr('取消分类')),
              onTap: () => Navigator.pop(context, ''),
            ),
            for (final category in categories)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(category),
                trailing: c.conversationCategory(conversation) == category
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, category),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    var selected = choice;
    if (choice == '__create__') {
      final field = TextEditingController();
      selected =
          await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(context.tr('创建新分类')),
              content: TextField(
                controller: field,
                autofocus: true,
                maxLength: 30,
                decoration: InputDecoration(labelText: context.tr('分类名称')),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('取消')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, field.text),
                  child: Text(context.tr('创建并移动')),
                ),
              ],
            ),
          ) ??
          '';
      field.dispose();
      final created = await c.createConversationCategory(selected);
      if (!created) return;
    }
    if (selected.isNotEmpty || choice == '') {
      await c.moveConversationToCategory(conversation, selected);
    }
  }

  Future<void> _pickProfile() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  context.tr('切换 Profile'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final profile in c.profiles)
                      ListTile(
                        leading: const Icon(Icons.layers_outlined),
                        title: Text(profile),
                        subtitle: profile == c.profile
                            ? Text(context.tr('当前 Profile'))
                            : null,
                        selected: profile == c.profile,
                        trailing: profile == c.profile
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(context, profile),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || chosen == null || chosen == c.profile || c.busy) return;
    _search.clear();
    c.search = '';
    await c.switchProfile(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffold,
      drawer: _drawer(context),
      // The reading-region recognizer handles edge and center touches once.
      drawerEnableOpenDragGesture: false,
      endDrawer: WorkspaceDrawer(controller: c),
      endDrawerEnableOpenDragGesture: false,
      onEndDrawerChanged: (open) {
        if (open && c.sessionId != null) c.refreshWorkspaceFiles();
      },
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr("对话记录"),
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffold.currentState!.openDrawer(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            AgentAvatar(controller: c, size: 25),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.title,
                key: const Key('chat-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _ConnectionLine(controller: c),
        ),
        actions: [
          IconButton(
            tooltip: context.tr("工作区"),
            onPressed: () => _scaffold.currentState!.openEndDrawer(),
            icon: const Icon(Icons.folder_copy_outlined, size: 21),
          ),
          IconButton(
            tooltip: context.tr("新建对话"),
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
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      context.tr("此会话由工作流、群聊或其他 Agent 管理。移动端仅供查看，请新建普通对话。"),
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

  Widget _swipeRegion(Widget child) => ChatSwipeRegion(
    onSwipe: (right) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (right) {
        _scaffold.currentState?.openDrawer();
      } else {
        _scaffold.currentState?.openEndDrawer();
      }
    },
    child: child,
  );

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
            child: _swipeRegion(
              SizedBox.expand(
                key: const Key('reading-stage'),
                child: Stack(
                  key: _stage,
                  children: [
                    if (rows.isEmpty &&
                        !c.loadingMessages &&
                        !c.hasMoreMessages)
                      _welcome(context)
                    else if (c.loadingMessages &&
                        rows.isEmpty &&
                        !c.hasMoreMessages)
                      const Center(child: CircularProgressIndicator.adaptive())
                    else
                      ListView.builder(
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
                                    ? Row(
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
                                            context.tr("正在加载更早的消息…"),
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        c.connected
                                            ? context.tr("继续上滑查看更早消息")
                                            : context.tr("连接恢复后加载历史"),
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
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Text(
                                  context.tr("轻点底部线条，继续输入"),
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
                          tooltip: context.tr("回到最新消息"),
                          onPressed: () => _scroll.animateTo(
                            0,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          ),
                          child: Badge(
                            isLabelVisible: _hasNewContent,
                            label: Text(context.tr("新")),
                            child: const Icon(Icons.arrow_downward_rounded),
                          ),
                        ),
                      ),
                  ],
                ),
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
                        child: Text(
                          c.speech.loading
                              ? context.tr("正在加载语音…")
                              : context.tr("正在播放语音"),
                        ),
                      ),
                      TextButton(
                        onPressed: () => c.speech.stop(),
                        child: Text(
                          c.speech.loading
                              ? context.tr("取消")
                              : context.tr("停止播放"),
                        ),
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
                      'sending' => context.tr("正在加入队列"),
                      'canceling' => context.tr("正在取消排队"),
                      'uncertain' => context.tr("状态待同步"),
                      'failed' => context.tr("排队失败，消息已保留"),
                      _ => context.tr("排队中"),
                    }),
                    trailing: IconButton(
                      tooltip: context.tr("取消排队"),
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
            const ChatStudioMark(size: 68),
            const SizedBox(height: 24),
            Text(
              context.tr("今天，想聊些什么？"),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w600,
                letterSpacing: -.6,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr("一个问题，一个念头，或者一个新的开始。"),
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
                  context.tr("激发灵感"),
                  context.tr("帮我为一个新项目进行头脑风暴，先问我几个问题。"),
                ),
                _prompt(
                  Icons.auto_stories_outlined,
                  context.tr("学习新知"),
                  context.tr("用简单的语言解释一个有趣的科学概念。"),
                ),
                _prompt(
                  Icons.edit_note_rounded,
                  context.tr("帮我写作"),
                  context.tr("我想写一篇文章，请先帮我梳理写作思路。"),
                ),
                _prompt(
                  Icons.code_rounded,
                  context.tr("一起编程"),
                  context.tr("帮我分析一个编程问题，我会提供背景和代码。"),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Center(child: AgentPickerButton(controller: c)),
            if (c.models.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  context.tr(
                    "未发现可选模型，将使用服务端默认配置。\n请先在 Studio 配置模型提供商与 Agent 运行环境。",
                  ),
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
    final visible = c.conversations.where((conversation) {
      final archived = c.isConversationArchived(conversation);
      final category = c.conversationCategory(conversation);
      return switch (_historyFilter) {
        'pinned' => c.isConversationPinned(conversation) && !archived,
        'archived' => archived,
        'category' => category == _historyCategory && !archived,
        _ => !archived,
      };
    }).toList();
    final categories = c.conversationCategoryNames.toList()..sort();
    return Drawer(
      key: const Key('conversation-history-drawer'),
      width: MediaQuery.sizeOf(context).width,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 18, 18),
              child: Row(
                children: [
                  const ChatStudioMark(size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('Chat Studio'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('关闭'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
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
                  label: Text(context.tr('新建对话')),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: context.tr('搜索全部对话'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                ),
                onChanged: (value) {
                  _searchTimer?.cancel();
                  _searchTimer = Timer(
                    const Duration(milliseconds: 350),
                    () => c.refreshSessions(
                      query: value,
                      includeArchived: _historyFilter == 'archived',
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('对话记录'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: context.tr('筛选历史'),
                    onSelected: (value) async {
                      if (value == 'new-category') {
                        final field = TextEditingController();
                        final name = await showDialog<String>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(context.tr('创建新分类')),
                            content: TextField(
                              controller: field,
                              autofocus: true,
                              maxLength: 30,
                              decoration: InputDecoration(
                                labelText: context.tr('分类名称'),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(context.tr('取消')),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(context, field.text),
                                child: Text(context.tr('创建')),
                              ),
                            ],
                          ),
                        );
                        field.dispose();
                        if (name != null) {
                          await c.createConversationCategory(name);
                        }
                        return;
                      }
                      if (value.startsWith('category:')) {
                        setState(() {
                          _historyFilter = 'category';
                          _historyCategory = value.substring(
                            'category:'.length,
                          );
                        });
                      } else {
                        setState(() {
                          _historyFilter = value;
                          _historyCategory = '';
                        });
                      }
                      unawaited(
                        c.refreshSessions(
                          includeArchived: _historyFilter == 'archived',
                        ),
                      );
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'all',
                        child: Text(context.tr('全部历史')),
                      ),
                      PopupMenuItem(
                        value: 'pinned',
                        child: Text(context.tr('置顶对话')),
                      ),
                      PopupMenuItem(
                        value: 'archived',
                        child: Text(context.tr('归档对话')),
                      ),
                      if (categories.isNotEmpty) const PopupMenuDivider(),
                      for (final category in categories)
                        PopupMenuItem(
                          value: 'category:$category',
                          child: Text(category),
                        ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'new-category',
                        child: Text(context.tr('创建新分类')),
                      ),
                    ],
                    icon: const Icon(Icons.filter_list_rounded, size: 20),
                  ),
                  IconButton(
                    tooltip: context.tr('刷新记录'),
                    onPressed: c.loadingSessions
                        ? null
                        : () => c.refreshSessions(
                            includeArchived: _historyFilter == 'archived',
                          ),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
            ),
            if (_historyFilter == 'category')
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _historyCategory,
                        style: TextStyle(color: colors.primary, fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final removed = await c.removeConversationCategory(
                          _historyCategory,
                        );
                        if (removed && mounted) {
                          setState(() {
                            _historyFilter = 'all';
                            _historyCategory = '';
                          });
                        }
                      },
                      child: Text(context.tr('删除分类')),
                    ),
                  ],
                ),
              ),
            if (c.loadingSessions) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        c.conversations.isEmpty
                            ? (c.search.isEmpty
                                  ? context.tr('还没有对话\n从一个问题开始吧')
                                  : context.tr('没有找到相关对话'))
                            : context.tr('此筛选下暂无对话'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          height: 1.8,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => c.refreshSessions(
                        includeArchived: _historyFilter == 'archived',
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                        itemCount: visible.length + (c.hasMoreSessions ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == visible.length) {
                            return TextButton(
                              onPressed: c.loadingSessions
                                  ? null
                                  : () => c.refreshSessions(
                                      more: true,
                                      includeArchived:
                                          _historyFilter == 'archived',
                                    ),
                              child: Text(context.tr('加载更多')),
                            );
                          }
                          final conversation = visible[index];
                          final task = c.taskStatus(conversation);
                          final pinned = c.isConversationPinned(conversation);
                          final category = c.conversationCategory(conversation);
                          return ListTile(
                            key: ValueKey('history:${conversation.id}'),
                            minTileHeight: 54,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            horizontalTitleGap: 10,
                            selected: conversation.id == c.sessionId,
                            selectedTileColor: colors.primaryContainer
                                .withValues(alpha: .4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            leading: Icon(
                              pinned
                                  ? Icons.push_pin
                                  : Icons.chat_bubble_outline_rounded,
                              size: 19,
                              color: pinned
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                            title: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    conversation.preview.isNotEmpty
                                        ? conversation.preview
                                        : conversation.model,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                if (category.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.folder_outlined,
                                    size: 13,
                                    color: colors.primary,
                                  ),
                                  const SizedBox(width: 2),
                                  Flexible(
                                    child: Text(
                                      category,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: colors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
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
                                  tooltip: context.tr('管理对话'),
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.more_horiz_rounded,
                                    size: 18,
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
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.layers_outlined),
              title: Text(
                c.profile,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(context.tr('切换当前 Profile')),
              trailing: const Icon(Icons.keyboard_arrow_up_rounded),
              enabled: !c.busy && c.profiles.isNotEmpty,
              onTap: _pickProfile,
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
              subtitle: Text(
                context.tr('个人信息与设置'),
                style: TextStyle(fontSize: 11),
              ),
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
                approval ? context.tr("需要你的授权") : context.tr("需要你补充信息"),
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
                  child: Text(context.tr("同步审批状态")),
                ),
              if (widget.controller.timeline.interactionSubmitting)
                Text(context.tr("等待服务器确认…")),
              if (approval)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: canRespond ? () => respond('deny') : null,
                      child: Text(context.tr("拒绝")),
                    ),
                    if (choices.contains('once'))
                      FilledButton(
                        onPressed: canRespond ? () => respond('once') : null,
                        child: Text(context.tr("仅允许本次")),
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
                                    title: Text(context.tr("确认永久授权？")),
                                    content: Text(
                                      context.l10n.format(
                                        "同类操作后续可能不再询问。授权范围与撤销方式由服务端控制。\n{0}",
                                        {
                                          '0': text(
                                            data['permission_key'] ??
                                                data['description'],
                                          ),
                                        },
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: Text(context.tr("取消")),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: Text(context.tr("永久允许")),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && mounted) {
                                  respond('always');
                                }
                              },
                        child: Text(context.tr("永久允许")),
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
                    hintText: context.tr("补充说明"),
                    suffixIcon: IconButton(
                      tooltip: context.tr("提交说明"),
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
