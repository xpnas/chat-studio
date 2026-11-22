import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/session_tasks.dart';
import 'package:chatstudio/data/person_api.dart';
import 'package:chatstudio/data/message_selection.dart';
import 'package:chatstudio/data/protocol_capabilities.dart';
import 'package:chatstudio/state/app_controller.dart';
import 'package:chatstudio/state/session_tasks_controller.dart';
import 'support.dart';

void main() {
  final server = Platform.environment['CHATSTUDIO_TEST_SERVER'];
  test(
    'stable two clients reconcile goal status, cross-page evidence/source deletion and conflict',
    () async {
      final first = AppController(storage: MemoryStorage()),
          second = AppController(storage: MemoryStorage());
      String? id;
      Future<void> until(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 80));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail(
              'Goal condition timed out: ${first.error}; ${first.timeline.messages.map((m) => m.failure).join()}',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      try {
        for (final c in [first, second]) {
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
        await until(() => first.canSend);
        expect(first.send('SESSION_GOAL_CONTRACT'), true);
        id = first.sessionId;
        await until(
          () =>
              !first.working &&
              first.timeline.messages.any(
                (m) => m.role == 'assistant' && m.content.contains('本地协议自测'),
              ),
        );
        final api = first.api!, other = second.api!;
        final initial = await api.sessionGoals(sessionId: id);
        expect(initial.tasks.length, 1);
        final task = initial.tasks.single;
        expect(task.status, 'completed');
        expect(task.evidenceMessageId, isNotNull);
        final total = (await api.messages(id!)).total;
        expect(total, greaterThan(60));
        final source = await EvidenceLookup().locate(
          api,
          task,
          task.sourceMessageId!,
        );
        expect(source.$1, EvidenceResult.found);
        expect(source.$2!.id, '${task.sourceMessageId}');
        final state = SessionTasksController(other, sessionId: id);
        await state.refresh();
        var selection = await api.sessionMessageSelection(id);
        final evidenceGroup = selection.groups.singleWhere(
          (g) => g.messageIds.contains(task.evidenceMessageId),
        );
        expect(evidenceGroup.messageIds.length, greaterThan(60));
        final oldRevision = selection.historyRevision;
        first.draft.text = 'keep text through deletion';
        first.draft.uploaded.add(
          const MessageAttachment(
            name: 'draft.txt',
            path: '/local/draft.txt',
            mimeType: 'text/plain',
          ),
        );
        await other.deleteSessionMessages(
          id,
          evidenceGroup.messageIds,
          oldRevision,
        );
        await expectLater(
          api.deleteSessionMessages(id, evidenceGroup.messageIds, oldRevision),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
        await first.reconcileMessageDeletion(id);
        expect(first.draft.text, 'keep text through deletion');
        expect(first.draft.uploaded.single.name, 'draft.txt');
        final reopened = (await api.sessionGoals(sessionId: id)).tasks.single;
        expect(reopened.status, 'open');
        expect(reopened.evidenceMessageId, isNull);
        expect(reopened.completionEvidence, isEmpty);
        await state.refresh();
        await state.setStatus(state.tasks.single, 'closed');
        expect(state.tasks.single.status, 'closed');
        await expectLater(
          api.setGoalStatus(task, 'open'),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 409)),
        );
        final fresh = (await api.sessionGoals(sessionId: id)).tasks.single;
        await api.setGoalStatus(fresh, 'completed');
        await state.refresh();
        expect(state.tasks.single.status, 'completed');
        expect(
          (await api.messages(id)).messages.any((m) => m.role == 'assistant'),
          false,
        );
        selection = await api.sessionMessageSelection(id);
        final sourceGroup = selection.groups.singleWhere(
          (g) => g.messageIds.contains(task.sourceMessageId),
        );
        await api.deleteSessionMessages(
          id,
          sourceGroup.messageIds,
          selection.historyRevision,
        );
        await state.refresh();
        expect(state.tasks, isEmpty);
        expect((await other.messages(id)).total, 0);
        state.dispose();
      } finally {
        if (id != null) await first.api?.delete(id);
        first.dispose();
        second.dispose();
      }
    },
    skip:
        server == null ||
        Platform.environment['CHATSTUDIO_TEST_BASELINE'] == 'legacy',
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'legacy explicitly degrades user goals and message selection without changing run plans',
    () async {
      final c = AppController(storage: MemoryStorage());
      try {
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
        await expectLater(
          c.api!.sessionGoals(),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
        );
        expect(
          c.api!.capabilities[ProtocolCapability.sessionTasks],
          CapabilityState.unsupported,
        );
        await expectLater(
          c.api!.sessionMessageSelection('missing'),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
        );
        expect(
          c.api!.capabilities[ProtocolCapability.messageSelection],
          CapabilityState.unsupported,
        );
        await expectLater(
          c.api!.personConversations(c.account!.id),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
        );
        expect(
          c.api!.capabilities[ProtocolCapability.person],
          CapabilityState.unsupported,
        );
      } finally {
        c.dispose();
      }
    },
    skip:
        server == null ||
        Platform.environment['CHATSTUDIO_TEST_BASELINE'] != 'legacy',
  );
}
