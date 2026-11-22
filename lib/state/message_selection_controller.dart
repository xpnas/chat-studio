import 'package:flutter/foundation.dart';
import '../data/models.dart';
import '../data/message_selection.dart';

class MessageSelectionController<T extends Object, R extends Object>
    extends ChangeNotifier {
  MessageSelectionController({
    required this.read,
    required this.remove,
    required this.reconcile,
    required this.valid,
  });
  final Future<MessageSelection<T, R>> Function() read;
  final Future<Map<String, dynamic>> Function(List<T>, R) remove;
  final Future<void> Function() reconcile;
  final bool Function() valid;
  MessageSelection<T, R>? snapshot;
  final selected = <T>{};
  bool loading = false,
      submitting = false,
      uncertain = false,
      _disposed = false;
  int _generation = 0;
  String? error;
  List<MessageSelectionGroup<T>> get selectedGroups =>
      snapshot?.groups.where((group) => selected.contains(group.id)).toList() ??
      [];
  List<T> get messageIds =>
      selectedGroups.expand((group) => group.messageIds).toSet().toList();
  bool get canDelete =>
      !_disposed &&
      valid() &&
      !loading &&
      !submitting &&
      !uncertain &&
      selectedGroups.isNotEmpty;
  void toggle(T id) {
    if (loading ||
        submitting ||
        uncertain ||
        !valid() ||
        snapshot?.groups.any((group) => group.id == id && group.selectable) !=
            true) {
      return;
    }
    if (!selected.add(id)) selected.remove(id);
    notifyListeners();
  }

  void cancel() {
    selected.clear();
    _generation++;
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    if (_disposed || !valid() || submitting) return;
    final generation = ++_generation;
    snapshot = null;
    selected.clear();
    loading = true;
    error = null;
    notifyListeners();
    try {
      // An unknown write is reconciled read-only before another selection is allowed.
      if (uncertain) await reconcile();
      final result = await read();
      if (_disposed || !valid() || generation != _generation) return;
      snapshot = result;
      uncertain = false;
    } catch (e) {
      if (!_disposed && valid() && generation == _generation) error = '$e';
    } finally {
      if (!_disposed && valid() && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> deleteConfirmed() async {
    if (!canDelete) return false;
    final revision = snapshot!.historyRevision, ids = List<T>.of(messageIds);
    final generation = ++_generation;
    submitting = true;
    error = null;
    notifyListeners();
    var success = false, committed = false;
    try {
      await remove(ids, revision);
      committed = true;
      if (_disposed || !valid() || generation != _generation) return false;
      snapshot = null;
      selected.clear();
      await reconcile();
      success = true;
    } catch (e) {
      if (_disposed || !valid() || generation != _generation) return false;
      snapshot = null;
      selected.clear();
      if (committed) {
        uncertain = true;
        error = '消息已删除，视图刷新失败，请刷新核对';
      } else if (e is ApiException && e.status > 0 && e.status < 500) {
        error = e.status == 409 ? '历史或运行状态已变化，请重新选择并确认' : '$e';
        // No stop, no write retry, even if the server now has a new revision.
        try {
          await reconcile();
        } catch (_) {
          uncertain = true;
        }
      } else {
        uncertain = true;
        error = '删除结果未知，请刷新核对后重新选择';
      }
    } finally {
      if (!_disposed && valid() && generation == _generation) {
        submitting = false;
        notifyListeners();
      }
    }
    return success;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
