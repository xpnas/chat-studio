import 'package:flutter/foundation.dart';
import '../data/person_api.dart';
import '../data/person_models.dart';
import '../data/studio_api.dart';

class PersonFlowDetailsController extends ChangeNotifier {
  PersonFlowDetailsController(this.api, this.id, this.valid);
  final StudioApi api;
  final String id;
  final bool Function() valid;
  PersonFlow? flow;
  String historyKey = '';
  String? error;
  final pages = <PersonFlowMessagesPage>[];
  bool loading = false, hasMore = false, _disposed = false;
  int? before;
  int _generation = 0;
  int _lookupGeneration = 0;
  bool locating = false;
  void cancelLocate() {
    _lookupGeneration++;
    locating = false;
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>?> locate(
    int messageId,
    String stageId, {
    int maxPages = 20,
  }) async {
    if (_disposed || !valid() || loading) return null;
    final lookup = ++_lookupGeneration;
    locating = true;
    notifyListeners();
    try {
      for (var page = 0; page < maxPages; page++) {
        if (_disposed || !valid() || lookup != _lookupGeneration) return null;
        final target = messages
            .where(
              (row) => row['id'] == messageId && row['stage_id'] == stageId,
            )
            .firstOrNull;
        if (target != null) return target;
        if (!hasMore || before == null) {
          error = '协作结果已删除或不可用';
          return null;
        }
        await refresh(more: true);
        if (error != null) return null;
      }
      error = '已达定位页数上限，请在 Studio 查看';
      return null;
    } finally {
      if (!_disposed && lookup == _lookupGeneration) {
        locating = false;
        notifyListeners();
      }
    }
  }

  List<Map<String, dynamic>> get messages => {
    for (final page in pages)
      for (final row in page.messages) '${row['session_id']}:${row['id']}': row,
  }.values.toList();
  void invalidate() {
    cancelLocate();
    _generation++;
    pages.clear();
    historyKey = '';
    before = null;
    hasMore = false;
    loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh({bool more = false}) async {
    if (_disposed ||
        !valid() ||
        more && (loading || !hasMore || before == null)) {
      return;
    }
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await api.personFlowMessages(
        id,
        before: more ? before : null,
      );
      if (_disposed || !valid() || generation != _generation) return;
      if (historyKey.isNotEmpty && page.historyKey != historyKey) {
        pages.clear();
        if (more) {
          loading = false;
          await refresh();
          return;
        }
      }
      if (!more) pages.clear();
      historyKey = page.historyKey;
      flow = page.flow;
      pages.insert(0, page);
      while (pages.length > 3) {
        pages.removeLast();
      }
      hasMore = page.hasMore;
      before = page.nextBeforeId;
    } catch (e) {
      if (!_disposed && valid() && generation == _generation) {
        error = '$e';
        pages.clear();
      }
    } finally {
      if (!_disposed && valid() && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _lookupGeneration++;
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
