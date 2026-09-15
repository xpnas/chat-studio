import 'package:flutter/material.dart';
import '../data/models.dart';
import '../state/app_controller.dart';
import 'theme.dart';

class ServerScreen extends StatelessWidget {
  const ServerScreen({super.key, required this.controller});
  final AppController controller;
  void _root(BuildContext context) =>
      Navigator.of(context).popUntil((r) => r.isFirst);
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      return Scaffold(
        appBar: AppBar(title: const Text('服务器')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (c.error != null)
              ErrorNotice(message: c.error!, onDismiss: c.dismissError),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '登录记录仅保存在本机安全存储中，不保存密码。切换不会停止服务端任务，但会清空本机未发送的草稿。',
                style: TextStyle(fontSize: 13),
              ),
            ),
            for (final record in c.servers)
              Card(
                child: ListTile(
                  leading: Icon(
                    c.authenticated && c.api?.address.value == record['server']
                        ? Icons.check_circle_outline
                        : Icons.dns_outlined,
                  ),
                  title: Text(
                    text(record['server']),
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '${text(record['profile']).isEmpty ? 'default' : record['profile']} · ${text(record['token']).isEmpty ? '需要登录' : '已保存登录'}',
                  ),
                  onTap: c.busy
                      ? null
                      : () {
                          _root(context);
                          c.switchServer(text(record['server']));
                        },
                  trailing:
                      c.authenticated &&
                          c.api?.address.value == record['server']
                      ? const Text('当前', style: TextStyle(fontSize: 12))
                      : IconButton(
                          tooltip: '删除记录',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: c.busy
                              ? null
                              : () async {
                                  final remove = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('删除服务器记录？'),
                                      content: Text(text(record['server'])),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('取消'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (remove == true) {
                                    await c.removeServer(
                                      text(record['server']),
                                    );
                                  }
                                },
                        ),
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加服务器'),
              onPressed: c.busy
                  ? null
                  : () {
                      _root(context);
                      c.addServer();
                    },
            ),
          ],
        ),
      );
    },
  );
}
