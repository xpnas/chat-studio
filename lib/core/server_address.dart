import 'dart:io';

/// An origin, never an API endpoint. Restrict HTTP to explicitly opted-in LANs.
class ServerAddress {
  ServerAddress._(this.uri, this.allowLocalHttp);
  final Uri uri;
  final bool allowLocalHttp;
  String get value => uri.toString().replaceFirst(RegExp(r'/$'), '');

  factory ServerAddress.parse(String input, {bool allowLocalHttp = false}) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        '请输入服务根地址，例如 https://studio.example.com（不含 /api、账号或路径）',
      );
    }
    if (uri.scheme == 'http' && (!allowLocalHttp || !isLocalHost(uri.host))) {
      throw const FormatException('公网连接必须使用 HTTPS；局域网 HTTP 需要手动开启');
    }
    return ServerAddress._(uri.replace(path: ''), allowLocalHttp);
  }

  static bool isLocalHost(String host) {
    final value = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    if (value == 'localhost' || value.endsWith('.local')) return true;
    final ip = InternetAddress.tryParse(value);
    if (ip == null) return false;
    if (ip.isLoopback || ip.isLinkLocal) return true;
    final bytes = ip.rawAddress;
    if (bytes.length == 4) {
      return bytes[0] == 10 ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31);
    }
    return bytes.length == 16 && (bytes[0] & 0xfe) == 0xfc;
  }
}
