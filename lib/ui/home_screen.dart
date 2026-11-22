import '../l10n.dart';
import 'session_tasks_screen.dart';
import 'person_screens.dart';
import '../data/mobile_features.dart';
import '../data/message_selection.dart';
import '../state/message_selection_controller.dart';
import 'message_selection_screen.dart';
import 'widgets/chat_swipe_region.dart';
import 'widgets/workspace_drawer.dart';
import 'widgets/agent_picker.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/message_bubble.dart';
import 'widgets/chat_history_list.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_reading_view.dart';
import 'widgets/conversation_drawer.dart';
import 'widgets/chat_title.dart';
import 'widgets/chat_interaction_card.dart';
import 'group_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with ChatReadingState<HomeScreen> {
  Conversation? get _selectionConversation =>
      c.conversations
          .where((row) => row.id == c.sessionId && row.profile == c.profile)
          .firstOrNull ??
      c.current;
  Future<void> _selectMessages([String? initial]) async {
    final api = c.api, session = _selectionConversation;
    if (api == null ||
        !MobileFeatures.messageSelection ||
        !supportsSessionSelection(session)) {
      return;
    }
    final id = session!.id, profile = c.profile, token = api.token;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MessageSelectionScreen<int, int>(
          title: session.title,
          scopeChanges: c,
          messages: List.of(c.displayMessages),
          initialMessageId: initial,
          controller: MessageSelectionController<int, int>(
            read: () => api.sessionMessageSelection(id),
            remove: (ids, revision) =>
                api.deleteSessionMessages(id, ids, revision),
            reconcile: () => c.reconcileMessageDeletion(id),
            valid: () =>
                c.api == api &&
                api.token == token &&
                c.profile == profile &&
                c.sessionId == id,
          ),
        ),
      ),
    );
  }

  final _scaffold = GlobalKey<ScaffoldState>();
  final _input = TextEditingController();
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    initReading();
  }

  @override
  ChatReadingSnapshot get readingSnapshot => ChatReadingSnapshot(
    id: c.sessionId,
    draft: c.draft,
    messageCount: c.timeline.messages.length,
    liveRevision: c.timeline.liveRevision,
    hasNewer: c.hasNewerMessages,
    readingOlder: c.readingOlderWindow,
    canLoadEarlier: c.canLoadEarlier,
  );
  @override
  bool get readingRouteVisible =>
      ModalRoute.of(context)?.isCurrent == true &&
      _scaffold.currentState?.isDrawerOpen != true &&
      _scaffold.currentState?.isEndDrawerOpen != true;
  @override
  bool get readingHintSeen => c.readingHintSeen;
  @override
  Future<void> markReadingHintSeen() => c.markReadingHintSeen();
  @override
  void beginHistoryReading() => c.beginReadingWindow();
  @override
  Future<void> showLatestHistory() => c.showLatestHistory();
  @override
  Future<void> loadEarlierHistory() => c.loadHistory(more: true);
  @override
  Future<void> confirmLatestVisible() => c.confirmVisibleRead(atLatest: true);

  void _changed() {
    final person = c.personToOpen;
    if (person != null) {
      c.personToOpen = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => PersonScreen(app: c, sessionId: person),
            ),
          );
        }
      });
    }
    if (!mounted) return;
    setState(() {});
    readingChanged();
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _input.dispose();
    disposeReading();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffold,
      drawer: ConversationDrawer(
        controller: c,
        onNewChat: c.newChat,
        onOpenConversation: c.openConversation,
        onOpenGroup: (room) => Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                GroupChatScreen(api: c.api!, room: room, appController: c),
          ),
        ),
      ),
      // The reading-region recognizer handles edge and center touches once.
      drawerEnableOpenDragGesture: false,
      onDrawerChanged: (open) {
        if (!open) scheduleReadReceipt();
      },
      endDrawer: WorkspaceDrawer(controller: c),
      endDrawerEnableOpenDragGesture: false,
      onEndDrawerChanged: (open) {
        if (open && c.sessionId != null) c.refreshWorkspaceFiles();
        if (!open) scheduleReadReceipt();
      },
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr("对话记录"),
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffold.currentState!.openDrawer(),
        ),
        titleSpacing: 0,
        title: ChatTitle(controller: c, title: c.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: ChatConnectionLine(
            connected: c.connected,
            syncing: c.syncing,
            onReconnect: c.reconnect,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: context.tr('更多操作'),
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'select') {
                _selectMessages();
                return;
              }
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => SessionTasksScreen(
                    app: c,
                    sessionId: value == 'current' ? c.sessionId : null,
                  ),
                ),
              );
            },
            itemBuilder: (_) => [
              if (MobileFeatures.messageSelection &&
                  supportsSessionSelection(_selectionConversation))
                PopupMenuItem(value: 'select', child: Text(context.tr('选择消息'))),
              if (MobileFeatures.sessionTasks)
                PopupMenuItem(value: 'all', child: Text(context.tr('任务中心'))),
              if (MobileFeatures.sessionTasks && c.sessionId != null)
                PopupMenuItem(
                  value: 'current',
                  child: Text(context.tr('当前会话目标')),
                ),
            ],
          ),
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
      body: ChatBody(
        notices: [
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
          if (c.recoverableDrafts.isNotEmpty)
            for (final recovered in c.recoverableDrafts)
              ListTile(
                dense: true,
                title: Text(context.tr('有可恢复的草稿')),
                subtitle: Text(
                  recovered.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: TextButton(
                  key: ValueKey('recover-draft:${recovered.sessionId}'),
                  onPressed: () =>
                      c.recoverConversationDraft(recovered.sessionId),
                  child: Text(context.tr('恢复到新对话')),
                ),
              ),
          if (c.current?.canContinue == false)
            Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                context.tr("此会话由工作流、群聊或其他 Agent 管理。移动端仅供查看，请新建普通对话。"),
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
        child: _composer(context),
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
    final rows = c.displayMessages;
    final indices = <Key, int>{
      for (var i = 0; i < rows.length; i++)
        ValueKey(rows[i].renderKey): rows.length - i - 1,
    };
    readingAnchors.prune(rows.map((m) => m.renderKey).toSet());
    return readingLayout(
      history: Stack(
        children: [
          if (rows.isEmpty && !c.loadingMessages && !c.hasMoreMessages)
            _welcome(context)
          else if (c.loadingMessages && rows.isEmpty && !c.hasMoreMessages)
            const Center(child: CircularProgressIndicator.adaptive())
          else
            ChatHistoryList(
              listKey: const Key('message-list'),
              controller: readingScroll,
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
                              icon: const Icon(Icons.refresh_rounded, size: 16),
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
                  child: GestureDetector(
                    onLongPress:
                        MobileFeatures.messageSelection &&
                            supportsSessionSelection(_selectionConversation)
                        ? () => _selectMessages(message.id)
                        : null,
                    child: MessageBubble(
                      onSelectMessage:
                          MobileFeatures.messageSelection &&
                              supportsSessionSelection(_selectionConversation)
                          ? () => _selectMessages(message.id)
                          : null,
                      key: readingAnchors.keyFor(message.renderKey),
                      message: message,
                      controller: c,
                      anchorKey: (block) =>
                          readingAnchors.keyFor('${message.renderKey}:$block'),
                      onRetry: c.canRetryMessage(message)
                          ? c.prepareRetry
                          : null,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      editor: editor,
      handle: handle,
      stop: stop,
      wrapReading: _swipeRegion,
      footer: [
        ChatSpeechStatus(speech: c.speech),
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
          Builder(
            builder: (_) {
              final data = c.timeline.interaction!;
              final approval = data['kind'] == 'approval.requested';
              final owner = c.sessionId;
              final interactionId = text(
                data[approval ? 'approval_id' : 'clarify_id'],
              );
              return ChatInteractionCard(
                key: ValueKey('${c.profile}:$owner:$interactionId'),
                data: data,
                enabled:
                    c.connected &&
                    !c.syncing &&
                    !c.timeline.interactionExpired &&
                    c.current?.canContinue != false,
                submitting: c.timeline.interactionSubmitting,
                error: c.timeline.interactionError,
                onSync: c.syncCurrentConversation,
                canSync: c.connected && !c.syncing,
                onRespond: (value) => c.respondToInteraction(
                  value,
                  expectedSession: owner,
                  expectedInteraction: interactionId,
                ),
              );
            },
          ),
        ChatActivityStatus(working: c.working, activity: c.timeline.activity),
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
    collapsed: composerCollapsed,
    onExpand: expandReadingComposer,
    readingProgress: readingProgress,
    layoutBuilder: _readingLayout,
  );
}
