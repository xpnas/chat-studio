import 'models.dart';

/// Server OS can differ from the phone OS. Only consume server-supplied paths;
/// do not use dart:io or the client's path resolver to turn relative into full.
bool isAbsoluteServerPath(String path) =>
    path.isNotEmpty &&
    !path.contains('\u0000') &&
    (path.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
        path.startsWith(r'\\'));

String serverWorkspaceError(Object error) {
  final detail = error.toString();
  if (detail.contains('ENOENT') ||
      detail.contains('no such file') ||
      detail.contains('workspace not found') ||
      detail.contains('Path not found')) {
    return '服务器工作目录不存在或尚未创建，请重新选择服务器上的文件夹。';
  }
  if (error is ApiException && error.status == 403) {
    return '没有访问此服务器目录的权限，请选择允许访问的文件夹。';
  }
  return '服务器工作区操作失败，请重试。$detail';
}
