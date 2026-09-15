import 'package:mime/mime.dart';
import 'models.dart';

/// Only local server paths or the configured Studio download endpoint become
/// authenticated requests. Arbitrary remote origins never receive the token.
MessageAttachment? messageFileReference(
  String href, {
  Uri? server,
  String? label,
}) {
  var value = href.trim();
  if (value.startsWith('<') && value.endsWith('>')) {
    value = value.substring(1, value.length - 1);
  }
  final uri = Uri.tryParse(value);
  if (uri == null || value.startsWith('//')) return null;
  String path;
  if (uri.path == '/api/studio/files/download' &&
      ((!uri.hasAuthority && uri.scheme.isEmpty) ||
          (server != null &&
              ['http', 'https'].contains(uri.scheme) &&
              uri.userInfo.isEmpty &&
              uri.origin == server.origin))) {
    try {
      path = uri.queryParameters['path'] ?? '';
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  } else if (value.startsWith('/') &&
      !value.startsWith('//') &&
      !uri.hasAuthority &&
      !uri.hasQuery &&
      !uri.hasFragment) {
    try {
      path = Uri.decodeComponent(value);
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  } else if (RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value)) {
    try {
      path = Uri.decodeComponent(value).replaceAll('\\', '/');
    } on ArgumentError {
      return null;
    } on FormatException {
      return null;
    }
  } else {
    return null;
  }
  if (path.isEmpty || path.contains(RegExp(r'[\x00-\x1f]'))) return null;
  final name = path.replaceAll('\\', '/').split('/').last;
  return MessageAttachment(
    name: name.isEmpty ? (label ?? '附件') : name,
    path: path,
    mimeType: lookupMimeType(path) ?? 'application/octet-stream',
  );
}
