import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models.dart';
import '../../data/slash_commands.dart';
import '../../state/app_controller.dart';

/// A bounded, scrollable completion panel: selection fills a draft, never runs it.
class SlashCommandPicker extends StatefulWidget {
  const SlashCommandPicker({
    super.key,
    required this.controller,
    required this.input,
    required this.focus,
    required this.enabled,
    required this.child,
  });
  final AppController controller;
  final TextEditingController input;
  final FocusNode focus;
  final bool enabled;
  final Widget child;
  @override
  State<SlashCommandPicker> createState() => _SlashCommandPickerState();
}

class _SlashCommandPickerState extends State<SlashCommandPicker> {
  bool dismissed = false;
  int selected = 0;
  final scroll = ScrollController();
  final portal = OverlayPortalController();
  List<SlashCommand> get matches {
    final value = widget.input.value;
    if (!widget.enabled ||
        dismissed ||
        !widget.focus.hasFocus ||
        !value.selection.isCollapsed ||
        value.selection.baseOffset < 1 ||
        (value.composing.isValid && !value.composing.isCollapsed)) {
      return [];
    }
    if (!value.text.startsWith('/') ||
        value.selection.baseOffset > value.text.length) {
      return [];
    }
    final prefix = value.text.substring(0, value.selection.baseOffset);
    if (!prefix.startsWith('/') ||
        prefix.contains(' ') ||
        prefix.contains('\n')) {
      return [];
    }
    final query = prefix.substring(1).trim().toLowerCase();
    return commandsForEngine(widget.controller.engine)
        .where(
          (c) =>
              c.name.startsWith(query) ||
              c.insert.startsWith(query) ||
              c.description.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    widget.input.addListener(_changed);
    widget.focus.addListener(_focusChanged);
    widget.focus.onKeyEvent = _key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) portal.show();
    });
  }

  void _changed() {
    if (mounted) {
      setState(() {
        dismissed = false;
        selected = 0;
      });
    }
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    final rows = matches;
    if (event is! KeyDownEvent || rows.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => dismissed = true);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => selected =
            (selected +
                (event.logicalKey == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
            rows.length,
      );
      if (scroll.hasClients) {
        scroll.jumpTo(
          (selected * 64.0).clamp(0.0, scroll.position.maxScrollExtent),
        );
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      _select(rows[selected.clamp(0, rows.length - 1)]);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    widget.input.removeListener(_changed);
    widget.focus.removeListener(_focusChanged);
    widget.focus.onKeyEvent = null;
    scroll.dispose();
    super.dispose();
  }

  void _insert(String command) {
    widget.input.value = TextEditingValue(
      text: '/$command ',
      selection: TextSelection.collapsed(offset: command.length + 2),
    );
    setState(() => dismissed = true);
    widget.focus.requestFocus();
  }

  Future<void> _select(SlashCommand command) async {
    setState(() => dismissed = true);
    final c = widget.controller, draft = widget.controller.draft;
    if (command.name == 'skill' || command.name == 'bundles') {
      final client = c.api;
      if (client == null) return;
      final result = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => CommandResourceSheet(
          controller: c,
          bundles: command.name == 'bundles',
          create: command.insert == 'bundles create',
        ),
      );
      if (mounted && identical(draft, c.draft) && result != null) {
        _insert(result);
      }
      return;
    }
    _insert(command.insert);
  }

  @override
  Widget build(BuildContext context) => OverlayPortal.overlayChildLayoutBuilder(
    controller: portal,
    child: widget.child,
    overlayChildBuilder: (context, info) {
      final origin = MatrixUtils.transformPoint(
        info.childPaintTransform,
        Offset.zero,
      );
      final available = (origin.dy - MediaQuery.paddingOf(context).top - 8)
          .clamp(0.0, 224.0);
      final rows = matches;
      if (rows.isEmpty || available < 48) return const SizedBox.shrink();
      final height = (rows.length * 64.0).clamp(0.0, available);
      return Positioned(
        left: origin.dx,
        top: origin.dy - height - 6,
        width: info.childSize.width,
        height: height,
        child: TextFieldTapRegion(child: _panel(context, rows)),
      );
    },
  );

  Widget _panel(BuildContext context, List<SlashCommand> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      key: const Key('slash-commands'),
      height: (rows.length * 64.0).clamp(
        0.0,
        (MediaQuery.sizeOf(context).height * .24).clamp(64.0, 224.0),
      ),
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListView.builder(
          controller: scroll,
          itemExtent: 64,
          itemCount: rows.length,
          itemBuilder: (context, i) => ListTile(
            key: ValueKey('command:${rows[i].insert}'),
            selected: i == selected,
            title: Text(
              '/${rows[i].insert} ${rows[i].args}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              rows[i].description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () => _select(rows[i]),
          ),
        ),
      ),
    );
  }
}

