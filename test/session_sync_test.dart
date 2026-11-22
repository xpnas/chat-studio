import 'dart:async';
import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/session_sync_transport.dart';
import 'package:chatstudio/data/protocol_capabilities.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/state/session_sync_controller.dart';
import 'package:chatstudio/state/session_sync_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'support.dart';

class ProbeSocket implements io.Socket {
  @override
  bool connected = false;
  final handlers = <String, Function>{};
  final emitted = <(String, Map<String, dynamic>)>[];
  Completer<dynamic>? pendingAck;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final args = invocation.positionalArguments;
    if (invocation.memberName == #on) {
      handlers[args[0] as String] = args[1] as Function;
      return () => handlers.remove(args[0]);
    }
    if (invocation.memberName == #connect) {
      connected = true;
      handlers['connect']?.call(null);
      return this;
    }
    if (invocation.memberName == #dispose) {
      connected = false;
      return this;
    }
    if (invocation.memberName == #emit ||
        invocation.memberName == #emitWithAckAsync) {
      emitted.add((
        args[0] as String,
        Map<String, dynamic>.from(args[1] as Map),
      ));
      if (invocation.memberName == #emitWithAckAsync) {
        return pendingAck?.future ??
            Future<dynamic>.value({'ok': true, 'schema_version': 1});
      }
      return this;
    }
    return super.noSuchMethod(invocation);
  }
}

