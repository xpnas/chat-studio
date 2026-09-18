import '../../l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../data/models.dart';
import '../../data/server_workspace.dart';
import '../../data/studio_api.dart';
import '../../state/app_controller.dart';

/// Browses files on the connected Agent server, not on this phone.
class WorkspaceDrawer extends StatelessWidget {
  const WorkspaceDrawer({super.key, required this.controller});
  final AppController controller;

  Future<void> _choose(BuildContext context) async {
    final c = controller, client = controller.api;
    if (client == null || !c.canChooseWorkspace) return;
    final navigation = c.chatRevision, id = c.sessionId, profile = c.profile;
    final fullPath = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ServerFolderPicker(api: client),
    );
    if (fullPath == null ||
        !context.mounted ||
        c.api != client ||
        c.chatRevision != navigation ||
        c.sessionId != id ||
        c.profile != profile) {
      return;
    }
    await c.chooseWorkspace(fullPath);
  }

  Future<void> _previewFile(
    BuildContext context,
    Map<String, dynamic> file,
  ) async {
    final id = controller.sessionId, api = controller.api;
    final path = text(file['path']);
    if (id == null || api == null || path.isEmpty) return;
    final name = text(file['name']);
    final mime = text(file['mime']).isNotEmpty
        ? text(file['mime'])
        : text(file['mimeType']);
    final image = _isImage(name, mime);
    final textFile = _isText(name, mime);
    if (!image && !textFile) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('暂不支持预览此文件类型'))));
      return;
    }
    try {
      final data = await api.readWorkspaceFile(id, path);
      if (!context.mounted) return;
      final content = text(data['content']).isNotEmpty
          ? text(data['content'])
          : text(data['text']);
      if (image) {
        final bytes = _decodeBytes(data);
        if (bytes == null) throw StateError(context.tr('图片内容读取失败'));
        await showDialog<void>(
          context: context,
          useSafeArea: false,
          builder: (_) => Dialog.fullscreen(
            child: _ImageFilePreview(title: name, bytes: bytes),
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          useSafeArea: false,
          builder: (_) => Dialog.fullscreen(
            child: _TextFileEditor(
              title: name,
              initialValue: content,
              onSave: (value) => api.writeWorkspaceFile(id, path, value),
            ),
          ),
        );
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  bool _isImage(String name, String mime) =>
      mime.startsWith('image/') ||
      RegExp(
        r'\.(png|jpe?g|gif|webp|bmp)$',
        caseSensitive: false,
      ).hasMatch(name);
  bool _isText(String name, String mime) =>
      mime.startsWith('text/') ||
      const {
        'application/json',
        'application/xml',
        'application/yaml',
      }.contains(mime) ||
      RegExp(
        r'\.(txt|md|json|yaml|yml|xml|csv|log|dart|py|js|ts|html|css|sh|sql|toml|ini|conf)$',
        caseSensitive: false,
      ).hasMatch(name);

  Uint8List? _decodeBytes(Map<String, dynamic> data) {
    final value = text(data['base64']).isNotEmpty
        ? text(data['base64'])
        : text(data['content']);
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller, colors = Theme.of(context).colorScheme;
    return Drawer(
      key: const Key('server-workspace-drawer'),
      width: MediaQuery.sizeOf(context).width,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(
                children: [
                  const Icon(Icons.dns_outlined, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr("服务器工作区"),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr("刷新服务器文件"),
                    onPressed:
                        c.sessionId == null ||
                            c.workspaceLoading ||
                            c.workspaceSaving
                        ? null
                        : () => c.refreshWorkspaceFiles(),
                    icon: const Icon(Icons.refresh_rounded, size: 21),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                c.api?.address.uri.host ?? '',
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: SelectableText(
                c.workspacePath.isEmpty
                    ? context.tr("尚未获取服务器工作路径")
                    : c.workspacePath,
                key: const Key('server-workspace-path'),
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            if (c.sessionId == null)
              Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  context.tr("发送首条消息后，可查看和选择此对话在服务器上的工作目录。"),
                  style: TextStyle(fontSize: 12),
                ),
              ),
            if (c.workspaceLoading || c.workspaceSaving)
              const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.tonalIcon(
                key: const Key('choose-server-workspace'),
                onPressed: c.canChooseWorkspace ? () => _choose(context) : null,
                icon: const Icon(Icons.folder_open_rounded, size: 20),
                label: Text(
                  c.workspaceSaving
                      ? context.tr("正在保存…")
                      : context.tr("选择服务器文件夹"),
                ),
              ),
            ),
            if (c.working)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  context.tr("任务执行期间不能切换工作目录"),
                  style: TextStyle(fontSize: 11),
                ),
              ),
            if (c.workspaceError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  c.workspaceError!,
                  key: const Key('server-workspace-error'),
                  style: TextStyle(fontSize: 12, color: colors.error),
                ),
              ),
            const Divider(height: 18),
            if (c.workspaceRelativePath.isNotEmpty)
              TextButton.icon(
                onPressed: c.workspaceLoading || c.workspaceSaving
                    ? null
                    : () => c.refreshWorkspaceFiles(path: ''),
                icon: const Icon(Icons.home_outlined, size: 18),
                label: Text(context.tr("返回工作区根目录")),
              ),
            Expanded(
              child: c.workspaceFiles.isEmpty
                  ? Center(
                      child: Text(
                        c.workspaceLoading
                            ? context.tr("正在读取服务器文件…")
                            : c.workspaceError == null
                            ? context.tr("暂无文件")
                            : context.tr("读取失败，可刷新或重新选择目录"),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: const Key('server-workspace-files'),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: c.workspaceFiles.length,
                      itemBuilder: (_, i) {
                        final f = c.workspaceFiles[i],
                            dir = c.workspaceFiles[i]['isDir'] == true;
                        return ListTile(
                          key: ValueKey('workspace-file:${f['path']}'),
                          dense: true,
                          leading: Icon(
                            dir
                                ? Icons.folder_outlined
                                : Icons.insert_drive_file_outlined,
                            size: 20,
                          ),
                          title: Text(
                            text(f['name']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            text(f['path']),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: c.workspaceLoading || c.workspaceSaving
                              ? null
                              : dir
                              ? () => c.refreshWorkspaceFiles(
                                  path: text(f['path']),
                                )
                              : () => _previewFile(context, f),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageFilePreview extends StatelessWidget {
  const _ImageFilePreview({required this.title, required this.bytes});
  final String title;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: IconButton(
        tooltip: context.tr('关闭'),
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded),
      ),
    ),
    body: ColoredBox(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: .25),
      child: Center(
        child: InteractiveViewer(
          minScale: .5,
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    ),
  );
}

class _TextFileEditor extends StatefulWidget {
  const _TextFileEditor({
    required this.title,
    required this.initialValue,
    required this.onSave,
  });
  final String title, initialValue;
  final Future<void> Function(String value) onSave;
  @override
  State<_TextFileEditor> createState() => _TextFileEditorState();
}

class _TextFileEditorState extends State<_TextFileEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  bool _saving = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _controller.text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr('已复制'))));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_controller.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      leading: IconButton(
        tooltip: context.tr('关闭'),
        onPressed: _saving ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded),
      ),
      actions: [
        IconButton(
          tooltip: context.tr('复制'),
          onPressed: _saving ? null : _copy,
          icon: const Icon(Icons.copy_outlined),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilledButton.tonalIcon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(context.tr('保存')),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: TextField(
          controller: _controller,
          expands: true,
          maxLines: null,
          minLines: null,
          textAlignVertical: TextAlignVertical.top,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            height: 1.5,
          ),
          decoration: InputDecoration(
            hintText: context.tr('请输入文本'),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ),
    ),
  );
}

class ServerFolderPicker extends StatefulWidget {
  const ServerFolderPicker({super.key, required this.api});
  final StudioApi api;
  @override
  State<ServerFolderPicker> createState() => _ServerFolderPickerState();
}

class _ServerFolderPickerState extends State<ServerFolderPicker> {
  List<Map<String, dynamic>> _folders = const [];
  final _parents = <(String, String)>[];
  String _path = '', _fullPath = '';
  String? _error;
  bool _loading = true;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    _load('', '');
  }

  Future<void> _load(
    String path,
    String fullPath, {
    bool enter = false,
    bool back = false,
  }) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.workspaceFolders(path: path);
      if (!mounted || request != _request) return;
      setState(() {
        if (enter) _parents.add((_path, _fullPath));
        if (back && _parents.isNotEmpty) _parents.removeLast();
        _path = path;
        _fullPath = fullPath.isNotEmpty ? fullPath : text(data['base']);
        _folders = asList(data['folders']).map(asMap).toList();
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = serverWorkspaceError(e);
        });
      }
    } finally {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              context.tr("选择服务器文件夹"),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: Text(
              context.tr("目录来自当前 Agent 服务器，不是手机存储"),
              style: TextStyle(fontSize: 11),
            ),
          ),
          if (_fullPath.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _fullPath,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          Row(
            children: [
              TextButton.icon(
                onPressed: _loading || _parents.isEmpty
                    ? null
                    : () =>
                          _load(_parents.last.$1, _parents.last.$2, back: true),
                icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                label: Text(context.tr("上一级")),
              ),
              const Spacer(),
              TextButton(
                onPressed:
                    _loading ||
                        _error != null ||
                        !isAbsoluteServerPath(_fullPath)
                    ? null
                    : () => Navigator.pop(context, _fullPath),
                child: Text(context.tr("使用此目录")),
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          if (_error != null)
            TextButton(
              onPressed: _loading ? null : () => _load(_path, _fullPath),
              child: Text(context.tr("重试目录读取")),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _folders.length,
              itemBuilder: (_, i) {
                final f = _folders[i], fullPath = text(_folders[i]['fullPath']);
                final valid =
                    !_loading &&
                    _error == null &&
                    isAbsoluteServerPath(fullPath);
                return ListTile(
                  key: ValueKey('server-folder:${f['path']}'),
                  dense: true,
                  leading: const Icon(Icons.folder_outlined, size: 22),
                  title: Text(
                    text(f['name']),
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    fullPath.isEmpty ? context.tr("服务器未提供绝对路径，不能选择") : fullPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: !valid
                      ? null
                      : () => _load(text(f['path']), fullPath, enter: true),
                  trailing: IconButton(
                    tooltip: context.l10n.format("使用 {0}", {
                      '0': text(f['name']),
                    }),
                    onPressed: !valid
                        ? null
                        : () => Navigator.pop(context, fullPath),
                    icon: const Icon(Icons.check_rounded, size: 20),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
