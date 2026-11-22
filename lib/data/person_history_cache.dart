import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'person_models.dart';

/// One file is one complete projected snapshot. Pending files are never read.
class PersonHistoryCache {
  PersonHistoryCache(this.root, this.server, this.account, this.sessionId);
  final Directory root;
  final String server, account, sessionId;
  String get scope => sha256
      .convert(
        utf8.encode(jsonEncode([server, account, sessionId, personProjection])),
      )
      .toString();
  File get file => File('${root.path}/$scope.json');
  Future<void> _writes = Future.value();
  int _generation = 0;
  bool _closed = false;
  Future<Map<String, dynamic>?> read() async {
    try {
      if (_closed ||
          !await file.exists() ||
          await file.length() > 12 * 1024 * 1024) {
        return null;
      }
      final data = asMap(jsonDecode(await file.readAsString()));
      if (data['version'] != 1 ||
          data['scope'] != scope ||
          data['projection'] != personProjection) {
        return null;
      }
      final latest = PersonTimelinePage.fromJson(asMap(data['latest']));
      if (latest.id.isEmpty || latest.items.length > 150) return null;
      final window = asList(
        data['window'],
      ).map((row) => PersonTimelinePage.fromJson(asMap(row))).toList();
      if ({
                ...latest.items.map((item) => item.key),
                for (final page in window)
                  ...page.items.map((item) => item.key),
              }.length >
              300 ||
          window.any(
            (page) => page.historyRevision != latest.historyRevision,
          )) {
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(
    Map<String, dynamic> data, {
    Future<void> Function()? beforePublish,
  }) {
    final generation = _generation;
    final encoded = jsonEncode({
      'version': 1,
      'scope': scope,
      'projection': personProjection,
      ...data,
    });
    if (encoded.length > 12 * 1024 * 1024) {
      return Future.error(
        const FormatException('BOT cache exceeds its size bound'),
      );
    }
    final next = _writes.catchError((Object _) {}).then((_) async {
      if (_closed || generation != _generation) return;
      await root.create(recursive: true);
      final pending = File('${file.path}.${const Uuid().v4()}.pending');
      try {
        await pending.writeAsString(encoded, flush: true);
        await beforePublish?.call();
        if (_closed || generation != _generation) return;
        await pending.rename(file.path);
      } finally {
        if (await pending.exists()) await pending.delete();
      }
    });
    _writes = next;
    return next;
  }

  Future<void> clear() async {
    _generation++;
    await _writes.catchError((Object _) {});
    if (await file.exists()) await file.delete();
  }

  void close() {
    _closed = true;
    _generation++;
  }
}
