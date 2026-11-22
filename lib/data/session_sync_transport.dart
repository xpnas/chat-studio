import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'chat_transport.dart' show SocketEvent, decodeSocketPayload;
import 'models.dart';
import 'protocol_capabilities.dart';
import 'studio_api.dart';

abstract class SessionSyncTransport {
  bool get connected;
  void connect(StudioApi api, SocketEvent listener);
  void requestState();
  Future<Map<String, dynamic>> markRead(
    String id,
    int messageId,
    int attentionId,
  );
  Future<Map<String, dynamic>> subscribeRemovals();
  void dispose();
}

class SocketSessionSyncTransport implements SessionSyncTransport {
  SocketSessionSyncTransport({
    io.Socket Function(String, Map<String, dynamic>)? socketFactory,
    this.ackTimeout = const Duration(seconds: 8),
  }) : _socketFactory = socketFactory ?? io.io;
  final io.Socket Function(String, Map<String, dynamic>) _socketFactory;
  final Duration ackTimeout;
  io.Socket? _socket;
  int _generation = 0, _connection = 0;
  bool Function()? _identityValid;
  String _profile = 'default';
  @override
  bool get connected =>
      _socket?.connected == true && (_identityValid?.call() ?? false);
  @override
  void connect(StudioApi api, SocketEvent listener) {
    dispose();
    final generation = _generation, token = api.token, profile = api.profile;
    bool valid() =>
        generation == _generation &&
        token == api.token &&
        profile == api.profile;
    _identityValid = valid;
    _profile = profile;
    final socket = _socketFactory(
      '${api.address.value}/chat-run',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .disableMultiplex()
          .setAuth({'token': token})
          .setQuery({'profile': profile, 'session_state': '1'})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .setTimeout(15000)
          .build()
        ..['multiplex'] = false,
    );
    _socket = socket;
    socket.onConnect((_) {
      if (valid()) {
        _connection++;
        listener('connected', {});
      }
    });
    socket.onDisconnect((_) {
      if (valid()) {
        _connection++;
        listener('disconnected', {});
      }
    });
    socket.onConnectError((error) {
      if (valid()) listener('connection.error', {'error': '$error'});
    });
    for (final event in [
      'sessions.state.snapshot',
      'sessions.state.updated',
      'app.event',
    ]) {
      socket.on(event, (data) {
        if (valid()) listener(event, decodeSocketPayload(data));
      });
    }
    socket.connect();
  }

  @override
  void requestState() {
    if (!connected) throw const ApiException('会话状态连接未就绪');
    // This protocol answers with a snapshot event; it has no ACK contract.
    _socket!.emit('sessions.state.request', {});
  }

  Future<Map<String, dynamic>> _ack(
    String event,
    Map<String, dynamic> data,
  ) async {
    if (!connected) throw const ApiException('会话状态连接未就绪');
    final generation = _generation, connection = _connection;
    final result = await _socket!
        .emitWithAckAsync(event, data)
        .timeout(ackTimeout);
    if (!connected || generation != _generation || connection != _connection) {
      throw const StaleProtocolResponse();
    }
    return decodeSocketPayload(result);
  }

  @override
  Future<Map<String, dynamic>> markRead(
    String id,
    int messageId,
    int attentionId,
  ) => _ack('sessions.read', {
    'sessionId': id,
    'messageId': messageId,
    'attentionId': attentionId,
  });
  @override
  Future<Map<String, dynamic>> subscribeRemovals() =>
      _ack('app.events.subscribe', {
        'schema_version': 1,
        'profile': _profile,
        'types': <String>[],
        'include_session_removals': true,
      });
  @override
  void dispose() {
    _generation++;
    _connection++;
    _identityValid = null;
    _socket?.dispose();
    _socket = null;
  }
}
