import 'dart:io';
import 'package:flutter/services.dart';

/// Path-only bridge: no multi-megabyte platform-channel byte array copies.
class FileExport {
  static const _channel = MethodChannel('ai.ekkolearn.ekko_app/file_export');
  static Future<String?> save(File file, String name, String mime) =>
      _channel.invokeMethod<String>('save', {
        'path': file.path,
        'name': name,
        'mime': mime,
      });
}
