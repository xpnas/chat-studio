import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../l10n.dart';
import '../data/models.dart';
import '../data/person_models.dart';
import '../data/person_api.dart';
import '../data/protocol_capabilities.dart';
import '../data/studio_api.dart';
import '../state/app_controller.dart';
import '../state/person_controller.dart';
import '../state/chat_timeline.dart';
import '../state/person_list_controller.dart';
import '../state/person_flow_details_controller.dart';
import '../state/person_task_controller.dart';
import 'theme.dart';
import 'widgets/message_bubble.dart';
import 'widgets/chat_history_list.dart';
import 'widgets/chat_reading_view.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_swipe_region.dart';
import 'widgets/conversation_drawer.dart';
import 'group_chat_screen.dart';
import 'widgets/chat_interaction_card.dart';
import 'person_create_screen.dart';

String personStateLabel(BuildContext context, String state) =>
    context.tr(switch (state) {
      'active' || 'open' => '进行中',
      'completed' => '已完成',
      'closed' => '已关闭',
      'pending' => '待处理',
      'queued' => '排队中',
      'starting' => '正在启动',
      'running' => '执行中',
      'stopping' => '正在停止',
      'waiting_person' => '等待 BOT',
      'waiting_user' => '等待用户',
      'waiting_approval' => '等待审批',
      'finished' => '执行结束',
      'failed' => '失败',
      'interrupted' => '已中断',
      'stopped' => '已停止',
      'idle' => '空闲',
      'delivered' => '已交付',
      'cancelling' => '正在取消',
      'cancelled' => '已取消',
      _ => state,
    });

class PersonListScreen extends StatefulWidget {
  const PersonListScreen({
    super.key,
    required this.app,
    this.controller,
    this.embedded = false,
    this.onOpen,
    this.showSearch = true,
    this.initialSearch = '',
    this.selectedSessionId,
  });
  final AppController app;
  final PersonListController? controller;
  final bool embedded;
  final ValueChanged<PersonConversation>? onOpen;
  final bool showSearch;
  final String initialSearch;
  final String? selectedSessionId;
  @override
  State<PersonListScreen> createState() => PersonListScreenState();
}

