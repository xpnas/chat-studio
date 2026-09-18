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
    input.addListener(_inputChanged);
    scroll.addListener(_scrollChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.start());
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
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          controller.room.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .42,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final agent in controller.agents)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Tooltip(
                        message: agent.name,
                        child: AgentAvatar(
                          controller: widget.appController,
                          agentId: agent.agent,
                          size: 26,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
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
          if (controller.loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
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
                      padding: const EdgeInsets.symmetric(vertical: 8),
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
                        final message = messages[messages.length - 1 - index];
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
                      style: TextStyle(color: colors.onSurfaceVariant),
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
    );
  }
}