/// Same profile-scoped skills/bundles as the Web pickers. Creation uses REST,
/// not a '/bundles create' prompt (which the official server rejects).
class CommandResourceSheet extends StatefulWidget {
  const CommandResourceSheet({
    super.key,
    required this.controller,
    required this.bundles,
    this.create = false,
  });
  final AppController controller;
  final bool bundles, create;
  @override
  State<CommandResourceSheet> createState() => _CommandResourceSheetState();
}

class _CommandResourceSheetState extends State<CommandResourceSheet> {
  late final client = widget.controller.api!;
  late final draft = widget.controller.draft;
  late final profile = client.profile;
  final name = TextEditingController(), description = TextEditingController();
  final chosen = <String>{};
  List<Map<String, dynamic>> rows = [];
  String query = '';
  String? error;
  bool loading = true, saving = false;
  bool get valid =>
      mounted &&
      client == widget.controller.api &&
      profile == client.profile &&
      identical(draft, widget.controller.draft);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = widget.bundles && !widget.create
          ? await client.commandBundles()
          : await client.commandSkills();
      if (valid) setState(() => rows = data);
    } catch (e) {
      if (valid) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _create() async {
    if (!valid || saving || name.text.trim().isEmpty || chosen.isEmpty) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final bundle = await client.createCommandBundle(
        name.text.trim(),
        description.text.trim(),
        chosen.toList(),
      );
      if (mounted && valid) {
        Navigator.pop(context, 'bundles ${text(bundle['commandName'])}');
      }
    } catch (e) {
      if (valid) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = rows
        .where(
          (r) =>
              '${r['name']} ${r['description']} ${r['commandName']} ${r['skills']}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Text(
              widget.create
                  ? '创建 Skill Bundle'
                  : widget.bundles
                  ? 'Skill Bundles'
                  : '选择技能',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            if (widget.create) ...[
              TextField(
                controller: name,
                maxLength: 120,
                enabled: !saving,
                decoration: const InputDecoration(labelText: 'Bundle 名称'),
              ),
              TextField(
                controller: description,
                enabled: !saving,
                decoration: const InputDecoration(labelText: '描述（可选）'),
              ),
            ],
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索名称或描述',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (error != null)
              TextButton(
                onPressed: saving ? null : _load,
                child: const Text('重试'),
              ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? const Center(child: Text('没有可用或匹配的项目'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final row = filtered[i],
                            label = text(filtered[i]['name']);
                        final command = widget.bundles && !widget.create
                            ? text(row['commandName'])
                            : skillCommandName(label);
                        return ListTile(
                          title: Text(label),
                          subtitle: Text(
                            text(row['description']),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: widget.create
                              ? Checkbox(
                                  value: chosen.contains(label),
                                  onChanged: saving
                                      ? null
                                      : (_) => setState(() {
                                          if (!chosen.add(label)) {
                                            chosen.remove(label);
                                          }
                                        }),
                                )
                              : null,
                          onTap: !valid || saving
                              ? null
                              : () {
                                  if (widget.create) {
                                    setState(() {
                                      if (!chosen.add(label)) {
                                        chosen.remove(label);
                                      }
                                    });
                                  } else {
                                    Navigator.pop(
                                      context,
                                      '${widget.bundles ? 'bundles' : 'skill'} $command',
                                    );
                                  }
                                },
                        );
                      },
                    ),
            ),
            if (widget.create)
              FilledButton(
                onPressed: saving || loading ? null : _create,
                child: Text(saving ? '创建中…' : '创建并填入输入框'),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
