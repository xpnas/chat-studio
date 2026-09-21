import 'models.dart';

enum ChannelFieldKind { text, password, toggle, list }

class ChannelField {
  const ChannelField(
    this.path,
    this.label, {
    this.kind = ChannelFieldKind.text,
    this.credential = false,
    this.hint = '',
  });
  final String path;
  final String label;
  final ChannelFieldKind kind;
  final bool credential;
  final String hint;
}

List<ChannelField> channelFields(String platform) {
  final commonGroup = <ChannelField>[
    const ChannelField(
      'require_mention',
      '需要提及',
      kind: ChannelFieldKind.toggle,
    ),
    const ChannelField('free_response_chats', '无需提及的会话'),
    const ChannelField(
      'mention_patterns',
      '提及匹配模式',
      kind: ChannelFieldKind.list,
    ),
  ];
  switch (platform) {
    case 'telegram':
      return [
        const ChannelField(
          'token',
          'Bot Token',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField('proxy', '代理地址', credential: true),
        ...commonGroup,
        const ChannelField('reactions', '启用反应', kind: ChannelFieldKind.toggle),
      ];
    case 'discord':
      return [
        const ChannelField(
          'token',
          'Bot Token',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField('proxy', '代理地址', credential: true),
        const ChannelField(
          'require_mention',
          '需要提及',
          kind: ChannelFieldKind.toggle,
        ),
        const ChannelField(
          'auto_thread',
          '自动创建线程',
          kind: ChannelFieldKind.toggle,
        ),
        const ChannelField('reactions', '启用反应', kind: ChannelFieldKind.toggle),
        const ChannelField('free_response_channels', '无需提及的频道'),
        const ChannelField('allowed_channels', '允许的频道'),
        const ChannelField('ignored_channels', '忽略的频道'),
        const ChannelField('no_thread_channels', '不创建线程的频道'),
      ];
    case 'slack':
      return [
        const ChannelField(
          'token',
          'Bot Token',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField(
          'require_mention',
          '需要提及',
          kind: ChannelFieldKind.toggle,
        ),
        const ChannelField(
          'allow_bots',
          '允许响应其他 Bot',
          kind: ChannelFieldKind.toggle,
        ),
        const ChannelField('free_response_channels', '无需提及的频道'),
      ];
    case 'whatsapp':
      return [
        const ChannelField(
          'enabled',
          '启用 WhatsApp',
          kind: ChannelFieldKind.toggle,
          credential: true,
        ),
        ...commonGroup,
      ];
    case 'matrix':
      return [
        const ChannelField(
          'token',
          'Access Token',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField('extra.user_id', '用户 ID', credential: true),
        const ChannelField(
          'extra.password',
          '密码',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField('extra.homeserver', 'Homeserver', credential: true),
        const ChannelField('proxy', '代理地址', credential: true),
        const ChannelField(
          'require_mention',
          '需要提及',
          kind: ChannelFieldKind.toggle,
        ),
        const ChannelField(
          'auto_thread',
          '自动创建线程',
          kind: ChannelFieldKind.toggle,
        ),
        const ChannelField(
          'dm_mention_threads',
          '私聊使用提及线程',
          kind: ChannelFieldKind.toggle,
        ),
        const ChannelField('free_response_rooms', '无需提及的房间'),
      ];
    case 'feishu':
      return [
        const ChannelField('extra.app_id', 'App ID', credential: true),
        const ChannelField(
          'extra.app_secret',
          'App Secret',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField(
          'extra.encrypt_key',
          'Encrypt Key',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField(
          'extra.verification_token',
          'Verification Token',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField(
          'require_mention',
          '需要提及',
          kind: ChannelFieldKind.toggle,
        ),
        const ChannelField('free_response_chats', '无需提及的会话'),
      ];
    case 'dingtalk':
      return [
        const ChannelField('extra.client_id', 'Client ID', credential: true),
        const ChannelField(
          'extra.client_secret',
          'Client Secret',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField(
          'extra.app_key',
          'App Key',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField(
          'extra.card_template_id',
          '卡片模板 ID',
          credential: true,
        ),
        const ChannelField('allowed_users', '允许的用户', credential: true),
        const ChannelField(
          'allow_all_users',
          '允许所有用户',
          kind: ChannelFieldKind.toggle,
          credential: true,
        ),
        const ChannelField(
          'require_mention',
          '需要提及',
          kind: ChannelFieldKind.toggle,
        ),
        const ChannelField('free_response_chats', '无需提及的会话'),
      ];
    case 'qqbot':
      return [
        const ChannelField('extra.app_id', 'App ID', credential: true),
        const ChannelField(
          'extra.client_secret',
          'App Secret',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField('allowed_users', '允许的用户', credential: true),
        const ChannelField(
          'allow_all_users',
          '允许所有用户',
          kind: ChannelFieldKind.toggle,
          credential: true,
        ),
        const ChannelField(
          'extra.markdown_support',
          'Markdown 支持',
          kind: ChannelFieldKind.toggle,
        ),
      ];
    case 'weixin':
      return [
        const ChannelField(
          'token',
          'Token',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
        const ChannelField('extra.account_id', 'Account ID', credential: true),
        const ChannelField('extra.base_url', 'Base URL', credential: true),
      ];
    case 'wecom':
      return [
        const ChannelField('extra.bot_id', 'Bot ID', credential: true),
        const ChannelField(
          'extra.secret',
          'Secret',
          kind: ChannelFieldKind.password,
          credential: true,
        ),
      ];
    default:
      return const [];
  }
}

const hermesChannelNames = {
  'telegram': 'Telegram',
  'discord': 'Discord',
  'slack': 'Slack',
  'whatsapp': 'WhatsApp',
  'matrix': 'Matrix',
  'feishu': 'Feishu',
  'dingtalk': 'DingTalk',
  'qqbot': 'QQBot',
  'weixin': 'Weixin',
  'wecom': 'WeCom',
};

dynamic channelValue(Map<String, dynamic> source, String path) {
  dynamic value = source;
  for (final part in path.split('.')) {
    if (value is! Map) return null;
    value = value[part];
  }
  return value;
}

bool channelBool(dynamic value) => value == true || value == 'true';
bool _present(dynamic value) =>
    value != null && value != false && '$value'.trim().isNotEmpty;

/// Mirrors PlatformCard.vue. Credential presence is NOT channel readiness:
/// Matrix needs a homeserver and token (or user/password); a proxy alone is not a login.
bool channelConfigured(Map<String, dynamic> config, String platform) {
  final credentials = asMap(asMap(config['platforms'])[platform]);
  if (platform == 'matrix') {
    return text(
          channelValue(credentials, 'extra.homeserver'),
        ).trim().isNotEmpty &&
        (_present(credentials['token']) ||
            (_present(channelValue(credentials, 'extra.user_id')) &&
                _present(channelValue(credentials, 'extra.password'))));
  }
  const keys = [
    'token',
    'api_key',
    'app_id',
    'client_id',
    'secret',
    'app_secret',
    'client_secret',
    'access_token',
    'bot_id',
    'account_id',
    'enabled',
  ];
  return [
    credentials,
    asMap(credentials['extra']),
  ].any((values) => keys.any((key) => _present(values[key])));
}

bool channelCredentialsStored(Map<String, dynamic> config, String platform) =>
    asMap(config['platformCredentialStatus'])[platform] == true;

Map<String, dynamic> nestedChannelPatch(Map<String, dynamic> flat) {
  final result = <String, dynamic>{};
  for (final entry in flat.entries) {
    final parts = entry.key.split('.');
    var current = result;
    for (final part in parts.take(parts.length - 1)) {
      current =
          current.putIfAbsent(part, () => <String, dynamic>{})
              as Map<String, dynamic>;
    }
    current[parts.last] = entry.value;
  }
  return result;
}
