import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/models.dart';
import '../state/app_controller.dart';
import 'profile_screen.dart';
import 'theme.dart';
import 'widgets/message_bubble.dart';

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
  Timer? _searchTimer;
  String? _lastSession;
  int _lastLength = 0;
  bool _showJump = false;
  AppController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    _scroll.addListener(_scrollChanged);
  }

  void _scrollChanged() {
    final value = _scroll.hasClients && _scroll.position.pixels > 220;
    if (value != _showJump && mounted) setState(() => _showJump = value);
  }

  void _changed() {
    if (!mounted) return;
    if (_lastSession != c.sessionId) {
      _lastSession = c.sessionId;
      _input.clear();
      _lastLength = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
      });
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
    _searchTimer?.cancel();
    super.dispose();
  }

  void _send() {
    if (c.send(_input.text)) {
      _input.clear();
      HapticFeedback.lightImpact();
    }
  }

  Future<void> _models() async {
    final selected = await showModalBottomSheet<ModelChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) =>
          _ModelSheet(models: c.models, selected: c.selectedModel),
    );
    if (selected != null) await c.chooseModel(selected);
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
        title: TextButton(
          onPressed: c.working || c.busy ? null : _models,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  c.selectedModel?.label ?? '服务端默认模型',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.expand_more_rounded,
                color: colors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: '新建对话',
            onPressed: c.working || c.busy ? null : c.newChat,
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
                  child: Stack(
                    children: [
                      if (c.timeline.messages.isEmpty && !c.loadingMessages)
                        _welcome(context)
                      else if (c.loadingMessages && c.timeline.messages.isEmpty)
                        const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      else
                        SelectionArea(
                          child: ListView.builder(
                            key: const Key('message-list'),
                            controller: _scroll,
                            reverse: true,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.only(bottom: 20, top: 12),
                            itemCount:
                                c.timeline.messages.length +
                                (c.hasMoreMessages ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == c.timeline.messages.length) {
                                return Center(
                                  child: TextButton(
                                    onPressed: c.loadingMessages
                                        ? null
                                        : () => c.loadHistory(more: true),
                                    child: Text(
                                      c.loadingMessages ? '正在加载…' : '加载更早的消息',
                                    ),
                                  ),
                                );
                              }
                              final message =
                                  c.timeline.messages[c
                                          .timeline
                                          .messages
                                          .length -
                                      index -
                                      1];
                              return MessageBubble(
                                key: ValueKey(message.id),
                                message: message,
                              );
                            },
                          ),
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
                            child: const Icon(Icons.arrow_downward_rounded),
                          ),
                        ),
                    ],
                  ),
                ),
                if (c.timeline.interaction != null)
                  _InteractionCard(controller: c),
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
                _composer(context),
              ],
            ),
          ),
        ),
      ),
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
                  style: TextStyle(fontSize: 13, color: colors.onSurface),
                  items: const [
                    DropdownMenuItem(
                      value: 'ekko-agent',
                      child: Text(
                        'Ekko Agent',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'hermes',
                      child: Text(
                        'Hermes Agent',
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
  Widget _composer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: colors.outlineVariant),
            ),
            padding: const EdgeInsets.fromLTRB(18, 6, 8, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('message-input'),
                    controller: _input,
                    minLines: 1,
                    maxLines: 6,
                    maxLength: 64000,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      hintText: '发消息给 Ekko',
                      counterText: '',
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    style: const TextStyle(fontSize: 16),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                ),
                const SizedBox(width: 6),
                ValueListenableBuilder(
                  valueListenable: _input,
                  builder: (context, value, _) => IconButton.filled(
                    key: Key(c.working ? 'stop-button' : 'send-button'),
                    tooltip: c.working ? '停止生成' : '发送消息',
                    onPressed: c.working
                        ? (c.connected ? c.stop : null)
                        : (c.canSend && value.text.trim().isNotEmpty
                              ? _send
                              : null),
                    icon: Icon(
                      c.working
                          ? Icons.stop_rounded
                          : Icons.arrow_upward_rounded,
                      size: 23,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI 的回答可能有误，请核实重要信息。',
            style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

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
                  onPressed: c.working || c.busy
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
                          return ListTile(
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
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              conversation.preview.isNotEmpty
                                  ? conversation.preview
                                  : conversation.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: c.working || c.busy
                                ? null
                                : () {
                                    Navigator.pop(context);
                                    c.openConversation(conversation);
                                  },
                            trailing: IconButton(
                              tooltip: '管理对话',
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                size: 18,
                              ),
                              onPressed:
                                  c.working && c.sessionId == conversation.id
                                  ? null
                                  : () => _manage(conversation),
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
                      onChanged: c.working || c.busy
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

class _ModelSheet extends StatefulWidget {
  const _ModelSheet({required this.models, this.selected});
  final List<ModelChoice> models;
  final ModelChoice? selected;
  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final visible = widget.models
        .where(
          (m) => '${m.label} ${m.id} ${m.providerLabel}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .72,
      child: Column(
        children: [
          const Text(
            '选择模型',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('使用服务端已配置的模型，不在手机保存模型密钥', style: TextStyle(fontSize: 12)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                hintText: '搜索模型或提供商',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('没有可用模型，请在 Studio 中配置'))
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final model = visible[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 4,
                        ),
                        leading: const Icon(Icons.auto_awesome_outlined),
                        title: Text(model.label),
                        subtitle: Text(
                          model.providerLabel.isEmpty
                              ? model.provider
                              : model.providerLabel,
                        ),
                        trailing: widget.selected?.key == model.key
                            ? Icon(
                                Icons.check_circle_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () => Navigator.pop(context, model),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _InteractionCard extends StatefulWidget {
  const _InteractionCard({required this.controller});
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
              if (approval)
                Wrap(
                  spacing: 8,
                  children: [
                    // No permanent/session-wide approval in this lightweight client.
                    OutlinedButton(
                      onPressed: widget.controller.connected
                          ? () => widget.controller.respondToInteraction('deny')
                          : null,
                      child: const Text('拒绝'),
                    ),
                    if (choices.contains('once'))
                      FilledButton(
                        onPressed: widget.controller.connected
                            ? () =>
                                  widget.controller.respondToInteraction('once')
                            : null,
                        child: const Text('仅允许本次'),
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
                            onPressed: () =>
                                widget.controller.respondToInteraction(v),
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
                      onPressed: () {
                        if (field.text.trim().isNotEmpty) {
                          widget.controller.respondToInteraction(
                            field.text.trim(),
                          );
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
