import '../l10n.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'server_screen.dart';
import 'widgets/language_picker.dart';
import 'management_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppController get controller => widget.controller;
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();
  Future<void> _credentials(BuildContext context, bool username) async {
    final old = TextEditingController(), replacement = TextEditingController();
    final form = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(username ? context.tr("修改用户名") : context.tr("修改密码")),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr("更新成功后需要重新登录。"), style: TextStyle(fontSize: 13)),
              const SizedBox(height: 18),
              TextFormField(
                controller: old,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(labelText: context.tr("当前密码")),
                validator: (v) =>
                    v?.isEmpty != false ? context.tr("请输入当前密码") : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: replacement,
                obscureText: !username,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: username
                      ? context.tr("新用户名")
                      : context.tr("新密码（至少 8 位）"),
                ),
                validator: (v) =>
                    v == null || (username ? v.trim().isEmpty : v.length < 8)
                    ? context.tr("请输入有效的新凭据")
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr("取消")),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: Text(context.tr("确认更新")),
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
          appBar: AppBar(title: Text(context.tr("个人信息"))),
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: Text(context.tr("返回登录")),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: Text(context.tr("个人信息"))),
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
                    user.role == 'super_admin'
                        ? context.tr("超级管理员")
                        : context.tr("管理员"),
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
                    child: Text(context.tr("当前账号仍使用服务端默认凭据。请尽快修改用户名和密码。")),
                  ),
                _section(context, context.tr("连接"), [
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: Text(context.tr("服务器管理与切换")),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: c.busy
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ServerScreen(controller: c),
                            ),
                          ),
                    subtitle: SelectableText(c.api?.address.value ?? ''),
                    isThreeLine: false,
                  ),
                  ListTile(
                    leading: const Icon(Icons.layers_outlined),
                    title: Text(context.tr("当前 Profile")),
                    subtitle: Text(c.profile),
                  ),
                  ListTile(
                    leading: const Icon(Icons.sync_rounded),
                    title: Text(context.tr("同步模型与配置")),
                    subtitle: Text(context.tr("模型与密钥统一在 Studio 服务端管理")),
                    onTap: c.busy || c.working ? null : c.refreshWorkspace,
                    trailing: const Icon(Icons.chevron_right_rounded),
                  ),
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: Text(context.tr("服务管理")),
                    subtitle: Text(context.tr("Agent、模型、日志与服务配置")),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ManagementScreen(controller: c),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                _section(context, context.tr("偏好"), [
                  ListTile(
                    leading: const Icon(Icons.language_rounded),
                    title: Text(context.tr('语言')),
                    trailing: LanguagePicker(controller: c),
                  ),
                  ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: Text(context.tr("外观")),
                    trailing: DropdownButton<String>(
                      value: c.theme,
                      underline: const SizedBox.shrink(),
                      items: [
                        DropdownMenuItem(
                          value: 'system',
                          child: Text(context.tr("跟随系统")),
                        ),
                        DropdownMenuItem(
                          value: 'light',
                          child: Text(context.tr("浅色")),
                        ),
                        DropdownMenuItem(
                          value: 'dark',
                          child: Text(context.tr("深色")),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) c.setTheme(v);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                _section(context, context.tr("账号与隐私"), [
                  ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(context.tr("修改用户名")),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: c.busy ? null : () => _credentials(context, true),
                  ),
                  ListTile(
                    leading: const Icon(Icons.lock_outline_rounded),
                    title: Text(context.tr("修改密码")),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: c.busy ? null : () => _credentials(context, false),
                  ),
                  ListTile(
                    leading: Icon(Icons.shield_outlined),
                    title: Text(context.tr("数据仅发送到你的服务器")),
                    subtitle: Text(
                      context.tr(
                        "不含广告或分析 SDK。不保存密码，聊天记录由服务端管理。退出仅清除本机凭据；可在 Studio 撤销设备授权。",
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                _section(context, context.tr("关于"), [
                  _aboutTile(context),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: Text(context.tr("开源许可")),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final info = await _packageInfo;
                      if (!context.mounted) return;
                      showLicensePage(
                        context: context,
                        applicationName: info.appName.isEmpty
                            ? 'Chat Studio'
                            : info.appName,
                        applicationVersion: _versionLabel(info),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 26),
                OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(context.tr("退出登录？")),
                        content: Text(
                          context.tr(
                            "将清除当前服务器的本机登录凭据和聊天内存，保留其他服务器登录。服务端历史和任务不会被删除或停止。",
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(context.tr("取消")),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(context.tr("退出登录")),
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
                  label: Text(context.tr("退出登录")),
                ),
                const SizedBox(height: 30),
                Center(
                  child: Text(
                    context.tr("Chat Studio\n适配 Studio v1.0.3"),
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
  String _versionLabel(PackageInfo info) {
    final version = info.version.trim();
    final build = info.buildNumber.trim();
    if (version.isEmpty)
      return build.isEmpty
          ? context.tr("未知版本")
          : context.l10n.format("构建 {0}", {'0': build});
    return build.isEmpty ? version : '$version ($build)';
  }

  Widget _aboutTile(BuildContext context) => FutureBuilder<PackageInfo>(
    future: _packageInfo,
    builder: (context, snapshot) {
      final info = snapshot.data;
      final version = info == null
          ? context.tr("正在读取版本信息…")
          : context.l10n.format("版本 {0}", {'0': _versionLabel(info)});
      return ListTile(
        leading: const Icon(Icons.info_outline_rounded),
        title: Text(context.tr("关于 Chat Studio")),
        subtitle: Text(
          context.l10n.format("{0}\n适配 Studio v1.0.3", {'0': version}),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: info == null
            ? null
            : () => showAboutDialog(
                context: context,
                applicationName: info.appName.isEmpty
                    ? 'Chat Studio'
                    : info.appName,
                applicationVersion: _versionLabel(info),
                applicationLegalese: 'Apache License 2.0',
                children: [
                  Text(context.tr("面向 Hermes Studio 的原生移动端客户端。")),
                  SizedBox(height: 12),
                  Text(context.tr("服务端兼容版本：Studio v1.0.3")),
                ],
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
