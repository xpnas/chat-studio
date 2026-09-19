import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/studio_api.dart';
import '../state/app_controller.dart';
import '../state/group_chat_controller.dart';
import 'widgets/agent_avatar.dart';
import 'widgets/chat_composer.dart';
import 'widgets/message_bubble.dart';
import 'widgets/reading_handle.dart';
import 'widgets/chat_title.dart';
import 'widgets/chat_swipe_region.dart';
import 'widgets/conversation_drawer.dart';
import 'widgets/workspace_drawer.dart';

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
    with WidgetsBindingObserver {
  late final GroupChatController controller;
  final _scaffold = GlobalKey<ScaffoldState>();
  final _workspace = GlobalKey<GroupWorkspaceDrawerState>();
  late final String _profile;
  bool _leaving = false;
  final input = TextEditingController();
  final scroll = ScrollController();
  final progress = ValueNotifier<double>(0);
  bool collapsed = false, away = false, loadingOlder = false;
  bool _backgrounded = false, _historyCheckScheduled = false;
  bool _userScrolling = false;
  int? mentionStart;
  int mentionEnd = 0;
  String mentionQuery = '';

  @override
  void initState() {
    super.initState();
    controller =
        widget.controller ??
        GroupChatController(api: widget.api, room: widget.room);
    controller.addListener(_changed);
    _profile = widget.appController.profile;
    widget.appController.addListener(_appChanged);
    input.addListener(_inputChanged);
    scroll.addListener(_scrollChanged);
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
    _scheduleOlder();
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

  void _scrollChanged() {
    if (!scroll.hasClients) return;
    final position = scroll.position;
    final nextAway = position.pixels > 220;
    progress.value = historyReadProgress(position);
    final restore = collapsed && position.pixels <= 24;
    if (nextAway != away || restore) {
      setState(() {
        away = nextAway;
        if (restore) collapsed = false;
      });
    }
    _scheduleOlder();
  }

  void _scheduleOlder() {
    if (_historyCheckScheduled) return;
    _historyCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyCheckScheduled = false;
      if (!mounted ||
          !scroll.hasClients ||
          controller.loading ||
          loadingOlder ||
          !controller.hasMore ||
          controller.error != null) {
        return;
      }
      if (scroll.position.extentAfter <= 240) unawaited(_older());
    });
  }

  bool _chatScrolled(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _userScrolling = false;
    } else if (notification is ScrollUpdateNotification &&
        _userScrolling &&
        (notification.scrollDelta ?? 0) > 0 &&
        notification.metrics.pixels > 160 &&
        !collapsed) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => collapsed = true);
    }
    return false;
  }

  Future<void> _older() async {
    if (loadingOlder || controller.loading) return;
    loadingOlder = true;
    await controller.loadOlder();
    if (!mounted) return;
    loadingOlder = false;
    _scheduleOlder();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.appController.removeListener(_appChanged);
    controller.removeListener(_changed);
    if (widget.controller == null) controller.dispose();
    input.removeListener(_inputChanged);
    input.dispose();
    scroll.dispose();
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final messages = controller.displayMessages;
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
          tooltip: '对话记录',
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
          child: LinearProgressIndicator(
            minHeight: 2,
            value: controller.loading
                ? .62
                : controller.connected
                ? 0
                : .22,
            color: controller.loading ? colors.primary : colors.tertiary,
            backgroundColor: colors.surfaceContainerHighest.withValues(
              alpha: .32,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: '工作区',
            icon: const Icon(Icons.folder_copy_outlined, size: 21),
            onPressed: () => _scaffold.currentState?.openEndDrawer(),
          ),
          IconButton(
            tooltip: '新建对话',
            icon: const Icon(Icons.edit_square, size: 22),
            onPressed: widget.appController.busy ? null : _newChat,
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
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                Expanded(
                  child: ChatSwipeRegion(
                    onSwipe: (right) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (right) {
                        _scaffold.currentState?.openDrawer();
                      } else {
                        _scaffold.currentState?.openEndDrawer();
                      }
                    },
                    child: SizedBox.expand(
                      key: const Key('reading-stage'),
                      child: Stack(
                        children: [
                          NotificationListener<ScrollNotification>(
                            onNotification: _chatScrolled,
                            child: RefreshIndicator(
                              onRefresh: controller.start,
                              child: ListView.builder(
                                controller: scroll,
                                reverse: true,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                itemCount: messages.length + 1,
                                itemBuilder: (context, index) {
                                  if (index == messages.length) {
                                    return controller.hasMore
                                        ? Center(
                                            child: TextButton(
                                              onPressed: controller.loading
                                                  ? null
                                                  : _older,
                                              child: const Text('加载更早消息'),
                                            ),
                                          )
                                        : const SizedBox.shrink();
                                  }
                                  final message =
                                      messages[messages.length - 1 - index];
                                  return MessageBubble(
                                    key: ValueKey(message.id),
                                    message: message,
                                    controller: widget.appController,
                                  );
                                },
                              ),
                            ),
                          ),
                          if (messages.isEmpty && !controller.loading)
                            Center(
                              child: Text(
                                '开始对话',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          if (away)
                            Positioned(
                              right: 16,
                              bottom: 10,
                              child: IconButton.filledTonal(
                                tooltip: '回到最新消息',
                                icon: const Icon(Icons.arrow_downward_rounded),
                                onPressed: () => scroll.animateTo(
                                  0,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!collapsed &&
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
                ChatComposer(
                  controller: widget.appController,
                  input: input,
                  group: controller,
                  collapsed: collapsed,
                  readingProgress: progress,
                  onExpand: () {
                    _userScrolling = false;
                    setState(() => collapsed = false);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
