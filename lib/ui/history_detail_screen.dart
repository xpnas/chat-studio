import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models.dart';
import '../data/task_plan.dart';
import '../state/app_controller.dart';
import '../state/chat_timeline.dart';
import 'widgets/message_bubble.dart';

class HistoryDetailScreen extends StatefulWidget {
  const HistoryDetailScreen({
    super.key,
    required this.controller,
    required this.conversation,
  });
  final AppController controller;
  final Conversation conversation;
  @override
  State<HistoryDetailScreen> createState() => _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  late final api = widget.controller.api!;
  late final profile = widget.controller.profile;
  final timeline = ChatTimeline();
  bool _leaving = false;
  bool loading = false, hasMore = false;
  int offset = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    timeline.sessionId = widget.conversation.id;
    widget.controller.addListener(_scopeChanged);
    unawaited(_load());
  }

  void _scopeChanged() {
    if (_leaving || !mounted) return;
    if (widget.controller.api == api && widget.controller.profile == profile) {
      return;
    }
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scopeChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (loading || _leaving) return;
    setState(() {
      loading = true;
      error = null;
    });
    final row = widget.conversation,
        id = Uri.encodeComponent(widget.conversation.id);
    try {
      Map<String, dynamic> data;
      try {
        data = await api.request(
          '/api/studio/sessions/conversations/$id/messages/paginated',
          query: {'profile': row.profile, 'offset': '$offset', 'limit': '60'},
        );
      } on ApiException catch (e) {
        if (offset != 0 || ![404, 405].contains(e.status)) rethrow;
        final legacy = await api.request(
          '/api/studio/sessions/hermes/$id',
          query: {'profile': row.profile},
        );
        data = {...asMap(legacy['session']), 'hasMore': false};
      }
      if (!mounted || _leaving) return;
      final rows = asList(data['messages']);
      final existing = timeline.messages.map((m) => m.id).toSet();
      final older = rows
          .map((m) => ChatMessage.fromJson(asMap(m)))
          .where((m) => !existing.contains(m.id))
          .toList();
      timeline.replace([...older, ...timeline.messages]);
      timeline.mergeTaskPlans(
        TaskPlan.parseList(data['taskPlans'], sessionId: row.id),
      );
      offset += rows.length;
      hasMore = rows.isNotEmpty && flag(data['hasMore']);
    } catch (e) {
      if (mounted) error = '$e';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = timeline.displayMessages;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.conversation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: const [
          Tooltip(
            message: '只读历史',
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Icon(Icons.history_rounded, size: 21),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              children: [
                if (loading) const LinearProgressIndicator(minHeight: 2),
                if (error != null)
                  MaterialBanner(
                    content: Text(error!),
                    actions: [
                      TextButton(
                        onPressed: loading ? null : _load,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                Expanded(
                  child: rows.isEmpty && !loading && error == null
                      ? const Center(child: Text('暂无消息'))
                      : ListView.builder(
                          reverse: true,
                          itemCount: rows.length + 1,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemBuilder: (context, index) => index == rows.length
                              ? hasMore
                                    ? Center(
                                        child: TextButton(
                                          onPressed: loading ? null : _load,
                                          child: const Text('加载更早消息'),
                                        ),
                                      )
                                    : const SizedBox.shrink()
                              : MessageBubble(
                                  message: rows[rows.length - 1 - index],
                                  controller: widget.controller,
                                  agentId: widget.conversation.agent,
                                ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
