import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/models.dart';
import '../data/protocol_capabilities.dart';
import '../data/session_sync_transport.dart';
import '../data/studio_api.dart';
import 'session_sync_state.dart';

class SessionSyncController extends ChangeNotifier {
  SessionSyncController(
    this.transport, {
    this.confirmationTimeout = const Duration(seconds: 8),
    this.refreshDelay = const Duration(milliseconds: 150),
  });
  final SessionSyncTransport transport;
  final Duration confirmationTimeout, refreshDelay;
  final projection = SessionSyncState();
  CapabilityState state = CapabilityState.unknown;
  bool removalsSubscribed = false;
  void Function(String)? onRemoval;
  StudioApi? _api;
  int _generation = 0, _connection = 0;
  Timer? _confirmation, _refresh;
  final _reading = <String>{};
  final _acknowledged = <String, (int, int)>{};
  bool _disposed = false;
  bool get confirmed =>
      state == CapabilityState.supported && projection.confirmed;
  void connect(StudioApi api) {
    disconnect();
    _api = api;
    final generation = _generation, profile = api.profile, token = api.token;
    projection.reset(profile);
    state = CapabilityState.unknown;
    transport.connect(api, (event, data) {
      if (_disposed ||
          generation != _generation ||
          api != _api ||
          profile != api.profile ||
          token != api.token) {
        return;
      }
      if (event == 'connected') {
        _connection++;
        projection.reset(profile, clearEvents: false);
        _reading.clear();
        _acknowledged.clear();
        state = CapabilityState.unknown;
        removalsSubscribed = false;
        _waitForSnapshot();
        unawaited(_subscribe(generation, _connection));
      } else if (event == 'sessions.state.snapshot') {
        if (projection.snapshot(projection.generation, data['sessions'])) {
          state = CapabilityState.supported;
          _confirmation?.cancel();
        }
      } else if (event == 'sessions.state.updated') {
        projection.update(projection.generation, data);
      } else if (event == 'disconnected' || event == 'connection.error') {
        _connection++;
        _reading.clear();
        _acknowledged.clear();
        _confirmation?.cancel();
        state = CapabilityState.unavailable;
        projection.confirmed = false;
        removalsSubscribed = false;
      } else if (event == 'app.event') {
        if (removalsSubscribed &&
            data['schema_version'] == 1 &&
            data['type'] == 'chat.session.removed' &&
            (text(data['profile']).isEmpty || data['profile'] == profile) &&
            projection.acceptEvent(projection.generation, text(data['id']))) {
          final id = text(asMap(data['subject'])['session_id']);
          if (id.isNotEmpty &&
              !id.startsWith('person-task-') &&
              !id.startsWith('person-main-')) {
            onRemoval?.call(id);
          }
        }
      }
      _notify();
    });
  }

  void _waitForSnapshot() {
    _confirmation?.cancel();
    _confirmation = Timer(confirmationTimeout, () {
      if (_disposed || confirmed) return;
      state = CapabilityState.unavailable;
      _notify();
    });
  }

  Future<void> _subscribe(int generation, int connection) async {
    try {
      final result = await transport.subscribeRemovals();
      if (generation != _generation || connection != _connection || _disposed) {
        return;
      }
      removalsSubscribed =
          result['ok'] == true && result['schema_version'] == 1;
      _notify();
    } catch (_) {
      /* State observation stays independent of optional App events. */
    }
  }

  void refresh() {
    if (_disposed || _api == null || _refresh?.isActive == true) return;
    _refresh = Timer(refreshDelay, () {
      if (_disposed || _api == null) return;
      if (!transport.connected) {
        connect(_api!);
        return;
      }
      try {
        transport.requestState();
        _waitForSnapshot();
      } catch (_) {
        state = CapabilityState.unavailable;
        _notify();
      }
    });
  }

  Future<bool> readVisible({
    required String id,
    required int messageId,
    required int attentionId,
    required bool foreground,
    required bool atLatest,
    required bool working,
    required bool hasUnseenAttention,
  }) async {
    final row = projection.sessions[id];
    if (!confirmed ||
        row == null ||
        row.working != false ||
        !foreground ||
        !atLatest ||
        working ||
        hasUnseenAttention ||
        messageId < 0 ||
        attentionId < 0 ||
        messageId > row.lastMessageId ||
        attentionId > row.lastAttentionId ||
        _reading.contains(id)) {
      return false;
    }
    final ack = _acknowledged[id] ?? (0, 0);
    final before = (
      row.readMessageId > ack.$1 ? row.readMessageId : ack.$1,
      row.readAttentionId > ack.$2 ? row.readAttentionId : ack.$2,
    );
    if (messageId <= before.$1 && attentionId <= before.$2) return true;
    if (messageId < before.$1 || attentionId < before.$2) return false;
    final generation = _generation, connection = _connection;
    _reading.add(id);
    try {
      final result = await transport.markRead(id, messageId, attentionId);
      if (_disposed ||
          generation != _generation ||
          connection != _connection ||
          result['ok'] != true) {
        return false;
      }
      _acknowledged[id] = (messageId, attentionId);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (generation == _generation && connection == _connection) {
        _reading.remove(id);
      }
    }
  }

  void disconnect() {
    _generation++;
    _connection++;
    _confirmation?.cancel();
    _refresh?.cancel();
    transport.dispose();
    _api = null;
    projection.reset(projection.profile);
    _reading.clear();
    _acknowledged.clear();
    removalsSubscribed = false;
    state = CapabilityState.unknown;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _disposed = true;
    super.dispose();
  }
}
