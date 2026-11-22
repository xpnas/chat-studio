import 'package:flutter/foundation.dart';
import '../data/person_api.dart';
import '../data/person_models.dart';
import '../data/protocol_capabilities.dart';
import '../data/studio_api.dart';

class PersonListController extends ChangeNotifier {
  PersonListController(this.api, this.account, this.valid);
  final StudioApi api;
  final Object account;
  final bool Function() valid;
  List<PersonConversation> sessions = [];
  String search = '';
  String? error;
  int? nextOffset;
  bool loading = false, _disposed = false;
  int _generation = 0;
  CapabilityState get capability => api.capabilities[ProtocolCapability.person];
  Future<void> refresh({String? query, bool more = false}) async {
    if (_disposed || !valid() || more && (loading || nextOffset == null)) {
      return;
    }
    final generation = ++_generation;
    if (query != null) search = query;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.personConversations(
        account,
        search: search,
        offset: more ? nextOffset! : 0,
      );
      if (_disposed || !valid() || generation != _generation) return;
      sessions = {
        if (more)
          for (final item in sessions) item.id: item,
        for (final item in result.sessions) item.id: item,
      }.values.toList();
      nextOffset = result.nextOffset;
    } catch (e) {
      if (!_disposed && valid() && generation == _generation) {
        error = '$e';
        sessions = [];
        nextOffset = null;
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
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
