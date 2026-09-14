import 'dart:io';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'models.dart';
import 'studio_api.dart';

typedef SocketEvent = void Function(String event, Map<String, dynamic> data);

abstract class ChatTransport {
  void connect(StudioApi api, SocketEvent onEvent);
  void emit(String event, Map<String, dynamic> data);
  void dispose();
}

class SocketChatTransport implements ChatTransport {
  io.Socket? _socket;
  @override
  void connect(StudioApi api, SocketEvent onEvent) {
    dispose();
    final socket = io.io(
      '${api.address.value}/chat-run',
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
          .setReconnectionDelayMax(10000)
          .setTimeout(15000)
          .build(),
    );
    _socket = socket;
    socket.onConnect((_) => onEvent('connected', {}));
    socket.onDisconnect((_) => onEvent('disconnected', {}));
    socket.onConnectError(
      (error) => onEvent('connection.error', {'error': '$error'}),
    );
    // Socket.IO connection-state recovery appends an offset as a second argument.
    socket.onAny((event, data) => onEvent(event, decodeSocketPayload(data)));
    socket.connect();
  }

  @override
  void emit(String event, Map<String, dynamic> data) {
    // Never queue run/approval events offline: reconnect must not duplicate actions.
    if (_socket?.connected != true) throw const ApiException('聊天连接尚未就绪，请重试连接');
    _socket!.emit(event, data);
  }

  @override
  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}

Map<String, dynamic> decodeSocketPayload(dynamic data) =>
    asMap(data is List && data.isNotEmpty ? data.first : data);
