import 'package:flutter/material.dart';
import '../state/app_controller.dart';
import 'theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.controller});
  final AppController controller;
  Future<void> _credentials(BuildContext context, bool username) async {
    final old = TextEditingController(), replacement = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(username ? '修改用户名' : '修改密码'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('更新成功后需要重新登录。', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 18),
              TextFormField(
                controller: old,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: '当前密码'),
                validator: (v) => v?.isEmpty != false ? '请输入当前密码' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: replacement,
                obscureText: !username,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: username ? '新用户名' : '新密码（至少 8 位）',
                ),
                validator: (v) =>
                    v == null || (username ? v.trim().isEmpty : v.length < 8)
                    ? '请输入有效的新凭据'
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('确认更新'),
          ),
        ],
      ),
    );
    if (result == true) {
      await controller.updateCredentials(
        old.text,
        replacement.text,
        username: username,
      );
    }
    // Dispose after the dialog's reverse transition.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    old.dispose();
    replacement.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller,
          user = c.account,
          colors = Theme.of(context).colorScheme;
      if (user == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('个人信息')),
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: const Text('返回登录'),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('个人信息')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 18),
                CircleAvatar(
                  radius: 36,
                  backgroundColor: colors.primaryContainer,
                  child: Text(
                    user.username.characters.firstOrNull?.toUpperCase() ?? 'E',
                    style: TextStyle(
                      fontSize: 28,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Text(
                    user.username,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    user.role == 'super_admin' ? '超级管理员' : '管理员',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 28),
                if (c.error != null)
                  ErrorNotice(message: c.error!, onDismiss: c.dismissError),
                if (user.requiresCredentialChange)
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colors.errorContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text('当前账号仍使用服务端默认凭据。请尽快修改用户名和密码。'),
                  ),
                _section(context, '连接', [
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('服务地址'),
                    subtitle: SelectableText(c.api?.address.value ?? ''),
                    isThreeLine: false,
                  ),
                  ListTile(
                    leading: const Icon(Icons.layers_outlined),
                    title: const Text('当前 Profile'),
                    subtitle: Text(c.profile),
                  ),
                  ListTile(
                    leading: const Icon(Icons.sync_rounded),
                    title: const Text('同步模型与配置'),
                    subtitle: const Text('模型与密钥统一在 Studio 服务端管理'),
                    onTap: c.busy || c.working ? null : c.refreshWorkspace,
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                ]),
                const SizedBox(height: 20),
                _section(context, '偏好', [
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: const Text('外观'),
                    trailing: DropdownButton<String>(
                      value: c.theme,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                        DropdownMenuItem(value: 'light', child: Text('浅色')),
                        DropdownMenuItem(value: 'dark', child: Text('深色')),
                      ],
                      onChanged: (v) {
                        if (v != null) c.setTheme(v);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                _section(context, '账号与隐私', [
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: const Text('修改用户名'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: c.busy ? null : () => _credentials(context, true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: const Text('修改密码'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: c.busy ? null : () => _credentials(context, false),
                  ),
                  const ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text('数据仅发送到你的服务器'),
                    subtitle: Text(
                      '不含广告或分析 SDK。不保存密码，聊天记录由服务端管理。退出仅清除本机凭据；可在 Studio 撤销设备授权。',
                    ),
                  ),
                ]),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('开源许可'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Ekko Mobile',
                    applicationVersion: '1.0.5',
                  ),
                ),
                const SizedBox(height: 26),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('退出登录？'),
                        content: const Text(
                          '将清除本机登录凭据和内存中的聊天内容。服务端历史与正在执行的任务不会被删除或停止。',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('退出登录'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await c.logout();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    }
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('退出登录'),
                ),
                const SizedBox(height: 30),
                Center(
                  child: Text(
                    'EKKO MOBILE  1.0.5\n适配 Studio v1.0.5',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.8,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: children),
          ),
        ],
      );
}