Map<String, dynamic> row(
  String id, {
  String profile = 'default',
  dynamic working = false,
  bool unread = true,
}) => {
  'sessionId': id,
  'profile': profile,
  'working': working,
  'unread': unread,
  'backgroundPending': 0,
  'lastMessageId': 10,
  'readMessageId': 0,
  'lastAttentionId': 2,
  'readAttentionId': 0,
};
void main() {
  test(
    'observer wire uses an independent connection and only read/state/subscription operations',
    () async {
      final socket = ProbeSocket();
      late Map<String, dynamic> options;
      final transport = SocketSessionSyncTransport(
        socketFactory: (uri, opts) {
          expect(uri, 'https://example.test/chat-run');
          options = opts;
          return socket;
        },
      );
      final api = StudioApi(ServerAddress.parse('https://example.test'))
        ..token = 'token'
        ..profile = 'work';
      addTearDown(api.close);
      addTearDown(transport.dispose);
      final events = <String>[];
      transport.connect(api, (event, _) => events.add(event));
      expect(options['forceNew'], true);
      expect(options['multiplex'], false);
      expect(options['query'], {'profile': 'work', 'session_state': '1'});
      expect(options['auth'], {'token': 'token'});
      transport.requestState();
      await transport.subscribeRemovals();
      await transport.markRead('s', 10, 2);
      expect(socket.emitted.map((event) => event.$1), [
        'sessions.state.request',
        'app.events.subscribe',
        'sessions.read',
      ]);
      expect(socket.emitted[1].$2['profile'], 'work');
      final old = socket.handlers['sessions.state.snapshot']!;
      api.profile = 'other';
      old({
        'sessions': [row('old')],
      });
      expect(events, ['connected']);
    },
  );
  test(
    'late observer ACK cannot apply after identity or connection changes',
    () async {
      final socket = ProbeSocket()..pendingAck = Completer<dynamic>();
      final transport = SocketSessionSyncTransport(
        socketFactory: (_, _) => socket,
      );
      final api = StudioApi(ServerAddress.parse('https://example.test'));
      addTearDown(api.close);
      addTearDown(transport.dispose);
      transport.connect(api, (_, _) {});
      final pending = transport.markRead('s', 10, 2);
      final assertion = expectLater(
        pending,
        throwsA(isA<StaleProtocolResponse>()),
      );
      transport.dispose();
      socket.pendingAck!.complete({'ok': true});
      await assertion;
    },
  );
  test(
    'snapshot plus delta is scoped, ignores private/BOT rows and old generations, and keeps unknown working unknown',
    () {
      final state = SessionSyncState();
      final old = state.reset('default');
      expect(state.update(old, row('before')), false);
      state.snapshot(old, [
        row('a'),
        row('b', profile: 'work'),
        row('person-task-private'),
        row('person-main-bot'),
        row('unknown', working: 'future'),
      ]);
      expect(state.sessions.keys, ['a', 'unknown']);
      expect(state.sessions['unknown']!.working, isNull);
      state.update(old, row('a', working: true));
      expect(state.sessions['a']!.working, true);
      state.reset('work');
      expect(state.snapshot(old, [row('old')]), false);
      expect(state.sessions, isEmpty);
    },
  );
  test(
    'legacy timeout degrades only observation and foreground refresh coalesces and retries',
    () async {
      final transport = FakeSessionSyncTransport(autoSnapshot: false);
      final controller = SessionSyncController(
        transport,
        confirmationTimeout: const Duration(milliseconds: 5),
        refreshDelay: const Duration(milliseconds: 1),
      );
      final api = StudioApi(ServerAddress.parse('https://example.test'));
      addTearDown(controller.dispose);
      addTearDown(api.close);
      controller.connect(api);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.state, CapabilityState.unavailable);
      controller.refresh();
      controller.refresh();
      controller.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 3));
      expect(transport.requests, 1);
      transport.receive('sessions.state.snapshot', {
        'sessions': [row('a')],
      });
      expect(controller.confirmed, true);
    },
  );
  test(
    'read ACK failures, hidden attention, background, old windows and concurrent receipts preserve unread',
    () async {
      final transport = FakeSessionSyncTransport()..sessions = [row('a')];
      final controller = SessionSyncController(transport);
      final api = StudioApi(ServerAddress.parse('https://example.test'));
      addTearDown(controller.dispose);
      addTearDown(api.close);
      controller.connect(api);
      Future<bool> read({
        bool foreground = true,
        bool latest = true,
        bool working = false,
        bool unseen = false,
        int message = 10,
        int attention = 2,
      }) => controller.readVisible(
        id: 'a',
        messageId: message,
        attentionId: attention,
        foreground: foreground,
        atLatest: latest,
        working: working,
        hasUnseenAttention: unseen,
      );
      expect(await read(foreground: false), false);
      expect(await read(latest: false), false);
      expect(await read(working: true), false);
      expect(await read(unseen: true), false);
      expect(await read(message: 11), false);
      expect(transport.reads, isEmpty);
      transport.readReply = () async => {'ok': false};
      expect(await read(), false);
      expect(controller.projection.sessions['a']!.unread, true);
      final pendingAck = Completer<Map<String, dynamic>>();
      transport.readReply = () => pendingAck.future;
      final pending = read();
      expect(await read(message: 9), false);
      pendingAck.complete({'ok': true});
      expect(await pending, true);
      final count = transport.reads.length;
      expect(await read(message: 9), true);
      expect(transport.reads.length, count);
      // Only authoritative observer updates clear unread, never an optimistic ACK.
      expect(controller.projection.sessions['a']!.unread, true);
      transport.receive('sessions.state.updated', row('a', unread: false));
      expect(controller.projection.sessions['a']!.unread, false);
    },
  );
  test(
    'removals require subscription ACK, schema, scope and unique event IDs',
    () async {
      final transport = FakeSessionSyncTransport();
      final controller = SessionSyncController(transport);
      final api = StudioApi(ServerAddress.parse('https://example.test'));
      addTearDown(controller.dispose);
      addTearDown(api.close);
      final removals = <String>[];
      controller.onRemoval = removals.add;
      controller.connect(api);
      await Future<void>.delayed(Duration.zero);
      final event = {
        'schema_version': 1,
        'id': 'e',
        'type': 'chat.session.removed',
        'profile': 'default',
        'subject': {'session_id': 'a'},
      };
      transport.receive('app.event', event);
      transport.receive('app.event', event);
      transport.receive('app.event', {
        ...event,
        'id': 'other',
        'profile': 'other',
      });
      expect(removals, ['a']);
      transport.receive('disconnected', {});
      transport.receive('connected', {});
      transport.receive('sessions.state.snapshot', {'sessions': []});
      await Future<void>.delayed(Duration.zero);
      transport.receive('app.event', event);
      expect(removals, ['a']);
      final oldListener = transport.listener!;
      controller.disconnect();
      oldListener('app.event', {...event, 'id': 'late'});
      expect(removals, ['a']);
    },
  );
}
