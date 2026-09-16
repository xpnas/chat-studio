import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final c = controller, colors = Theme.of(context).colorScheme;
    return Drawer(
      key: const Key('server-workspace-drawer'),
      width: 340,
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
                  const Expanded(
                    child: Text(
                      '服务器工作区',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新服务器文件',
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
                c.workspacePath.isEmpty ? '尚未获取服务器工作路径' : c.workspacePath,
                key: const Key('server-workspace-path'),
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
            if (c.sessionId == null)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  '发送首条消息后，可查看和选择此对话在服务器上的工作目录。',
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
                label: Text(c.workspaceSaving ? '正在保存…' : '选择服务器文件夹'),
              ),
            ),
            if (c.working)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('任务执行期间不能切换工作目录', style: TextStyle(fontSize: 11)),
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
                label: const Text('返回工作区根目录'),
              ),
            Expanded(
              child: c.workspaceFiles.isEmpty
                  ? Center(
                      child: Text(
                        c.workspaceLoading
                            ? '正在读取服务器文件…'
                            : c.workspaceError == null
                            ? '暂无文件'
                            : '读取失败，可刷新或重新选择目录',
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
                          onTap: !dir || c.workspaceLoading || c.workspaceSaving
                              ? null
                              : () => c.refreshWorkspaceFiles(
                                  path: text(f['path']),
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
}

/// `path` is an API navigation token, `fullPath` is the selected server path.
/// In particular Linux returns relative `path` and absolute `fullPath`.
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '选择服务器文件夹',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: Text(
              '目录来自当前 Agent 服务器，不是手机存储',
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
                label: const Text('上一级'),
              ),
              const Spacer(),
              TextButton(
                onPressed:
                    _loading ||
                        _error != null ||
                        !isAbsoluteServerPath(_fullPath)
                    ? null
                    : () => Navigator.pop(context, _fullPath),
                child: const Text('使用此目录'),
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
              child: const Text('重试目录读取'),
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
                    fullPath.isEmpty ? '服务器未提供绝对路径，不能选择' : fullPath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: !valid
                      ? null
                      : () => _load(text(f['path']), fullPath, enter: true),
                  trailing: IconButton(
                    tooltip: '使用 ${text(f['name'])}',
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