class PersonListScreenState extends State<PersonListScreen>
    with WidgetsBindingObserver {
  late final StudioApi api;
  late final PersonListController c;
  late final String token, server;
  late final Object account;
  final search = TextEditingController();
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    final current = widget.app.api!;
    server = current.address.value;
    token = current.token;
    account = widget.app.account!.id;
    api = widget.controller?.api ?? widget.app.createAccountClient();
    c = widget.controller ?? PersonListController(api, account, valid);
    c.addListener(changed);
    widget.app.addListener(scopeChanged);
    WidgetsBinding.instance.addObserver(this);
    search.text = widget.initialSearch;
    unawaited(c.refresh(query: search.text));
  }

  bool valid() =>
      widget.app.authenticated &&
      widget.app.api?.address.value == server &&
      widget.app.api?.token == token &&
      widget.app.account?.id == account;
  void changed() {
    if (mounted) setState(() {});
  }

  void searchFor(String query) {
    if (!mounted || !valid()) return;
    search.text = query;
    unawaited(c.refresh(query: query));
  }

  Future<void> createConversation() async {
    if (!valid() || !AppController.botsEnabled) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final bot = await Navigator.push<PersonConversation>(
      context,
      MaterialPageRoute(
        builder: (_) => PersonCreateScreen(
          app: widget.app,
          api: api,
          account: account,
          valid: valid,
        ),
      ),
    );
    if (!mounted || !valid()) return;
    await c.refresh();
    if (bot != null && mounted && valid()) await open(bot);
  }

  void scopeChanged() {
    if (valid()) return;
    if (widget.embedded) {
      changed();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(c.refresh());
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(scopeChanged);
    c.removeListener(changed);
    if (widget.controller == null) {
      c.dispose();
      api.close();
    }
    super.dispose();
  }

  Future<void> open(PersonConversation bot) async {
    if (widget.onOpen != null) {
      widget.onOpen!(bot);
      return;
    }
    if (!AppController.botsEnabled) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(context.tr('BOT 功能尚未通过此版本验收，请在 Studio 使用')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.tr('关闭')),
            ),
          ],
        ),
      );
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PersonScreen(app: widget.app, sessionId: bot.id),
      ),
    );
    if (mounted) await c.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!valid()) return Center(child: Text(context.tr('账号已变化')));
    final body = Column(
      children: [
        if (!widget.embedded)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: createConversation,
                icon: const Icon(Icons.add_rounded),
                label: Text(context.tr('新建对话')),
              ),
            ),
          ),
        if (widget.showSearch)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: TextField(
              controller: search,
              decoration: InputDecoration(
                hintText: context.tr('搜索 BOT'),
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
              ),
              onChanged: (query) {
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => c.refresh(query: query),
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
                  context.tr('BOT 对话'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('刷新记录'),
                onPressed: c.loading ? null : () => c.refresh(),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
        ),
        if (c.loading) const LinearProgressIndicator(minHeight: 2),
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              c.capability == CapabilityState.unsupported
                  ? context.tr('服务端不支持 BOT，请在 Studio 升级后重试')
                  : context.tr(c.error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => c.refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
              children: [
                if (!c.loading && c.error == null && c.sessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        context.tr(
                          c.search.isEmpty ? '还没有 BOT 对话，点击新建对话开始' : '没有找到相关对话',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                for (final bot in c.sessions)
                  ListTile(
                    key: ValueKey('bot-history:${bot.id}'),
                    minTileHeight: 54,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    horizontalTitleGap: 10,
                    selected: widget.selectedSessionId == bot.id,
                    selectedTileColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: .4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Icon(
                      Icons.smart_toy_outlined,
                      size: 19,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      bot.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      bot.profile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => open(bot),
                  ),
                if (c.nextOffset != null)
                  TextButton(
                    onPressed: c.loading ? null : () => c.refresh(more: true),
                    child: Text(context.tr('加载更多')),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('BOT 对话')),
        actions: [
          IconButton(
            onPressed: () => c.refresh(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.tr('刷新'),
          ),
        ],
      ),
      body: body,
    );
  }
}

class PersonScreen extends StatefulWidget {
  const PersonScreen({
    super.key,
    required this.app,
    required this.sessionId,
    this.controller,
  });
  final AppController app;
  final String sessionId;
  final PersonController? controller;
  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen>
    with WidgetsBindingObserver, ChatReadingState<PersonScreen> {
  PersonController? c;
  String? error;
  final input = TextEditingController();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _historyViewport = GlobalKey();
  final _messageKeys = <String, GlobalKey>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.app.addListener(scopeChanged);
    unawaited(start());
  }

  Future<void> start() async {
    try {
      final controller =
          widget.controller ??
          await widget.app.personController(widget.sessionId);
      if (!mounted) return;
      c = controller;
      initReading(restoreInitial: true);
      input.text = controller.draft.text;
      controller.addListener(changed);
      if (!controller.transport.isStarted) controller.onForeground();
      changed();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void scopeChanged() {
    final controller = c;
    if (controller == null || controller.valid) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null) Navigator.of(context).removeRoute(route);
    });
  }

  @override
  ChatReadingSnapshot get readingSnapshot => ChatReadingSnapshot(
    id: c!.sessionId,
    draft: c!.draft,
    messageCount: c!.timeline.items.length + c!.live.messages.length,
    liveRevision: c!.live.liveRevision,
    readingOlder: c!.timeline.readingOlder,
    hasNewer: c!.timeline.hasNewer,
    // The BOT projection keeps old pages in a separate bounded window. Do not
    // replace that window from an automatic latest-edge prefetch.
    canLoadEarlier:
        c!.connected &&
        !c!.syncing &&
        !c!.loadingOlder &&
        c!.error == null &&
        c!.timeline.hasMore &&
        readingScroll.hasClients &&
        readingScroll.offset > 120,
  );
  @override
  bool get readingRouteVisible =>
      ModalRoute.of(context)?.isCurrent == true &&
      _scaffold.currentState?.isDrawerOpen != true &&
      _scaffold.currentState?.isEndDrawerOpen != true;
  @override
  bool get readingHintSeen => widget.app.readingHintSeen;
  @override
  Future<void> markReadingHintSeen() => widget.app.markReadingHintSeen();
  @override
  void beginHistoryReading() => c!.timeline.beginReading();
  @override
  Future<void> showLatestHistory() async {
    c!.showLatest();
  }

  @override
  Future<void> loadEarlierHistory() => c!.loadOlder();

  void changed() {
    if (!mounted) return;
    setState(() {});
    readingChanged();
  }

  @override
  Future<void> confirmLatestVisible() async {
    final controller = c!;
    int? visibleCursor;
    final viewport = _historyViewport.currentContext?.findRenderObject();
    if (viewport is RenderBox && viewport.hasSize) {
      final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;
      String? anchor;
      for (final item in controller.timeline.items) {
        final box = _messageKeys[item.key]?.currentContext?.findRenderObject();
        if (box is! RenderBox ||
            !box.hasSize ||
            !(box.localToGlobal(Offset.zero) & box.size).overlaps(bounds)) {
          continue;
        }
        anchor ??= item.key;
        if (item.kind != 'message' ||
            controller.timeline.messages[item.id]?.role != 'assistant') {
          continue;
        }
        final id = int.tryParse(item.id);
        if (id != null && (visibleCursor == null || id > visibleCursor)) {
          visibleCursor = id;
        }
      }
      controller.timeline.anchorKey = anchor ?? controller.timeline.anchorKey;
    }
    await controller.confirmVisibleRead(
      latest: true,
      routeVisible: readingRouteVisible,
      visibleMessageId: visibleCursor,
    );
  }

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c?.onForeground();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      c?.onBackground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.app.removeListener(scopeChanged);
    c?.draft.text = input.text;
    c?.removeListener(changed);
    c?.onBackground();
    input.dispose();
    disposeReading();
    super.dispose();
  }

  void openConversation(Conversation conversation) {
    if (isPersonMain(conversation.id)) {
      if (conversation.id == widget.sessionId) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              PersonScreen(app: widget.app, sessionId: conversation.id),
        ),
      );
      return;
    }
    unawaited(widget.app.openConversation(conversation));
    Navigator.of(context).pop();
  }

  Future<void> details(PersonFlow flow) async {
    final controller = c;
    if (controller == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PersonFlowScreen(person: controller, flow: flow),
      ),
    );
    if (mounted) controller.scheduleRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final controller = c;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('BOT 对话'))),
        body: Center(
          child: error == null
              ? const CircularProgressIndicator()
              : Text(error!),
        ),
      );
    }
    final live = controller.live, history = controller.timeline;
    final visibleIds = history.items
        .where((i) => i.kind == 'message')
        .map((i) => i.id)
        .toSet();
    final extra = history.readingOlder
        ? <ChatMessage>[]
        : live.messages
              .where((m) => m.visible && !visibleIds.contains(m.id))
              .toList();
    final rows = <({String key, PersonFlow? flow, ChatMessage? message})>[];
    final segment = <({String key, ChatMessage message})>[];
    _messageKeys.clear();
    void flushMessages() {
      if (segment.isEmpty) return;
      // Use the ordinary-chat reducer for interim/adjacent assistant segments.
      final reducer = ChatTimeline()
        ..messages = segment.map((row) => row.message).toList();
      final displayed = reducer.displayMessages;
      for (var i = 0; i < displayed.length; i++) {
        final message = displayed[i];
        final start = segment.indexWhere(
          (row) => row.message.renderKey == message.renderKey,
        );
        final end = i + 1 < displayed.length
            ? segment.indexWhere(
                (row) => row.message.renderKey == displayed[i + 1].renderKey,
              )
            : segment.length;
        final key = start < 0
            ? 'display:${message.renderKey}'
            : segment[start].key;
        final anchor = readingAnchors.keys.putIfAbsent(key, () => GlobalKey());
        if (start >= 0) {
          for (final source
              in segment.skip(start).take(end > start ? end - start : 1)) {
            _messageKeys[source.key] = anchor;
          }
        }
        rows.add((key: key, flow: null, message: message));
      }
      segment.clear();
    }

    for (final item in history.items) {
      if (item.kind == 'flow' && history.flows[item.id] != null) {
        flushMessages();
        rows.add((key: item.key, flow: history.flows[item.id], message: null));
        _messageKeys[item.key] = readingAnchors.keys.putIfAbsent(
          item.key,
          () => GlobalKey(),
        );
      } else if (item.kind == 'message' &&
          history.messages[item.id]?.visible == true) {
        segment.add((
          key: item.key,
          message:
              live.messages.where((m) => m.id == item.id).firstOrNull ??
              history.messages[item.id]!,
        ));
      }
    }
    for (final message in extra) {
      segment.add((key: 'live:${message.renderKey}', message: message));
    }
    flushMessages();
    final retained = rows.map((row) => row.key).toSet();
    readingAnchors.prune(retained);
    final indices = {
      for (var i = 0; i < rows.length; i++)
        ValueKey(rows[i].key): rows.length - i - 1,
    };
    return Scaffold(
      key: _scaffold,
      drawerEnableOpenDragGesture: false,
      endDrawerEnableOpenDragGesture: false,
      onDrawerChanged: (open) {
        if (!open) scheduleReadReceipt();
      },
      onEndDrawerChanged: (open) {
        if (!open) scheduleReadReceipt();
      },
      endDrawer: _PersonActivityDrawer(
        person: controller,
        onOpenFlow: (flow) {
          Navigator.pop(context);
          details(flow);
        },
      ),
      drawer: widget.app.authenticated
          ? ConversationDrawer(
              controller: widget.app,
              initialTab: 2,
              selectedBotSessionId: widget.sessionId,
              onNewChat: () {
                widget.app.newChat();
                Navigator.of(context).pop();
              },
              onOpenConversation: openConversation,
              onOpenGroup: (room) {
                final api = widget.app.api;
                if (api == null) return;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => GroupChatScreen(
                      api: api,
                      room: room,
                      appController: widget.app,
                    ),
                  ),
                );
              },
            )
          : null,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('BOT 对话'),
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffold.currentState?.openDrawer(),
        ),
        titleSpacing: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: ChatConnectionLine(
            connected: controller.connected,
            syncing: controller.syncing,
            onReconnect: controller.reconnect,
          ),
        ),
        title: Row(
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 22,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.snapshot?.session.title ?? context.tr('BOT 对话'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${context.tr(controller.working ? '主会话运行中' : '主会话空闲')} · ${context.l10n.format('后台任务 {0}', {'0': controller.backgroundPending})}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.tr('活动协作'),
            onPressed: () => _scaffold.currentState?.openEndDrawer(),
            icon: const Icon(Icons.groups_outlined),
          ),
          IconButton(
            tooltip: context.tr('刷新'),
            onPressed: () {
              controller.scheduleRefresh();
              controller.sync.refresh();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: context.tr('发起协作'),
            onPressed:
                controller.snapshot == null ||
                    controller.operation.pending ||
                    controller.operation.uncertain
                ? null
                : () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PersonFlowForm(person: controller),
                    ),
                  ),
            icon: const Icon(Icons.route_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ChatBody(
        notices: [
          if (controller.snapshot != null && !controller.configurationReady)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                context.tr('请先在 Studio 配置 BOT 模型和执行 Agent'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (controller.snapshot != null && controller.resourceAllowed != true)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                context.tr('BOT 执行资源不可用，请在 Studio 核对访问权限'),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          if (error ?? controller.error case final String message)
            ErrorNotice(
              message: context.tr(message),
              onDismiss: () {
                if (error != null) {
                  setState(() => error = null);
                } else {
                  controller.error = null;
                  controller.changed();
                }
              },
            ),
          PersonOperationNotice(person: controller),
        ],
        child: ChatComposer(
          controller: widget.app,
          person: controller,
          input: input,
          collapsed: composerCollapsed,
          onExpand: expandReadingComposer,
          readingProgress: readingProgress,
          layoutBuilder: (editor, handle, stop) => readingLayout(
            history: Stack(
              children: [
                ChatHistoryList(
                  listKey: _historyViewport,
                  controller: readingScroll,
                  itemCount: rows.length + (history.hasMore ? 1 : 0),
                  findChildIndexCallback: (key) => indices[key],
                  itemBuilder: (context, index) {
                    if (index == rows.length) {
                      return Center(
                        child: TextButton(
                          onPressed: controller.loadingOlder
                              ? null
                              : controller.loadOlder,
                          child: Text(context.tr('加载更早消息')),
                        ),
                      );
                    }
                    final row = rows[rows.length - index - 1];
                    final anchor = readingAnchors.keys[row.key];
                    return Container(
                      key: ValueKey(row.key),
                      child: row.flow != null
                          ? PersonFlowCard(
                              key: anchor,
                              flow: row.flow!,
                              onOpen: () => details(row.flow!),
                            )
                          : MessageBubble(
                              key: anchor,
                              message: row.message!,
                              controller: controller,
                              anchorKey: (block) =>
                                  readingAnchors.keyFor('${row.key}:$block'),
                            ),
                    );
                  },
                ),
                if (rows.isEmpty && !controller.syncing && !history.hasMore)
                  Center(
                    child: Text(
                      context.tr('开始 BOT 对话'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            editor: editor,
            handle: handle,
            stop: stop,
            wrapReading: _swipeReading,
            footer: [
              ChatSpeechStatus(speech: controller.speech),
              if (live.interaction != null ||
                  controller.interactions.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .48,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (live.interaction != null)
                        PersonQuestion(
                          key: ValueKey(controller.liveInteractionKey),
                          event: live.interaction!,
                          enabled:
                              controller.connected &&
                              !live.interactionSubmitting,
                          submitting: live.interactionSubmitting,
                          onAnswer: controller.answerLive,
                        ),
                      for (final interaction in controller.interactions.where(
                        (i) => i.key != controller.liveInteractionKey,
                      ))
                        PersonQuestion(
                          key: ValueKey(interaction.key),
                          event: interaction.event,
                          enabled: !controller.answering.contains(
                            interaction.key,
                          ),
                          submitting: controller.answering.contains(
                            interaction.key,
                          ),
                          onAnswer: (answer) =>
                              controller.answer(interaction, answer),
                        ),
                    ],
                  ),
                ),
              ChatActivityStatus(
                working: controller.working,
                activity: live.activity,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonActivityDrawer extends StatelessWidget {
  const _PersonActivityDrawer({required this.person, required this.onOpenFlow});
  final PersonController person;
  final ValueChanged<PersonFlow> onOpenFlow;

  @override
  Widget build(BuildContext context) {
    final flows = person.timeline.flows.values
        .where((flow) => !flow.terminal)
        .toList();
    return Drawer(
      key: const Key('bot-activity-drawer'),
      width: MediaQuery.sizeOf(context).width,
      child: SafeArea(
        child: ListView(
          children: [
            ListTile(
              title: Text(
                context.tr('活动协作'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              trailing: IconButton(
                tooltip: context.tr('关闭'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            if (flows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.tr('暂无活动协作')),
              ),
            for (final flow in flows)
              PersonFlowCard(flow: flow, onOpen: () => onOpenFlow(flow)),
            const Divider(),
            ListTile(
              title: Text(
                context.l10n.format('后台任务 {0}', {
                  '0': person.backgroundPending,
                }),
              ),
            ),
            for (final task in person.snapshot?.tasks ?? <PersonTask>[])
              ListTile(
                leading: const Icon(Icons.task_alt_outlined),
                title: Text(task.title),
                subtitle: Text(
                  personStateLabel(
                    context,
                    task.executionState.isEmpty
                        ? task.status
                        : task.executionState,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PersonTaskScreen(person: person, taskId: task.id),
                    ),
                  );
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text(context.tr('BOT 模型与工作区')),
              subtitle: Text(
                '${text(asMap(person.snapshot?.settings['model'])['model'])} · ${person.snapshot?.session.profile ?? ''}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PersonQuestion extends StatelessWidget {
  const PersonQuestion({
    super.key,
    required this.event,
    required this.enabled,
    required this.submitting,
    required this.onAnswer,
  });
  final Map<String, dynamic> event;
  final bool enabled, submitting;
  final void Function(String) onAnswer;
  @override
  Widget build(BuildContext context) => ChatInteractionCard(
    data: event,
    enabled: enabled,
    submitting: submitting,
    onRespond: onAnswer,
    allowPermanent: false,
  );
}

class PersonOperationNotice extends StatelessWidget {
  const PersonOperationNotice({super.key, required this.person});
  final PersonController person;
  Future<void> retry() async {
    final operation = person.operation, payload = operation.payload;
    if (payload == null || operation.target == null) return;
    final input = Map<String, dynamic>.of(payload)..remove('idempotency_key');
    final target = operation.target!;
    await operation.perform(target, input, (body) async {
      if (target == 'flow') {
        return (await person.api.applyPersonFlow(body)).json;
      }
      if (target.startsWith('task-chat:')) {
        return person.api.continuePersonTask(target.substring(10), body);
      }
      if (target.startsWith('task-stop:')) {
        return person.api.stopPersonTask(body);
      }
      throw StateError('Unknown operation');
    }, retry: true);
    await person.refreshSnapshot();
    person.requestResume();
  }

  @override
  Widget build(BuildContext context) {
    final operation = person.operation;
    if (!operation.uncertain && operation.error == null) {
      return const SizedBox.shrink();
    }
    return MaterialBanner(
      content: Text(
        context.tr(
          operation.uncertain ? '操作结果未知，已保留原幂等键；请先核对服务端状态' : operation.error!,
        ),
      ),
      actions: [
        TextButton(
          onPressed: operation.pending ? null : () => person.scheduleRefresh(),
          child: Text(context.tr('刷新核对')),
        ),
        if (operation.uncertain)
          TextButton(
            onPressed: operation.pending ? null : retry,
            child: Text(context.tr('使用原操作重试')),
          ),
      ],
    );
  }
}

class PersonFlowCard extends StatelessWidget {
  const PersonFlowCard({super.key, required this.flow, required this.onOpen});
  final PersonFlow flow;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      onTap: onOpen,
      leading: const Icon(Icons.route_outlined),
      title: Text(flow.title),
      subtitle: Text(
        '${personStateLabel(context, flow.state)} · ${context.l10n.format('第 {0} 轮 / {1}', {'0': flow.roundNumber, '1': flow.roundLimit == 0 ? context.tr('持续运行') : flow.roundLimit})}\n${flow.stages.where((s) => s.group == flow.position).map((s) => s.confirmation['decision_pending'] == true ? context.tr('服务端确认中') : personStateLabel(context, s.deliveryState.isNotEmpty ? s.deliveryState : s.state)).join(' · ')}',
      ),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class PersonFlowScreen extends StatefulWidget {
  const PersonFlowScreen({super.key, required this.person, required this.flow});
  final PersonController person;
  final PersonFlow flow;
  @override
  State<PersonFlowScreen> createState() => _PersonFlowScreenState();
}

class _PersonFlowScreenState extends State<PersonFlowScreen> {
  late int _mainGeneration = widget.person.timeline.generation;
  late final c = PersonFlowDetailsController(
    widget.person.api,
    widget.flow.id,
    () => widget.person.valid,
  );
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    widget.person.addListener(personChanged);
    unawaited(c.refresh());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void personChanged() {
    if (!mounted) return;
    if (_mainGeneration != widget.person.timeline.generation) {
      _mainGeneration = widget.person.timeline.generation;
      c.invalidate();
      unawaited(c.refresh());
    } else if (!c.loading &&
        (widget.person.timeline.flows[widget.flow.id]?.revision ?? 0) >
            (c.flow?.revision ?? widget.flow.revision)) {
      unawaited(c.refresh());
    }
    changed();
  }

  @override
  void dispose() {
    widget.person.removeListener(personChanged);
    c.removeListener(changed);
    c.dispose();
    super.dispose();
  }

  Future<void> control(String action) async {
    final person = widget.person, flow = c.flow ?? widget.flow;
    if (action == 'stop' && !flow.canStop ||
        action == 'resume' && !flow.canResume) {
      return;
    }
    await person.operation.perform('flow', {
      'action': action,
      'flow_id': flow.id,
      'expected_revision': flow.revision,
    }, (body) async => (await person.api.applyPersonFlow(body)).json);
    await c.refresh();
    await person.refreshSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person, flow = c.flow ?? widget.flow;
    if (!person.valid) {
      return Scaffold(body: Center(child: Text(context.tr('账号已变化'))));
    }
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(flow.title),
        actions: [
          IconButton(
            tooltip: context.tr('刷新'),
            onPressed: () => c.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PersonOperationNotice(person: person),
            if (flow.goal.isNotEmpty) ...[
              Text(flow.goal),
              const SizedBox(height: 6),
            ],
            Text(
              '${personStateLabel(context, flow.state)} · ${flow.roundNumber}/${flow.roundLimit == 0 ? context.tr('持续运行') : flow.roundLimit}',
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
            if (flow.error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(flow.error, style: TextStyle(color: colors.error)),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (flow.canStop)
                  TextButton(
                    onPressed:
                        person.operation.pending || person.operation.uncertain
                        ? null
                        : () => control('stop'),
                    child: Text(context.tr('停止协作')),
                  ),
                if (flow.canResume)
                  TextButton(
                    onPressed:
                        person.operation.pending || person.operation.uncertain
                        ? null
                        : () => control('resume'),
                    child: Text(context.tr('恢复协作')),
                  ),
              ],
            ),
            for (final stage in flow.stages)
              Card(
                key: ValueKey('${stage.id}:${stage.group}:${stage.position}'),
                child: ListTile(
                  title: Text(
                    '${stage.group + 1} · ${stage.sessionTitle.isEmpty ? stage.sessionId : stage.sessionTitle}',
                  ),
                  subtitle: Text(
                    '${stage.goal}\n${stage.returnExpectation}\n${stage.confirmation['decision_pending'] == true ? context.tr('服务端确认中') : personStateLabel(context, stage.state)}\n${personStateLabel(context, stage.deliveryState)} ${stage.deliveryError}',
                  ),
                  onTap: stage.resultMessageId == null
                      ? null
                      : () async {
                          final found = await c.locate(
                            stage.resultMessageId!,
                            stage.id,
                          );
                          if (!context.mounted || c.locating) return;
                          showDialog<void>(
                            context: context,
                            builder: (context) => AlertDialog(
                              content: found == null
                                  ? Text(context.tr(c.error ?? '协作结果已删除或不可用'))
                                  : MessageBubble(
                                      message: ChatMessage.fromJson(found),
                                      controller: person,
                                    ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text(context.tr('关闭')),
                                ),
                              ],
                            ),
                          );
                        },
                ),
              ),
            if (c.locating)
              TextButton(
                onPressed: c.cancelLocate,
                child: Text(context.tr('取消定位')),
              ),
            if (c.loading) const LinearProgressIndicator(),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(c.error!, style: TextStyle(color: colors.error)),
              ),
            for (final row in c.messages)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['session_title'] ?? row['session_id']} · ${row['stage_id']} · ${row['round_number']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    MessageBubble(
                      message: ChatMessage.fromJson(row),
                      controller: person,
                    ),
                  ],
                ),
              ),
            if (c.hasMore)
              TextButton(
                onPressed: c.loading ? null : () => c.refresh(more: true),
                child: Text(context.tr('加载更多')),
              ),
          ],
        ),
      ),
    );
  }
}

class PersonTaskScreen extends StatefulWidget {
  const PersonTaskScreen({
    super.key,
    required this.person,
    required this.taskId,
  });
  final PersonController person;
  final String taskId;
  @override
  State<PersonTaskScreen> createState() => _PersonTaskScreenState();
}

class _PersonTaskScreenState extends State<PersonTaskScreen> {
  late final c = PersonTaskController(widget.person, widget.taskId);
  final input = TextEditingController();
  @override
  void initState() {
    super.initState();
    c.addListener(changed);
    widget.person.addListener(personChanged);
    unawaited(c.refresh());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void personChanged() {
    final current = widget.person.snapshot?.tasks
        .where((task) => task.id == widget.taskId)
        .firstOrNull;
    if (!c.loading &&
        current != null &&
        current.revision > (c.task?.revision ?? -1)) {
      unawaited(c.refresh());
    }
    changed();
  }

  @override
  void dispose() {
    widget.person.removeListener(personChanged);
    c.removeListener(changed);
    c.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final person = widget.person, task = c.task;
    if (!person.valid) {
      return Scaffold(body: Center(child: Text(context.tr('账号已变化'))));
    }
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(task?.title ?? context.tr('BOT 任务')),
        actions: [
          IconButton(
            tooltip: context.tr('刷新'),
            onPressed: () => c.refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PersonOperationNotice(person: person),
            if (c.loading) const LinearProgressIndicator(),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(c.error!, style: TextStyle(color: colors.error)),
              ),
            if (task != null) ...[
              if (task.summary.isNotEmpty) ...[
                Text(task.summary),
                const SizedBox(height: 6),
              ],
              Text(
                '${personStateLabel(context, task.status)} · ${personStateLabel(context, task.executionState)}',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              Text(
                '${context.tr('验收状态')} · ${personStateLabel(context, task.acceptanceState)}${task.acceptanceReason.isEmpty ? '' : ' ${task.acceptanceReason}'}',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                isExpanded: true,
                value: c.selectedExecution,
                items: [
                  DropdownMenuItem(value: '', child: Text(context.tr('当前执行'))),
                  for (final execution in c.executions)
                    DropdownMenuItem(
                      value: execution.id,
                      child: Text(
                        '${execution.id} · ${personStateLabel(context, execution.state)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: c.loading
                    ? null
                    : (id) => c.refresh(executionId: id),
              ),
              if (!c.current)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.tr('历史执行只读'),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              if (c.execution != null) ...[
                const SizedBox(height: 8),
                Text(
                  personStateLabel(context, c.execution!.state),
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (c.execution!.error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      c.execution!.error,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                MessageBubble(
                  message: ChatMessage(
                    id: c.execution!.id,
                    role: 'assistant',
                    content: c.execution!.output,
                    attachments: MessageAttachment.parse(c.execution!.output),
                  ),
                  controller: person,
                ),
              ],
              if (c.pending.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  context.tr('待处理输入'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              for (final row in c.pending)
                ListTile(title: Text(messageText(row['input']))),
              const SizedBox(height: 12),
              TextField(
                controller: input,
                enabled: c.canFollowUp,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(labelText: context.tr('追问当前任务')),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton(
                    onPressed: c.canFollowUp
                        ? () async {
                            final value = input.text;
                            await c.followUp(value);
                            if (mounted &&
                                !person.operation.uncertain &&
                                person.operation.error == null) {
                              input.clear();
                            }
                          }
                        : null,
                    child: Text(context.tr('提交追问')),
                  ),
                  if (c.current && task.running)
                    TextButton(
                      onPressed:
                          person.operation.pending || person.operation.uncertain
                          ? null
                          : c.stop,
                      child: Text(context.tr('停止任务')),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PersonFlowForm extends StatefulWidget {
  const PersonFlowForm({super.key, required this.person});
  final PersonController person;
  @override
  State<PersonFlowForm> createState() => _PersonFlowFormState();
}

class _FlowStageFields {
  String bot = '';
  int group = 0;
  final goal = TextEditingController(), expectation = TextEditingController();
  void dispose() {
    goal.dispose();
    expectation.dispose();
  }
}

class _PersonFlowFormState extends State<PersonFlowForm> {
  final title = TextEditingController(),
      goal = TextEditingController(),
      rounds = TextEditingController(text: '1');
  final stages = [_FlowStageFields()];
  List<PersonConversation> bots = [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    widget.person.addListener(changed);
    unawaited(load());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    try {
      int? offset = 0;
      final all = <String, PersonConversation>{};
      while (offset != null && widget.person.valid) {
        final page = await widget.person.api.personConversations(
          widget.person.account,
          offset: offset,
        );
        for (final bot in page.sessions) {
          all[bot.id] = bot;
        }
        if (page.nextOffset == offset) break;
        offset = page.nextOffset;
      }
      if (mounted) {
        setState(() {
          bots = all.values.toList();
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.person.removeListener(changed);
    title.dispose();
    goal.dispose();
    rounds.dispose();
    for (final stage in stages) {
      stage.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    final person = widget.person;
    final draft = PersonFlowDraft(
      creator: person.sessionId,
      title: title.text,
      goal: goal.text,
      rounds: int.tryParse(rounds.text) ?? 0,
      stages: [
        for (final stage in stages)
          (
            sessionId: stage.bot,
            goal: stage.goal.text,
            expectation: stage.expectation.text,
            group: stage.group,
          ),
      ],
    );
    final invalid = draft.validate(bots.map((b) => b.id).toSet());
    if (invalid != null) {
      setState(() => error = invalid);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr(invalid))));
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('确认协作路线')),
        content: SingleChildScrollView(
          child: Text(
            '${draft.title}\n${draft.goal}\n${draft.rounds} ${context.tr('轮')}\n${draft.stages.map((s) => '${s.group + 1}: ${bots.where((b) => b.id == s.sessionId).first.title}\n${s.goal}\n${s.expectation}').join('\n↓\n')}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('发起协作')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final input = draft.toJson('')..remove('idempotency_key');
    final result = await person.operation.perform(
      'flow',
      input,
      (body) async => (await person.api.applyPersonFlow(body)).json,
    );
    if (!mounted) return;
    if (result != null) {
      await person.refreshSnapshot();
      if (mounted) Navigator.pop(context);
    } else {
      setState(() => error = person.operation.error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('发起协作'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PersonOperationNotice(person: widget.person),
          if (loading) const LinearProgressIndicator(),
          TextField(
            controller: title,
            decoration: InputDecoration(labelText: context.tr('协作标题')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: goal,
            decoration: InputDecoration(labelText: context.tr('总体目标')),
            minLines: 2,
            maxLines: 5,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: rounds,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.tr('轮次（1–1000）')),
          ),
          const SizedBox(height: 12),
          for (final (index, stage) in stages.indexed)
            Card(
              key: ValueKey(stage),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: stage.bot.isEmpty ? null : stage.bot,
                      items: [
                        for (final bot in bots)
                          DropdownMenuItem(
                            value: bot.id,
                            child: Text(bot.title),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => stage.bot = value ?? ''),
                      decoration: InputDecoration(
                        labelText: context.tr('选择既有 BOT'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: stage.goal,
                      decoration: InputDecoration(
                        labelText: context.tr('阶段目标'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: stage.expectation,
                      decoration: InputDecoration(
                        labelText: context.tr('返回期望'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(context.tr('并行分组（从 1 连续）')),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<int>(
                            value: stage.group.clamp(0, 12),
                            items: [
                              for (var group = 0; group <= 12; group++)
                                DropdownMenuItem(
                                  value: group,
                                  child: Text('${group + 1}'),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => stage.group = value ?? 0),
                          ),
                        ),
                        if (stages.length > 1)
                          IconButton(
                            tooltip: context.tr('移除阶段'),
                            onPressed: () {
                              setState(() => stages.removeAt(index));
                              stage.dispose();
                            },
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (stages.length < 13)
            TextButton(
              onPressed: () => setState(
                () => stages.add(
                  _FlowStageFields()
                    ..group = math.min(stages.last.group + 1, 12),
                ),
              ),
              child: Text(context.tr('添加阶段')),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                context.tr(error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed:
                loading ||
                    widget.person.operation.pending ||
                    widget.person.operation.uncertain
                ? null
                : submit,
            child: Text(context.tr('预览并确认')),
          ),
        ],
      ),
    ),
  );
}
