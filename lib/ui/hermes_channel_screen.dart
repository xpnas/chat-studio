import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/hermes_channels.dart';
import '../data/models.dart';
import '../data/studio_api.dart';
import '../l10n.dart';

/// Profile-scoped, native counterpart of Web PlatformSettings. Only changed
/// fields are sent, keeping secrets and settings edited by other clients intact.
class HermesChannelScreen extends StatefulWidget {
  const HermesChannelScreen({
    super.key,
    required this.api,
    required this.platform,
    required this.initialConfig,
    this.openQrUrl,
  });
  final StudioApi api;
  final String platform;
  final Map<String, dynamic> initialConfig;
  final Future<bool> Function(Uri)? openQrUrl;
  @override
  State<HermesChannelScreen> createState() => _HermesChannelScreenState();
}

class _HermesChannelScreenState extends State<HermesChannelScreen> {
  late final _profile = widget.api.profile;
  late final _token = widget.api.token;
  late final _fields = channelFields(widget.platform);
  late Map<String, dynamic> _config;
  final _inputs = <String, TextEditingController>{};
  final _toggles = <String, bool>{};
  final _initial = <String, dynamic>{};
  final _behavior = <String, dynamic>{};
  final _credentials = <String, dynamic>{};
  bool _busy = false;
  String? _notice;
  bool _noticeError = false;
  bool _allowPop = false;
  Timer? _qrTimer;
  int _qrEpoch = 0, _qrPolls = 0;
  String _qrStatus = '', _qrId = '';
  Uri? _qrUrl;
  bool get _dirty => _behavior.isNotEmpty || _credentials.isNotEmpty;
  bool get _qrActive => ['loading', 'waiting', 'scaned'].contains(_qrStatus);
  bool get _valid =>
      mounted && widget.api.profile == _profile && widget.api.token == _token;
  bool get _stored => channelCredentialsStored(_config, widget.platform);

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    for (final field in _fields) {
      if (field.kind != ChannelFieldKind.toggle) {
        _inputs[field.path] = TextEditingController();
      }
    }
    _resetFields();
  }

  dynamic _sourceValue(ChannelField field) => channelValue(
    field.credential
        ? asMap(asMap(_config['platforms'])[widget.platform])
        : asMap(_config[widget.platform]),
    field.path,
  );

  void _resetFields() {
    for (final field in _fields) {
      final value = _sourceValue(field);
      final initial = switch (field.kind) {
        ChannelFieldKind.password => '', // Never echo a server-returned secret.
        ChannelFieldKind.toggle =>
          value == null && field.path == 'extra.markdown_support'
              ? true
              : channelBool(value),
        ChannelFieldKind.list => asList(value).map(text).toList(),
        ChannelFieldKind.text =>
          value is List ? value.map(text).join(', ') : text(value),
      };
      _initial[field.path] = initial;
      if (field.kind == ChannelFieldKind.toggle) {
        _toggles[field.path] = initial as bool;
      } else {
        _inputs[field.path]!.text = initial is List
            ? initial.join(', ')
            : '$initial';
      }
    }
    _behavior.clear();
    _credentials.clear();
  }

  void _changed(ChannelField field, dynamic raw) {
    final value = field.kind == ChannelFieldKind.list
        ? text(raw)
              .split(RegExp(r'[,\n]'))
              .map((v) => v.trim())
              .where((v) => v.isNotEmpty)
              .toList()
        : raw;
    final changes = field.credential ? _credentials : _behavior;
    setState(() {
      if (jsonEncode(value) == jsonEncode(_initial[field.path])) {
        changes.remove(field.path);
      } else {
        changes[field.path] = value;
      }
      if (field.kind == ChannelFieldKind.toggle) {
        _toggles[field.path] = value == true;
      }
    });
  }

  void _checkScope() {
    if (!_valid) throw const ApiException('已取消：会话或 Profile 已变化');
  }

  void _message(String key, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _notice = key;
      _noticeError = error;
    });
  }

  Future<bool> _confirm(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr(title)),
          content: Text(context.tr(detail)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('取消')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('确认')),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty && !await _confirm('放弃未保存的更改？', '离开后将丢弃本页未保存的频道设置。')) return;
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.pop(context);
  }

  Future<bool> _reload() async {
    try {
      _checkScope();
      final config = await widget.api.fetchConfig();
      _checkScope();
      setState(() {
        _config = config;
        _resetFields();
      });
      return true;
    } catch (_) {
      _message('读取最新频道状态失败，请刷新重试；已提交的修改不会回滚。', error: true);
      return false;
    }
  }

  Future<void> _refresh() async {
    if (_busy || _qrActive) return;
    if (_dirty && !await _confirm('放弃未保存的更改？', '刷新将重新读取 Web 使用的服务器配置。')) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() async {
    if (_busy || !_dirty || _qrActive) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _notice = null;
    });
    var behaviorSaved = false;
    try {
      _checkScope();
      if (_behavior.isNotEmpty) {
        await widget.api.updateConfigSection(
          widget.platform,
          nestedChannelPatch(_behavior),
          restart: _credentials.isEmpty,
        );
        _checkScope();
        _initial.addAll(_behavior);
        _behavior.clear();
        behaviorSaved = true;
      }
      if (_credentials.isNotEmpty) {
        _checkScope();
        await widget.api.updateHermesChannelCredentials(
          widget.platform,
          nestedChannelPatch(_credentials),
        );
        _checkScope();
        _initial.addAll(_credentials);
        _credentials.clear();
        for (final field in _fields.where(
          (f) => f.kind == ChannelFieldKind.password,
        )) {
          _inputs[field.path]!.clear();
          _initial[field.path] = '';
        }
      }
      if (await _reload()) _message('频道设置已保存；网关是否自动重启由服务端策略决定。');
    } catch (e) {
      if (mounted) {
        final detail = e is ApiException ? e.message : '$e';
        _message(
          '${context.tr(behaviorSaved ? '行为设置已保存，但凭据保存未完成。' : '保存未完成，服务端可能已写入部分配置。')}\n${context.tr(detail)}',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    if (_dirty ||
        _busy ||
        _qrActive ||
        !_stored ||
        widget.platform == 'whatsapp') {
      return;
    }
    if (!await _confirm('清除凭据？', '清除后频道将无法连接，确定继续？')) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      _checkScope();
      final result = await widget.api.clearHermesChannelCredentials(
        widget.platform,
      );
      _checkScope();
      final refreshed = await _reload();
      final warning = asMap(result['warning']);
      if (warning.isNotEmpty) {
        _message(switch (warning['code']) {
          'gateway_restart_failed' => '凭据已清除，但网关重启失败，请检查服务端。',
          'gateway_restart_disabled' => '凭据已清除；自动重启已禁用，请手动重启网关。',
          _ => text(warning['message']),
        }, error: true);
      } else if (refreshed) {
        _message('凭据已清除');
      }
    } catch (e) {
      _message(e is ApiException ? e.message : '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _stopQr() {
    ++_qrEpoch;
    _qrTimer?.cancel();
    _qrTimer = null;
  }

  Future<bool> _openQr(Uri uri) =>
      widget.openQrUrl?.call(uri) ??
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _startQr() async {
    if (_busy || _dirty) return;
    _stopQr();
    final epoch = _qrEpoch;
    setState(() {
      _qrStatus = 'loading';
      _qrPolls = 0;
      _notice = null;
      _qrUrl = null;
    });
    try {
      _checkScope();
      final result = await widget.api.hermesWeixinQrCode();
      if (!_valid || epoch != _qrEpoch) return;
      final uri = Uri.tryParse(text(result['qrcode_url']));
      if (uri == null ||
          !['https', 'http'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          text(result['qrcode']).isEmpty) {
        throw const ApiException('服务端返回了无效的扫码地址');
      }
      _qrId = text(result['qrcode']);
      setState(() {
        _qrStatus = 'waiting';
        _qrUrl = uri;
      });
      _scheduleQr(epoch);
      if (!await _openQr(uri) && _valid && epoch == _qrEpoch) {
        _message('无法打开扫码页面，请重试或手动填写凭据。', error: true);
      }
    } catch (e) {
      if (mounted && epoch == _qrEpoch) {
        _stopQr();
        setState(() => _qrStatus = 'error');
        _message(e is ApiException ? e.message : '$e', error: true);
      }
    }
  }

  void _scheduleQr(int epoch) {
    _qrTimer = Timer(const Duration(seconds: 3), () async {
      if (!_valid || epoch != _qrEpoch) return;
      if (++_qrPolls > 100) {
        setState(() => _qrStatus = 'expired');
        return;
      }
      try {
        final result = await widget.api.hermesWeixinQrStatus(_qrId);
        if (!_valid || epoch != _qrEpoch) return;
        switch (result['status']) {
          case 'confirmed':
            if (text(result['token']).isEmpty ||
                text(result['account_id']).isEmpty) {
              throw const ApiException('扫码确认数据不完整，请重新扫码');
            }
            setState(() {
              _qrStatus = 'confirmed';
              _busy = true;
            });
            try {
              _checkScope();
              await widget.api.saveHermesWeixinCredentials({
                'token': result['token'],
                'account_id': result['account_id'],
                if (result['base_url'] != null) 'base_url': result['base_url'],
              });
              _checkScope();
              if (await _reload()) _message('扫码登录成功，频道凭据已保存');
            } catch (e) {
              if (mounted) setState(() => _qrStatus = 'error');
              _message(e is ApiException ? e.message : '$e', error: true);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
            return;
          case 'expired':
            setState(() => _qrStatus = 'expired');
            return;
          case 'scaned':
            setState(() => _qrStatus = 'scaned');
          case 'wait':
          case 'scaned_but_redirect':
            break;
          default:
            throw const ApiException('扫码状态异常，请重新扫码');
        }
        _scheduleQr(epoch);
      } catch (e) {
        if (_valid && epoch == _qrEpoch) {
          setState(() => _qrStatus = 'error');
          _message(e is ApiException ? e.message : '$e', error: true);
        }
      }
    });
  }

  @override
  void dispose() {
    _stopQr();
    for (final input in _inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Widget _field(ChannelField field) {
    final enabled = !_busy && !_qrActive;
    final secret = field.kind == ChannelFieldKind.password;
    final stored = secret && text(_sourceValue(field)).isNotEmpty;
    if (field.kind == ChannelFieldKind.toggle) {
      return SwitchListTile.adaptive(
        key: ValueKey('channel-field:${field.path}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text(context.tr(field.label)),
        subtitle: field.path == 'allow_all_users'
            ? Text(context.tr('开启后所有用户均可与此 Bot 交互'))
            : null,
        value: _toggles[field.path] ?? false,
        onChanged: enabled
            ? (value) async {
                if (field.path == 'allow_all_users' &&
                    value &&
                    !await _confirm('允许所有用户？', '开启后所有用户均可与此 Bot 交互')) {
                  return;
                }
                if (mounted) _changed(field, value);
              }
            : null,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: TextField(
        key: ValueKey('channel-field:${field.path}'),
        controller: _inputs[field.path],
        enabled: enabled,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: !secret,
        onChanged: (value) => _changed(field, value),
        decoration: InputDecoration(
          labelText: context.tr(field.label),
          helperMaxLines: 3,
          helperText: secret
              ? context.tr(
                  _credentials[field.path] == ''
                      ? '保存后清除此项凭据'
                      : stored
                      ? '已保存；留空保持不变，输入新值替换'
                      : '输入凭据后保存',
                )
              : (field.kind == ChannelFieldKind.list ||
                    field.path.contains('channels') ||
                    field.path.contains('chats') ||
                    field.path.contains('rooms') ||
                    field.path == 'allowed_users')
              ? context.tr('多个值请使用逗号分隔')
              : null,
          suffixIcon: stored
              ? IconButton(
                  tooltip: context.tr('清除此项凭据'),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: enabled
                      ? () async {
                          if (await _confirm(
                                '清除此项凭据？',
                                '点击保存后生效，可能导致频道断开连接。',
                              ) &&
                              mounted) {
                            setState(() {
                              _inputs[field.path]!.clear();
                              _credentials[field.path] = '';
                            });
                          }
                        }
                      : null,
                )
              : null,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || (!_dirty && !_busy),
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) {
        _stopQr();
      } else {
        unawaited(_leave());
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(hermesChannelNames[widget.platform]!),
        actions: [
          IconButton(
            tooltip: context.tr('刷新'),
            onPressed: _busy || _qrActive ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(15, 8, 15, 24),
              children: [
                Text(
                  context.l10n.format('配置保存到当前服务器 · Profile：{0}', {
                    '0': _profile,
                  }),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      context.tr(_notice!),
                      key: const Key('channel-notice'),
                      style: TextStyle(
                        color: _noticeError
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                    ),
                  ),
                if (!['matrix', 'wecom'].contains(widget.platform))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      context.tr('同一 Bot 凭据不要同时用于多个 Profile 或其他运行实例，以免连接冲突。'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Text(
                  context.tr('频道凭据'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (widget.platform == 'weixin') ...[
                  OutlinedButton.icon(
                    key: const Key('weixin-qr-login'),
                    onPressed: _busy || _dirty || _qrActive ? null : _startQr,
                    icon: const Icon(Icons.qr_code_rounded),
                    label: Text(context.tr('微信扫码登录')),
                  ),
                  if (_qrStatus.isNotEmpty)
                    Text(
                      context.tr(switch (_qrStatus) {
                        'loading' => '正在获取二维码…',
                        'waiting' => '请在打开的页面扫码；确认后自动保存到当前 Profile。',
                        'scaned' => '已扫码，请在微信中确认',
                        'expired' => '二维码已过期，请重新获取',
                        'confirmed' => '扫码已确认',
                        _ => '扫码失败，请重试',
                      }),
                    ),
                  if (_qrActive)
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_qrUrl != null)
                          TextButton(
                            onPressed: () async {
                              try {
                                await _openQr(_qrUrl!);
                              } catch (_) {
                                _message('无法打开扫码页面，请重试或手动填写凭据。', error: true);
                              }
                            },
                            child: Text(context.tr('打开扫码页面')),
                          ),
                        TextButton(
                          onPressed: () {
                            _stopQr();
                            setState(() => _qrStatus = '');
                          },
                          child: Text(context.tr('取消')),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                ],
                ..._fields.where((field) => field.credential).map(_field),
                if (_fields.any((field) => !field.credential)) ...[
                  const SizedBox(height: 20),
                  Text(
                    context.tr('频道行为'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  ..._fields.where((field) => !field.credential).map(_field),
                ],
                if (_stored && widget.platform != 'whatsapp') ...[
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    key: const Key('clear-channel-credentials'),
                    onPressed: _busy || _dirty || _qrActive ? null : _clear,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(context.tr('清除全部凭据')),
                  ),
                  if (_dirty)
                    Text(
                      context.tr('请先保存或放弃修改，再清除全部凭据。'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 8, 15, 12),
          child: FilledButton.icon(
            key: const Key('save-channel'),
            onPressed: _busy || !_dirty || _qrActive ? null : _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(context.tr(_busy ? '保存中' : '保存')),
          ),
        ),
      ),
    ),
  );
}
