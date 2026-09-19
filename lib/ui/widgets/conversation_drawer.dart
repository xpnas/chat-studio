import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import '../../state/conversation_state.dart';
import '../profile_screen.dart';
import '../theme.dart';
import 'agent_avatar.dart';
import 'conversation_activity_mark.dart';
import 'history_browser.dart';

class ConversationDrawer extends StatefulWidget {
  const ConversationDrawer({
    super.key,
    required this.controller,
    required this.onNewChat,
    required this.onOpenConversation,
    required this.onOpenGroup,
    this.initialTab = 0,
  });
  final AppController controller;
  final VoidCallback onNewChat;
  final ValueChanged<Conversation> onOpenConversation;
  final ValueChanged<GroupRoom> onOpenGroup;
  final int initialTab;
  @override
  State<ConversationDrawer> createState() => _ConversationDrawerState();
}

class _ConversationDrawerState extends State<ConversationDrawer> {
  final _search = TextEditingController();
  Timer? _searchTimer;
  String _historyFilter = 'all', _historyCategory = '';
  late int _historyTab;
  bool get _includeArchived => _historyFilter == 'archived';
  List<GroupRoom> _groupRooms = const [];
  bool _loadingGroupRooms = false;
  String? _groupRoomsError;
  AppController get c => widget.controller;
  Object? _api;
  String _profile = '';
  int _scope = 0;
  @override
  void initState() {
    super.initState();
    _historyTab = widget.initialTab;
    _api = c.api;
    _profile = c.profile;
    c.addListener(_changed);
    if (_historyTab == 1) unawaited(_loadGroupRooms());
  }

  void _changed() {
    if (!mounted) return;
    if (_api != c.api || _profile != c.profile) {
      _scope++;
      _api = c.api;
      _profile = c.profile;
      _searchTimer?.cancel();
      _search.clear();
      _groupRooms = const [];
      _loadingGroupRooms = false;
      _groupRoomsError = null;
      if (_historyTab == 1) unawaited(_loadGroupRooms());
    }
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    _searchTimer?.cancel();
    _search.dispose();
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

  Future<void> _loadGroupRooms() async {
    if (_loadingGroupRooms || c.api == null) return;
    final scope = _scope;
    setState(() {
      _loadingGroupRooms = true;
      _groupRoomsError = null;
    });
    try {
      final rooms = await c.api!.groupRooms();
      if (mounted && scope == _scope) setState(() => _groupRooms = rooms);
    } catch (e) {
      if (mounted && scope == _scope) setState(() => _groupRoomsError = '$e');
    } finally {
      if (mounted && scope == _scope) {
        setState(() => _loadingGroupRooms = false);
      }
    }
  }

  Widget _groupRoomsView(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_loadingGroupRooms && _groupRooms.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_groupRoomsError != null && _groupRooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_groupRoomsError!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadGroupRooms,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_groupRooms.isEmpty) {
      return Center(
        child: Text(
          '暂无群聊\n群聊配置请在 Web 端完成',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant, height: 1.7),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadGroupRooms,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        itemCount: _groupRooms.length,
        itemBuilder: (context, index) {
          final room = _groupRooms[index];
          return ListTile(
            key: ValueKey('group-room:${room.id}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 3,
            ),
            leading: SizedBox(
              width: 58,
              height: 36,
              child: Stack(
                children: [
                  for (var i = 0; i < room.agents.length && i < 3; i++)
                    Positioned(
                      left: i * 17,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: AgentAvatar(
                          controller: c,
                          agentId: room.agents[i].agent,
                          size: 29,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            title: Text(
              room.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              room.agents.isEmpty
                  ? '群聊'
                  : '${room.agents.length} 个 Agent · 仅支持聊天',
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.pop(context);
              widget.onOpenGroup(room);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final visible = c.conversations.where((conversation) {
      final archived = c.isConversationArchived(conversation);
      final category = c.conversationCategory(conversation);
      if (_historyTab == 0 && conversation.source == 'group_chat') return false;
      return switch (_historyFilter) {
        'pinned' =>
          c.isConversationPinned(conversation) &&
              (_historyTab == 2 || !archived),
        'archived' => archived,
        'category' =>
          category == _historyCategory && (_historyTab == 2 || !archived),
        _ => _historyTab == 2 || !archived,
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
                        letterSpacing: 0,
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
                          Navigator.pop(context);
                          widget.onNewChat();
                        },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.tr('新建对话')),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_historyTab == 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _search,
                  enabled: _historyTab != 1,
                  decoration: InputDecoration(
                    hintText: _historyTab == 1
                        ? '群聊列表不支持搜索'
                        : context.tr('搜索全部对话'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    _searchTimer?.cancel();
                    _searchTimer = Timer(
                      const Duration(milliseconds: 350),
                      () => c.refreshSessions(
                        query: value,
                        includeArchived: _includeArchived,
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DefaultTabController(
                length: 3,
                initialIndex: _historyTab,
                child: TabBar(
                  onTap: (value) {
                    if (_historyTab == value) return;
                    _searchTimer?.cancel();
                    setState(() => _historyTab = value);
                    if (value == 1) {
                      unawaited(_loadGroupRooms());
                    } else if (value == 0) {
                      unawaited(
                        c.refreshSessions(
                          query: _search.text,
                          includeArchived: _includeArchived,
                        ),
                      );
                    }
                  },
                  tabs: const [
                    Tab(text: '单聊'),
                    Tab(text: '群聊'),
                    Tab(text: '历史'),
                  ],
                ),
              ),
            ),
            if (_historyTab != 2)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _historyTab == 1
                            ? '群聊'
                            : _historyTab == 2
                            ? '全部历史'
                            : context.tr('对话记录'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (_historyTab != 1)
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
                              includeArchived: _includeArchived,
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
                    if (_historyTab != 1)
                      IconButton(
                        tooltip: context.tr('刷新记录'),
                        onPressed: c.loadingSessions
                            ? null
                            : () => c.refreshSessions(
                                includeArchived: _includeArchived,
                              ),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                      )
                    else
                      IconButton(
                        tooltip: '刷新群聊',
                        onPressed: _loadingGroupRooms ? null : _loadGroupRooms,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                      ),
                  ],
                ),
              ),
            if (_historyTab == 0 && _historyFilter == 'category')
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
            if (_historyTab == 0 && c.loadingSessions)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _historyTab == 2 && c.api != null
                  ? HistoryBrowser(
                      key: ValueKey((_api, _profile)),
                      controller: c,
                    )
                  : _historyTab == 1
                  ? _groupRoomsView(context)
                  : visible.isEmpty
                  ? RefreshIndicator(
                      onRefresh: () =>
                          c.refreshSessions(includeArchived: _includeArchived),
                      child: LayoutBuilder(
                        builder: (context, constraints) => ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: constraints.maxHeight,
                              child: Center(
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
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          c.refreshSessions(includeArchived: _includeArchived),
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
                        itemCount: visible.length + (c.hasMoreSessions ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == visible.length) {
                            return TextButton(
                              onPressed: c.loadingSessions
                                  ? null
                                  : () => c.refreshSessions(
                                      more: true,
                                      includeArchived: _includeArchived,
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
                                    widget.onOpenConversation(conversation);
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
