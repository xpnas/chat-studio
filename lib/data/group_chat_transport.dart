import 'dart:io';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'models.dart';
import 'studio_api.dart';

/// Dedicated transport for the Studio group-chat namespace. It intentionally
/// does not share the single-session chat socket: a group run can continue
/// while the user browses another single chat.
class GroupChatTransport {
  io.Socket? _socket;
  void Function(String event, Map<String, dynamic> data)? _onEvent;

  bool get connected => _socket?.connected == true;

  void connect(
    StudioApi api,
    void Function(String, Map<String, dynamic>) onEvent,
  ) {
    dispose();
    _onEvent = onEvent;
    final socket = io.io(
      '${api.address.value}/group-chat',
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .disableMultiplex()
          .setAuth({'token': api.token})
          .setQuery({
            'profile': api.profile,
            'platform': Platform.isIOS ? 'ios' : 'android',
          })
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(30000)
          .setTimeout(30000)
          .build(),
    );
    _socket = socket;
    socket.onConnect((_) => _emit('connected', const {}));
    socket.onDisconnect((_) => _emit('disconnected', const {}));
    socket.onConnectError(
      (error) => _emit('connection.error', {'error': '$error'}),
    );
    socket.onAny((event, data) => _emit(event, decodeSocketPayload(data)));
    socket.connect();
  }

  Future<Map<String, dynamic>> emitAck(
    String event,
    Map<String, dynamic> data,
  ) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      throw const ApiException('群聊连接尚未就绪，请稍后重试');
    }
    final response = await socket
        .emitWithAckAsync(event, data)
        .timeout(const Duration(seconds: 30));
    return decodeSocketPayload(response);
  }

  void emit(String event, Map<String, dynamic> data) {
    if (_socket?.connected != true) {
      throw const ApiException('群聊连接尚未就绪，请稍后重试');
    }
    _socket!.emit(event, data);
  }

  void _emit(String event, Map<String, dynamic> data) =>
      _onEvent?.call(event, data);

  void dispose() {
    _socket?.dispose();
    _socket = null;
    _onEvent = null;
  }
}

Map<String, dynamic> decodeSocketPayload(dynamic data) =>
    asMap(data is List && data.isNotEmpty ? data.first : data);
