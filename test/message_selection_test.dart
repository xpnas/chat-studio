import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/message_selection.dart';
import 'package:chatstudio/state/message_selection_controller.dart';
import 'package:chatstudio/ui/message_selection_screen.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'session_tasks_test.dart' show taskApi, jsonResponse;

void main() {
  for (final role in ['user', 'assistant']) {
    testWidgets(
      'long press $role text retains copy and offers server-group message selection',
      (tester) async {
        var selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: ChatMessage(
                  id: '1',
                  role: role,
                  content: 'Long press this text',
                ),
                onSelectMessage: () => selected++,
              ),
            ),
          ),
        );
        await tester.longPress(find.text('Long press this text'));
        await tester.pumpAndSettle();
        expect(find.text('选择消息'), findsOneWidget);
        await tester.tap(find.text('选择消息'));
        expect(selected, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'single numeric and group opaque identity/revision stay exact and invalid schemas fail',
    () async {
      final calls = <Object>[];
      final api = taskApi((r) {
        if (r.method == 'POST') {
          calls.add(jsonDecode(r.body));
          return jsonResponse({'deleted': 2});
        }
        return jsonResponse(
          r.url.path.contains('group-chat')
              ? {
                  'groups': [
                    {
                      'id': 'a',
                      'kind': 'run',
                      'messageIds': ['a', 'hidden'],
                    },
                  ],
                  'historyRevision': 'opaque-001',
                }
              : {
                  'groups': [
                    {
                      'id': 7,
                      'kind': 'run',
                      'messageIds': [7, 8],
                    },
                  ],
                  'historyRevision': 9,
                },
        );
      });
      final single = await api.sessionMessageSelection('s'),
          group = await api.groupMessageSelection('g');
      await api.deleteSessionMessages(
        's',
        single.groups.single.messageIds,
        single.historyRevision,
      );
      await api.deleteGroupMessages(
        'g',
        group.groups.single.messageIds,
        group.historyRevision,
      );
      expect(calls, [
        {
          'messageIds': [7, 8],
          'historyRevision': 9,
        },
        {
          'messageIds': ['a', 'hidden'],
          'historyRevision': 'opaque-001',
        },
      ]);
      expect(
        () => MessageSelection.parse<int, int>(
          {
            'groups': [
              {
                'id': 1,
                'kind': 'run',
                'messageIds': ['1'],
              },
            ],
            'historyRevision': 1,
          },
          (id) => true,
          (v) => true,
        ),
        throwsFormatException,
      );
      expect(
        supportsSessionSelection(
          const Conversation(
            id: 'person-main-a',
            title: 'BOT',
            agent: 'ekko-agent',
            source: 'builtin_agent',
          ),
        ),
        false,
      );
      expect(
        supportsSessionSelection(
          const Conversation(
            id: 's',
            title: 'CLI',
            agent: 'codex',
            source: 'cli',
          ),
        ),
        false,
      );
      api.close();
    },
  );
  test(
    'complete groups selected atomically, unknown blocked reason disables group',
    () async {
      final c = MessageSelectionController<int, int>(
        read: () async => const MessageSelection([
          MessageSelectionGroup(1, 'run', [1, 2, 3], ''),
          MessageSelectionGroup(4, 'run', [
            4,
            5,
          ], 'compression_boundary_unknown'),
          MessageSelectionGroup(6, 'run', [6], 'future_reason'),
        ], 10),
        remove: (ids, rev) async => {},
        reconcile: () async {},
        valid: () => true,
      );
      await c.refresh();
      c.toggle(1);
      c.toggle(4);
      c.toggle(6);
      expect(c.messageIds, [1, 2, 3]);
      expect(c.selected.length, 1);
      c.cancel();
      expect(c.messageIds, isEmpty);
      c.dispose();
    },
  );
  test(
    '409 and busy clear stale choices, never retry or stop; unknown read reconciliation',
    () async {
      var writes = 0, reconciles = 0, unknown = false;
      final c = MessageSelectionController<int, int>(
        read: () async => const MessageSelection([
          MessageSelectionGroup(1, 'run', [1, 2], ''),
        ], 7),
        remove: (ids, rev) async {
          writes++;
          expect(rev, 7);
          if (unknown) throw Exception('lost');
          throw const ApiException('busy', 409);
        },
        reconcile: () async {
          reconciles++;
        },
        valid: () => true,
      );
      await c.refresh();
      c.toggle(1);
      expect(await c.deleteConfirmed(), false);
      expect(c.snapshot, isNull);
      expect(c.selected, isEmpty);
      expect(writes, 1);
      expect(reconciles, 1);
      await c.refresh();
      c.toggle(1);
      unknown = true;
      await c.deleteConfirmed();
      expect(c.uncertain, true);
      await c.deleteConfirmed();
      expect(writes, 2);
      await c.refresh();
      expect(c.uncertain, false);
      expect(reconciles, 2);
      expect(writes, 2);
      c.dispose();
    },
  );
  testWidgets(
    'confirmation reports hidden members and cancellation sends no deletion',
    (tester) async {
      var writes = 0;
      final c = MessageSelectionController<int, int>(
        read: () async => const MessageSelection([
          MessageSelectionGroup(1, 'run', [1, 2, 3], ''),
        ], 7),
        remove: (ids, rev) async {
          writes++;
          return {};
        },
        reconcile: () async {},
        valid: () => true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MessageSelectionScreen(
            title: 'Session',
            controller: c,
            messages: const [
              ChatMessage(id: '1', role: 'assistant', content: 'Visible'),
            ],
            initialMessageId: '1',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除 1 组 / 3 条记录'));
      await tester.pumpAndSettle();
      expect(find.textContaining('包含 2 条未展示或跨页记录'), findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(c.messageIds, [1, 2, 3]);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
