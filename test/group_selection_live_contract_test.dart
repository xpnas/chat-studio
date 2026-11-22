import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/message_selection.dart';
import 'package:chatstudio/state/app_controller.dart';
import 'package:chatstudio/state/group_chat_controller.dart';
import 'support.dart';

void main() {
  final server = Platform.environment['CHATSTUDIO_TEST_SERVER'];
  test(
    'real group paging, two-client opaque conflicts and unknown summary protection',
    () async {
      final app = AppController(storage: MemoryStorage()),
          other = AppController(storage: MemoryStorage());
      GroupChatController? first, second;
      String? id;
      try {
        for (final c in [app, other]) {
          await c.initialize();
          expect(
            await c.login(
              server!,
              'admin',
              Platform.environment['CHATSTUDIO_TEST_PASSWORD']!,
              true,
            ),
            true,
          );
        }
        final api = app.api!;
        final created = await api.request(
          '/api/studio/group-chat/rooms',
          method: 'POST',
          body: {
            'name': 'Mobile selection contract',
            'inviteCode': 'mobile-${DateTime.now().microsecondsSinceEpoch}',
            'agents': [],
          },
        );
        final room = GroupRoom.fromJson(asMap(created['room']));
        id = room.id;
        expect(id, isNotEmpty);
        first = GroupChatController(api: api, room: room);
        second = GroupChatController(api: other.api!, room: room);
        await first.start();
        await second.start();
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!first.canSend || !second.canSend) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Group join failed: ${first.error}, ${second.error}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        for (var i = 0; i < 155; i++) {
          expect(await first.send('Record $i'), true);
        }
        final page = await api.groupRoomDetail(id, limit: 150);
        expect(page.messages.length, 150);
        expect(page.hasMore, true);
        final older = await api.groupRoomDetail(
          id,
          before: page.messages.first.id,
          history: true,
        );
        expect(older.messages.length, 5);
        if (Platform.environment['CHATSTUDIO_TEST_BASELINE'] == 'legacy') {
          await expectLater(
            api.groupMessageSelection(id),
            throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
          );
          expect((await other.api!.groupRoomDetail(id)).total, 155);
          return;
        }
        final selection = await api.groupMessageSelection(id),
            stale = await other.api!.groupMessageSelection(id);
        final ids = [
          selection.groups.first.messageIds.single,
          selection.groups.last.messageIds.single,
        ];
        expect(selection.groups.length, 155);
        expect(selection.historyRevision, isA<String>());
        first.draft.text = 'group draft';
        await api.deleteGroupMessages(id, ids, selection.historyRevision);
        await expectLater(
          other.api!.deleteGroupMessages(id, ids, stale.historyRevision),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
        await first.start();
        expect(first.draft.text, 'group draft');
        expect((await other.api!.groupRoomDetail(id)).total, 153);
        await api.request(
          '/api/studio/group-chat/rooms/$id/summary',
          method: 'PUT',
          body: {
            'summary': 'Manually supplied summary without a provable boundary',
          },
        );
        final protected = await other.api!.groupMessageSelection(id);
        expect(
          protected.groups.every(
            (g) =>
                !g.selectable && g.blockedReason == 'summary_boundary_unknown',
          ),
          true,
        );
        await expectLater(
          api.deleteGroupMessages(
            id,
            protected.groups.first.messageIds,
            protected.historyRevision,
          ),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
        expect((await api.groupRoomDetail(id)).total, 153);
      } finally {
        first?.dispose();
        second?.dispose();
        if (id != null) {
          await app.api?.request(
            '/api/studio/group-chat/rooms/$id',
            method: 'DELETE',
          );
        }
        app.dispose();
        other.dispose();
      }
    },
    skip: server == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
