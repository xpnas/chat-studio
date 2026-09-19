import 'package:flutter/foundation.dart';
import '../data/models.dart';
import '../data/studio_api.dart';

class HistoryEntry {
  HistoryEntry(Map<String, dynamic> json, String profile)
    : conversation = Conversation.fromJson({
        ...json,
        'last_active':
            json['last_active'] ?? json['ended_at'] ?? json['started_at'],
        'profile': text(json['profile']).isEmpty ? profile : json['profile'],
      }),
      imported = json['webui_imported'] as bool?;
  final Conversation conversation;
  final bool? imported;
  String get key => '${conversation.profile}\u0000${conversation.id}';
}

class HistorySource {
  HistorySource(this.source);
  final String source;
  int offset = 0;
  bool hasMore = false, loading = false;
  String? error;
}

String historySourceLabel(String source) =>
    const {
      'api_server': 'API Server',
      'cli': 'CLI',
      'coding_agent': 'Coding Agent',
      'global_agent': 'Global Agent',
      'telegram': 'Telegram',
      'discord': 'Discord',
      'slack': 'Slack',
      'matrix': 'Matrix',
      'whatsapp': 'WhatsApp',
      'signal': 'Signal',
      'email': 'Email',
      'sms': 'SMS',
      'dingtalk': 'DingTalk',
      'feishu': 'Feishu',
      'wecom': 'WeCom',
      'weixin': 'WeChat',
      'bluebubbles': 'iMessage',
      'mattermost': 'Mattermost',
      'cron': 'Cron',
      '': '其他',
    }[source] ??
    source;

/// History is a read-only view of all server sources, not the active chat list.
class HistoryController extends ChangeNotifier {
  HistoryController(this.api, this.profile);
  final StudioApi api;
  final String profile;
  final entries = <String, HistoryEntry>{};
  final sources = <String, HistorySource>{};
  bool loading = false, mutating = false, _disposed = false;
  int _revision = 0;
  String? error;
  bool _current(int revision) => !_disposed && revision == _revision;
  Uri linkFor(HistoryEntry entry) {
    final row = entry.conversation;
    final route = Uri(
      pathSegments: ['', 'hermes', 'history', 'session', row.id],
      queryParameters: {'profile': row.profile},
    );
    return api.address.uri.replace(
      path: '/',
      query: '',
      fragment: route.toString(),
    );
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  List<HistoryEntry> rows({String? source, bool pinned = false}) =>
      entries.values
          .where(
            (e) =>
                e.conversation.isPinned == pinned &&
                (source == null || e.conversation.source == source),
          )
          .toList()
        ..sort(
          (a, b) =>
              b.conversation.updatedAt.compareTo(a.conversation.updatedAt),
        );

  List<HistorySource> get groups =>
      sources.values
          .where((s) => s.hasMore || rows(source: s.source).isNotEmpty)
          .toList()
        ..sort((a, b) {
          int rank(String s) => s == 'api_server'
              ? -1
              : s == 'cron'
              ? 1
              : 0;
          final order = rank(a.source).compareTo(rank(b.source));
          return order == 0 ? a.source.compareTo(b.source) : order;
        });

  void _merge(dynamic rows) {
    for (final json in asList(rows)) {
      final entry = HistoryEntry(asMap(json), profile);
      if (entry.conversation.id.isEmpty) continue;
      entries[entry.key] = entry;
      sources.putIfAbsent(
        entry.conversation.source,
        () => HistorySource(entry.conversation.source),
      );
    }
  }

  Future<void> refresh() async {
    final revision = ++_revision;
    loading = true;
    error = null;
    _emit();
    try {
      final data = await api.request(
        '/api/studio/sessions/hermes/groups',
        query: {'profile': profile, 'limit': '50'},
      );
      if (!_current(revision)) return;
      entries.clear();
      sources.clear();
      for (final value in asList(data['groups'])) {
        final group = asMap(value), source = text(asMap(value)['source']);
        final rows = asList(group['sessions']);
        sources[source] = HistorySource(source)
          ..offset = rows.length
          ..hasMore = flag(group['hasMore']);
        _merge(rows);
      }
      _merge(data['included']);
    } catch (e) {
      if (_current(revision)) error = '$e';
    } finally {
      if (_current(revision)) {
        loading = false;
        _emit();
      }
    }
  }

  Future<void> loadMore(HistorySource group) async {
    if (loading || group.loading || !group.hasMore || mutating) return;
    final revision = _revision;
    group.loading = true;
    group.error = null;
    _emit();
    try {
      final data = await api.request(
        '/api/studio/sessions/hermes',
        query: {
          'profile': profile,
          'source': group.source,
          'offset': '${group.offset}',
          'limit': '50',
        },
      );
      if (!_current(revision)) return;
      final rows = asList(data['sessions']);
      _merge(rows);
      group.offset += rows.length;
      group.hasMore = rows.isNotEmpty && flag(data['hasMore']);
    } catch (e) {
      if (_current(revision)) group.error = '$e';
    } finally {
      if (_current(revision)) {
        group.loading = false;
        _emit();
      }
    }
  }

  Future<void> action(HistoryEntry entry, String action) async {
    if (mutating) return;
    mutating = true;
    _emit();
    try {
      final row = entry.conversation,
          id = Uri.encodeComponent(entry.conversation.id);
      await api.request(
        action == 'import'
            ? '/api/studio/sessions/hermes/$id/import'
            : '/api/studio/sessions/$id${action == 'delete' ? '' : '/$action'}',
        method: action == 'delete' ? 'DELETE' : 'POST',
        query: {'profile': row.profile},
        body: action == 'pin' ? {'is_pinned': !row.isPinned} : null,
      );
      if (!_disposed) await refresh();
    } finally {
      mutating = false;
      _emit();
    }
  }

  Future<Map<String, dynamic>> deleteSelected(
    List<HistoryEntry> selected,
  ) async {
    if (_disposed || mutating) {
      throw StateError(
        'History is unavailable or another operation is running',
      );
    }
    mutating = true;
    _emit();
    try {
      final result = await api.request(
        '/api/studio/sessions/batch-delete',
        method: 'POST',
        body: {
          'ids': selected.map((e) => e.conversation.id).toList(),
          'sessions': selected
              .map(
                (e) => {
                  'id': e.conversation.id,
                  'profile': e.conversation.profile,
                },
              )
              .toList(),
        },
      );
      if (!_disposed) await refresh();
      return result;
    } finally {
      mutating = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
