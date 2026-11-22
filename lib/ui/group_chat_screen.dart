import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n.dart';
import '../data/models.dart';
import '../data/studio_api.dart';
import '../data/message_selection.dart';
import '../state/message_selection_controller.dart';
import 'message_selection_screen.dart';
import '../data/person_models.dart';
import 'person_screens.dart';
import '../data/mobile_features.dart';
import '../state/app_controller.dart';
import '../state/group_chat_controller.dart';
import 'widgets/agent_avatar.dart';
import 'widgets/chat_composer.dart';
import 'widgets/message_bubble.dart';
import 'widgets/chat_reading_view.dart';
import 'widgets/chat_history_list.dart';
import 'widgets/chat_title.dart';
import 'widgets/chat_swipe_region.dart';
import 'widgets/conversation_drawer.dart';
import 'widgets/workspace_drawer.dart';
import 'widgets/chat_interaction_card.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.api,
    required this.room,
    required this.appController,
    this.controller,
  });
  final StudioApi api;
  final GroupRoom room;
  final AppController appController;
  final GroupChatController? controller;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with WidgetsBindingObserver, ChatReadingState<GroupChatScreen> {
  Future<void> _selectMessages([String? initial]) async {
    if (!MobileFeatures.messageSelection) return;
    final api = widget.api, id = controller.room.id, token = widget.api.token;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => MessageSelectionScreen<String, String>(
          title: controller.room.name,
          scopeChanges: widget.appController,
          messages: List.of(controller.displayMessages),
          initialMessageId: initial,
          controller: MessageSelectionController<String, String>(
            read: () => api.groupMessageSelection(id),
            remove: (ids, revision) =>
                api.deleteGroupMessages(id, ids, revision),
            reconcile: controller.start,
            valid: () =>
                mounted &&
                widget.appController.api == api &&
                api.token == token &&
                widget.appController.profile == _profile &&
                controller.room.id == id,
          ),
        ),
      ),
    );
  }

  late final GroupChatController controller;
  final _scaffold = GlobalKey<ScaffoldState>();
  final _workspace = GlobalKey<GroupWorkspaceDrawerState>();
  late final String _profile;
  bool _leaving = false;
  final input = TextEditingController();
  bool loadingOlder = false;
  bool _backgrounded = false;
  int? mentionStart;
  int mentionEnd = 0;
  String mentionQuery = '';

  @override
  void initState() {
    super.initState();
    controller =
        widget.controller ??
        GroupChatController(api: widget.api, room: widget.room);
    initReading(restoreInitial: true);
    controller.addListener(_changed);
    _profile = widget.appController.profile;
    widget.appController.addListener(_appChanged);
    input.addListener(_inputChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.start());
  }

  void _appChanged() {
    if (_leaving || !mounted) return;
    if (widget.appController.api != widget.api ||
        widget.appController.profile != _profile) {
      _leaving = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final route = ModalRoute.of(context);
        if (route != null) Navigator.of(context).removeRoute(route);
      });
    } else {
      setState(() {});
    }
  }

  void _newChat() {
    widget.appController.newChat();
    Navigator.of(context).pop();
  }

  void _openConversation(Conversation conversation) {
    if (isPersonMain(conversation.id) && AppController.botsEnabled) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PersonScreen(
            app: widget.appController,
            sessionId: conversation.id,
          ),
        ),
      );
      return;
    }
    unawaited(widget.appController.openConversation(conversation));
    Navigator.of(context).pop();
  }

  void _openGroup(GroupRoom room) {
    if (room.id == controller.room.id) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GroupChatScreen(
          api: widget.api,
          room: room,
          appController: widget.appController,
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _backgrounded = true;
    if (state == AppLifecycleState.resumed && _backgrounded) {
      _backgrounded = false;
      unawaited(controller.start());
    }
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    readingChanged();
  }

  void _inputChanged() {
    final caret = input.selection.baseOffset;
    final prefix = caret >= 0 && caret <= input.text.length
        ? input.text.substring(0, caret)
        : '';
    final match = RegExp(r'(^|\s)@([^@\n]{0,48})$').firstMatch(prefix);
    setState(() {
      mentionStart = match == null
          ? null
          : match.start + match.group(1)!.length;
      mentionEnd = caret;
      mentionQuery = match?.group(2)?.toLowerCase() ?? '';
    });
  }

  void _pickMention(GroupAgentSummary? agent) {
    final start = mentionStart;
    if (start == null) return;
    final mention = '@${agent?.name ?? 'all'} ';
    input.value = TextEditingValue(
      text: input.text.replaceRange(start, mentionEnd, mention),
      selection: TextSelection.collapsed(offset: start + mention.length),
    );
    setState(() => mentionStart = null);
  }

  @override
  ChatReadingSnapshot get readingSnapshot => ChatReadingSnapshot(
    id: controller.room.id,
    draft: controller.draft,
    messageCount: controller.messages.length,
    liveRevision: controller.messages.isEmpty
        ? null
        : (
            controller.messages.last.id,
            controller.messages.last.content,
            controller.messages.last.reasoning,
            controller.messages.last.isStreaming,
          ),
    canLoadEarlier:
        !controller.loading &&
        !loadingOlder &&
        controller.hasMore &&
        controller.error == null,
  );
  @override
  bool get readingRouteVisible =>
      ModalRoute.of(context)?.isCurrent == true &&
      _scaffold.currentState?.isDrawerOpen != true &&
      _scaffold.currentState?.isEndDrawerOpen != true;
  @override
  bool get readingHintSeen => widget.appController.readingHintSeen;
  @override
  Future<void> markReadingHintSeen() =>
      widget.appController.markReadingHintSeen();
  // Group history remains live; it has no single/BOT observer read protocol.
  @override
  void beginHistoryReading() {}
  @override
  Future<void> showLatestHistory() async {}
  @override
  Future<void> confirmLatestVisible() async {}
  @override
  Future<void> loadEarlierHistory() => _older();

  Widget _swipeReading(Widget child) => ChatSwipeRegion(
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

  Future<void> _older() async {
    if (loadingOlder || controller.loading) return;
    loadingOlder = true;
    await controller.loadOlder();
    if (!mounted) return;
    loadingOlder = false;
    scheduleEarlierHistory();
  }

  Widget _interactionPanel(BuildContext context) {
    final data = controller.timeline.interaction;
    if (data == null) return const SizedBox.shrink();
    final approval = data['kind'] == 'approval.requested';
    final interactionId = text(data[approval ? 'approval_id' : 'clarify_id']);
    return ChatInteractionCard(
      key: ValueKey('group:${controller.room.id}:$interactionId'),
      data: data,
      enabled: controller.canRespondToInteraction,
      submitting: controller.timeline.interactionSubmitting,
      error: controller.timeline.interactionError,
      onRespond: controller.respondToInteraction,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.appController.removeListener(_appChanged);
    controller.removeListener(_changed);
    if (widget.controller == null) controller.dispose();
    input.removeListener(_inputChanged);
    input.dispose();
    disposeReading();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final messages = controller.displayMessages;
    final indices = <Key, int>{
      for (var i = 0; i < messages.length; i++)
        ValueKey(messages[i].renderKey): messages.length - i - 1,
    };
    readingAnchors.prune(messages.map((m) => m.renderKey).toSet());
    final mentions = controller.agents
        .where((a) => a.name.toLowerCase().contains(mentionQuery))
        .toList();
    final mentionAll =
        controller.room.canMentionAll && 'all'.startsWith(mentionQuery);
    return Scaffold(
      key: _scaffold,
      drawer: ConversationDrawer(
        controller: widget.appController,
        initialTab: 1,
        onNewChat: _newChat,
        onOpenConversation: _openConversation,
        onOpenGroup: _openGroup,
      ),
      drawerEnableOpenDragGesture: false,
      endDrawer: GroupWorkspaceDrawer(
        key: _workspace,
        api: widget.api,
        room: controller.room,
      ),
      endDrawerEnableOpenDragGesture: false,
      onEndDrawerChanged: (open) {
        if (!open) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scaffold.currentState?.isEndDrawerOpen == true) {
            _workspace.currentState?.refresh();
          }
        });
      },
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('对话记录'),
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffold.currentState?.openDrawer(),
        ),
        titleSpacing: 0,
        title: ChatTitle(
          controller: widget.appController,
          title: controller.room.name,
          agents: controller.agents,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: ChatConnectionLine(
            connected: controller.connected,
            syncing: controller.loading,
            onReconnect: controller.start,
          ),
        ),
        actions: [
          if (MobileFeatures.messageSelection)
            IconButton(
              tooltip: context.tr('选择消息'),
              onPressed: () => _selectMessages(),
              icon: const Icon(Icons.checklist),
            ),
          IconButton(
            tooltip: context.tr('工作区'),
            icon: const Icon(Icons.folder_copy_outlined, size: 21),
            onPressed: () => _scaffold.currentState?.openEndDrawer(),
          ),
          IconButton(
            tooltip: context.tr('新建对话'),
            icon: const Icon(Icons.edit_square, size: 22),
            onPressed: widget.appController.busy ? null : _newChat,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ChatBody(
        notices: [
          if (controller.error != null)
            MaterialBanner(
              content: Text(
                controller.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                TextButton(
                  onPressed: controller.loading ? null : controller.start,
                  child: Text(context.tr('重试')),
                ),
              ],
            ),
        ],
        child: ChatComposer(
          controller: widget.appController,
          input: input,
          group: controller,
          collapsed: composerCollapsed,
          readingProgress: readingProgress,
          onExpand: expandReadingComposer,
          layoutBuilder: (editor, handle, stop) => readingLayout(
            editor: editor,
            handle: handle,
            stop: stop,
            wrapReading: _swipeReading,
            history: Stack(
              children: [
                RefreshIndicator(
                  onRefresh: controller.start,
                  child: ChatHistoryList(
                    listKey: const Key('message-list'),
                    controller: readingScroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: messages.length + 1,
                    findChildIndexCallback: (key) => indices[key],
                    itemBuilder: (context, index) {
                      if (index == messages.length) {
                        return controller.hasMore
                            ? Center(
                                child: TextButton(
                                  onPressed: controller.loading ? null : _older,
                                  child: Text(context.tr('加载更早消息')),
                                ),
                              )
                            : const SizedBox.shrink();
                      }
                      final message = messages[messages.length - 1 - index];
                      return GestureDetector(
                        key: ValueKey(message.renderKey),
                        onLongPress: MobileFeatures.messageSelection
                            ? () => _selectMessages(message.id)
                            : null,
                        child: MessageBubble(
                          onSelectMessage: MobileFeatures.messageSelection
                              ? () => _selectMessages(message.id)
                              : null,
                          key: readingAnchors.keyFor(message.renderKey),
                          message: message,
                          anchorKey: (block) => readingAnchors.keyFor(
                            '${message.renderKey}:$block',
                          ),
                          controller: widget.appController,
                        ),
                      );
                    },
                  ),
                ),
                if (messages.isEmpty && !controller.loading)
                  Center(
                    child: Text(
                      context.tr('开始对话'),
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            footer: [
              ChatSpeechStatus(speech: widget.appController.speech),
              if (!composerCollapsed &&
                  mentionStart != null &&
                  (mentions.isNotEmpty || mentionAll))
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Material(
                    color: colors.surfaceContainerLow,
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        if (mentionAll)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.groups_outlined),
                            title: const Text('@all'),
                            onTap: () => _pickMention(null),
                          ),
                        for (final agent in mentions)
                          ListTile(
                            dense: true,
                            leading: AgentAvatar(
                              controller: widget.appController,
                              agentId: agent.agent,
                              size: 25,
                            ),
                            title: Text('@${agent.name}'),
                            onTap: () => _pickMention(agent),
                          ),
                      ],
                    ),
                  ),
                ),
              if (controller.timeline.interaction != null)
                _interactionPanel(context),
              ChatActivityStatus(
                working: controller.working,
                activity: controller.timeline.activity,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
