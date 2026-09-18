import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/studio_api.dart';
import '../state/app_controller.dart';
import '../state/group_chat_controller.dart';
import 'widgets/agent_avatar.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.api,
    required this.room,
    this.appController,
  });
  final StudioApi api;
  final GroupRoom room;
  final AppController? appController;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  late final GroupChatController controller;
  final input = TextEditingController();
  final scroll = ScrollController();
  bool showMentions = false;

  @override
  void initState() {
    super.initState();
    controller = GroupChatController(api: widget.api, room: widget.room)
      ..addListener(_changed);
    input.addListener(_inputChanged);
    scroll.addListener(_scrollChanged);
    controller.start();
  }

  void _changed() {
    if (mounted) setState(() {});
    if (controller.messages.isNotEmpty && scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _inputChanged() {
    final value = input.text;
    final at = value.lastIndexOf('@');
    final query = at < 0 ? '' : value.substring(at + 1);
    setState(
      () => showMentions = at >= 0 && !query.contains(' ') && query.length < 24,
    );
  }

  void _scrollChanged() {
    if (scroll.hasClients && scroll.position.pixels <= 80) {
      controller.loadOlder();
    }
  }

  void _pickMention(GroupAgentSummary? agent) {
    final value = input.text;
    final at = value.lastIndexOf('@');
    if (at < 0) {
      return;
    }
    final mention = agent == null ? '@all ' : '@${agent.name} ';
    input.value = TextEditingValue(
      text: '${value.substring(0, at)}$mention',
      selection: TextSelection.collapsed(offset: at + mention.length),
    );
    setState(() => showMentions = false);
  }

  Future<void> _send() async {
    final value = input.text.trim();
    if (value.isEmpty || controller.sending) {
      return;
    }
    input.clear();
    try {
      await controller.send(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(controller.error ?? '发送失败')));
      }
    }
  }

  @override
  void dispose() {
    input.removeListener(_inputChanged);
    input.dispose();
    scroll.removeListener(_scrollChanged);
    scroll.dispose();
    controller.removeListener(_changed);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.room.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${controller.agents.length} 个 Agent',
              style: TextStyle(
                fontSize: 11,
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (controller.agents.isNotEmpty)
            SizedBox(
              width: (controller.agents.length.clamp(1, 5)) * 25.0 + 12,
              height: 44,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  for (var i = 0; i < controller.agents.length && i < 5; i++)
                    Positioned(
                      left: i * 22,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: AgentAvatar(
                          controller: widget.appController,
                          agentId: controller.agents[i].agent,
                          size: 25,
                        ),
                      ),
                    ),
                ],
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
              leading: const Icon(Icons.cloud_off_outlined),
              actions: [
                TextButton(
                  onPressed: controller.start,
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(
            child: controller.loading && controller.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : controller.messages.isEmpty
                ? const Center(child: Text('还没有群聊消息'))
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
                    itemCount: controller.messages.length,
                    itemBuilder: (_, index) =>
                        _message(controller.messages[index]),
                  ),
          ),
          _composer(colors),
        ],
      ),
    );
  }

  Widget _message(GroupChatMessage message) {
    final colors = Theme.of(context).colorScheme;
    final agent = message.isAgent;
    final agentId = message.senderAgentType.isNotEmpty
        ? message.senderAgentType
        : message.senderName;
    return Align(
      alignment: agent ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .88,
        ),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
        decoration: BoxDecoration(
          color: agent
              ? colors.surfaceContainerLow
              : colors.primaryContainer.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.outlineVariant.withValues(alpha: .28),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (agent) ...[
              AgentAvatar(
                controller: widget.appController,
                agentId: agentId,
                size: 24,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent ? message.senderName : '我',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (message.content.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: SelectableText(
                        message.content,
                        style: const TextStyle(fontSize: 15, height: 1.42),
                      ),
                    ),
                  if (message.reasoning.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '思考中 · ${message.reasoning.trim()}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant.withValues(alpha: .72),
                          height: 1.3,
                        ),
                      ),
                    ),
                  if (message.isStreaming && message.content.trim().isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: SizedBox(
                        width: 28,
                        child: LinearProgressIndicator(
                          minHeight: 2,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(ColorScheme colors) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMentions)
            Align(
              alignment: Alignment.bottomLeft,
              child: Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.groups_rounded),
                        title: const Text('@all'),
                        subtitle: const Text('提醒所有 Agent'),
                        onTap: () => _pickMention(null),
                      ),
                      ...controller.agents.map(
                        (agent) => ListTile(
                          dense: true,
                          leading: AgentAvatar(
                            controller: widget.appController,
                            agentId: agent.agent,
                            size: 25,
                          ),
                          title: Text('@${agent.name}'),
                          onTap: () => _pickMention(agent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '输入消息，使用 @ 指定 Agent',
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: controller.sending || !controller.connected
                    ? null
                    : _send,
                icon: controller.sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
