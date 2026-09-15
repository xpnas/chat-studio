import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'server_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});
  final AppController controller;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _server;
  final _username = TextEditingController(),
      _password = TextEditingController();
  bool _local = false, _obscure = true;
  @override
  void initState() {
    super.initState();
    _lastServer = widget.controller.serverInput;
    _server = TextEditingController(
      text: widget.controller.serverInput.isEmpty
          ? const String.fromEnvironment('DEFAULT_SERVER_URL')
          : widget.controller.serverInput,
    );
    _local = widget.controller.allowLocalHttp;
  }

  @override
  void didUpdateWidget(covariant LoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastServer != widget.controller.serverInput) {
      _lastServer = widget.controller.serverInput;
      _server.text = _lastServer;
      _local = widget.controller.allowLocalHttp;
      _password.clear();
      _username.clear();
    }
  }

  late String _lastServer;
  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false) || widget.controller.busy) {
      return;
    }
    FocusScope.of(context).unfocus();
    final ok = await widget.controller.login(
      _server.text,
      _username.text,
      _password.text,
      _local,
    );
    if (ok) {
      TextInput.finishAutofillContext();
      _password.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      EkkoMark(size: 46),
                      SizedBox(width: 14),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Chat Studio',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 54),
                  Text(
                    '你的灵感，\n随时接续。',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      letterSpacing: -1,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '连接你的 Studio，让每一次好奇都有回应。',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 15,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 34),
                  if (c.error != null)
                    ErrorNotice(message: c.error!, onDismiss: c.dismissError),
                  if (c.servers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextButton.icon(
                        icon: const Icon(Icons.dns_outlined, size: 18),
                        label: Text('已保存的服务器（${c.servers.length}）'),
                        onPressed: c.busy
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ServerScreen(controller: c),
                                ),
                              ),
                      ),
                    ),
                  AutofillGroup(
                    child: Form(
                      key: _form,
                      child: Column(
                        children: [
                          TextFormField(
                            key: const Key('server-field'),
                            controller: _server,
                            enabled: !c.busy,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: '服务地址',
                              hintText: 'https://studio.example.com',
                              prefixIcon: Icon(Icons.dns_outlined),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? '请输入服务地址'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('username-field'),
                            controller: _username,
                            enabled: !c.busy,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: '用户名',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (v) =>
                                v == null || v.trim().isEmpty ? '请输入用户名' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('password-field'),
                            controller: _password,
                            enabled: !c.busy,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enableSuggestions: false,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: '密码',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscure ? '显示密码' : '隐藏密码',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? '请输入密码' : null,
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              '允许局域网 HTTP',
                              style: TextStyle(fontSize: 14),
                            ),
                            subtitle: const Text(
                              '仅可信 Wi-Fi；公网始终要求 HTTPS',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: _local,
                            onChanged: c.busy
                                ? null
                                : (value) => setState(() => _local = value),
                          ),
                          if (_local)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Text(
                                'HTTP 不加密账号、密码和聊天内容。请勿在公共网络使用。',
                                style: TextStyle(
                                  color: colors.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const Key('login-button'),
                              onPressed: c.busy ? null : _submit,
                              child: c.busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '连接并登录',
                                          style: TextStyle(fontSize: 16),
                                        ),
                                        SizedBox(width: 10),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          '直连你的服务器 · 凭据存储在系统安全区',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
