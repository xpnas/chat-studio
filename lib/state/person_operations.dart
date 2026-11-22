import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../data/models.dart';

class PersonOperation extends ChangeNotifier {
  PersonOperation({required this.persist, required this.valid});
  final Future<void> Function(Map<String, dynamic>?) persist;
  final bool Function() valid;
  Map<String, dynamic>? payload;
  String? target;
  bool pending = false, uncertain = false, _disposed = false;
  String? error;
  Map<String, dynamic>? get journal =>
      payload == null ? null : {'target': target, 'payload': payload};
  void restore(Map<String, dynamic> data) {
    if (data['payload'] is Map &&
        asMap(data['payload'])['idempotency_key'] is String) {
      target = text(data['target']);
      payload = asMap(data['payload']);
      uncertain = true;
    }
  }

  Future<Map<String, dynamic>?> perform(
    String route,
    Map<String, dynamic> input,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) send, {
    bool retry = false,
  }) async {
    if (!valid() || pending || uncertain && !retry) return null;
    if (retry &&
        (payload == null ||
            target != route ||
            jsonEncode({
                  ...input,
                  'idempotency_key': payload!['idempotency_key'],
                }) !=
                jsonEncode(payload))) {
      return null;
    }
    if (!retry) {
      payload = {...input, 'idempotency_key': const Uuid().v4()};
      target = route;
    }
    pending = true;
    error = null;
    notifyListeners();
    try {
      await persist(journal);
      if (!valid()) return null;
      final response = await send(Map.of(payload!));
      if (!valid()) return null;
      payload = null;
      target = null;
      uncertain = false;
      await persist(null);
      return response;
    } catch (e) {
      if (!valid()) return null;
      error = '$e';
      // A server error can occur after a committed operation. Preserve its key.
      uncertain = !(e is ApiException && e.status >= 400 && e.status < 500);
      if (!uncertain) {
        payload = null;
        target = null;
        await persist(null);
      }
      return null;
    } finally {
      pending = false;
      if (!_disposed && valid()) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
