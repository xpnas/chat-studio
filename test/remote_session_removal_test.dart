import 'dart:convert';
import 'package:chatstudio/data/mobile_media.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'support.dart';

Future<Conversation> openSeed(TestHarness h) async {
  await h.login();
  final conversation = h.controller.conversations.single;
  await h.controller.openConversation(conversation);
  h.transport.receive('resumed', {
    'session_id': conversation.id,
    'isWorking': false,
    'messages': [
      {'id': 1, 'role': 'user', 'content': 'Stored question'},
      {'id': 2, 'role': 'assistant', 'content': 'Stored reply'},
    ],
  });
  h.controller.draft.text = 'unsent draft';
  return conversation;
}

void main() {
  test(
    'archive retains identity, body and draft; temporary and ambiguous failures do not imply deletion',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final conversation = await openSeed(h);
      h.override = (r) async => r.url.path == '/api/studio/sessions/history-1'
          ? http.Response(
              jsonEncode({
                'session': {...conversation.toJson(), 'is_archived': true},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )
          : h.response(r);
      await h.controller.verifyRemoteSession(conversation.id);
      expect(h.controller.sessionId, conversation.id);
      expect(h.controller.timeline.messages.length, 2);
      expect(h.controller.draft.text, 'unsent draft');
      expect(h.controller.current!.isArchived, true);
      for (final status in [503, 404]) {
        h.override = (r) async => r.url.path == '/api/studio/sessions/history-1'
            ? http.Response('{"error":"Route unavailable"}', status)
            : h.response(r);
        await h.controller.verifyRemoteSession(conversation.id);
        expect(h.controller.sessionId, conversation.id);
        expect(h.controller.timeline.messages.length, 2);
        expect(h.controller.draft.text, 'unsent draft');
        expect(h.controller.recoverableDrafts, isEmpty);
      }
    },
  );
  for (final status in [403, 404]) {
    test(
      'confirmed HTTP $status detaches old session, preserves scope draft and prevents late list resurrection',
      () async {
        final h = TestHarness();
        addTearDown(h.dispose);
        final conversation = await openSeed(h);
        h.controller.draft.files.add(
          const LocalAttachment(
            path: '/local/pending.txt',
            name: 'pending.txt',
            size: 12,
            mimeType: 'text/plain',
          ),
        );
        h.controller.draft.uploaded.add(
          const MessageAttachment(
            name: 'uploaded.txt',
            path: '/remote/uploaded.txt',
            mimeType: 'text/plain',
          ),
        );
        h.override = (r) async => r.url.path == '/api/studio/sessions/history-1'
            ? http.Response(
                status == 404
                    ? '{"error":"Session not found"}'
                    : '{"error":"Forbidden"}',
                status,
              )
            : h.response(r);
        await h.controller.verifyRemoteSession(conversation.id);
        expect(h.controller.sessionId, isNull);
        expect(h.controller.timeline.messages, isEmpty);
        expect(
          h.controller.recoverableDrafts.single.draft.text,
          'unsent draft',
        );
        expect(
          h.controller.workspaceNotice,
          contains(status == 403 ? '权限' : '已删除'),
        );
        await h.controller.refreshSessions();
        expect(
          h.controller.conversations.where((row) => row.id == conversation.id),
          isEmpty,
        );
        await h.controller.openConversation(conversation);
        expect(h.controller.sessionId, isNull);
        expect(h.controller.recoverConversationDraft(conversation.id), true);
        expect(h.controller.draft.text, 'unsent draft');
        expect(h.controller.draft.files.single.name, 'pending.txt');
        expect(h.controller.draft.uploaded.single.name, 'uploaded.txt');
        expect(h.controller.sessionId, isNull);
        expect(
          h.transport.emitted.where((event) => event.$1 == 'run'),
          isEmpty,
        );
      },
    );
  }
  test(
    'removal notices coalesce, omit-reason does not delete, and recovery never crosses Profile or login',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      final conversation = await openSeed(h);
      var details = 0;
      h.override = (r) async {
        if (r.url.path == '/api/studio/sessions/history-1') {
          details++;
          return http.Response(
            jsonEncode({'session': conversation.toJson()}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return h.response(r);
      };
      await Future<void>.delayed(Duration.zero);
      for (var i = 0; i < 3; i++) {
        h.sessionSync.receive('app.event', {
          'schema_version': 1,
          'id': 'removed-$i',
          'type': 'chat.session.removed',
          'profile': 'default',
          'subject': {'session_id': conversation.id},
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(details, 1);
      expect(h.controller.timeline.messages.length, 2);
      h.override = (r) async => r.url.path == '/api/studio/sessions/history-1'
          ? http.Response('{"error":"Session not found"}', 404)
          : h.response(r);
      await h.controller.verifyRemoteSession(conversation.id);
      expect(h.controller.recoverableDrafts, hasLength(1));
      await h.controller.switchProfile('work');
      expect(h.controller.recoverableDrafts, isEmpty);
      expect(h.controller.recoverConversationDraft(conversation.id), false);
      await h.controller.switchProfile('default');
      expect(h.controller.recoverableDrafts, hasLength(1));
      await h.controller.logout();
      await h.login();
      expect(h.controller.recoverableDrafts, isEmpty);
    },
  );
  testWidgets(
    'recovery button restores a detached draft without submitting it',
    (tester) async {
      final h = TestHarness();
      final conversation = await openSeed(h);
      h.override = (r) async => r.url.path == '/api/studio/sessions/history-1'
          ? http.Response('{"error":"Session not found"}', 404)
          : h.response(r);
      await h.controller.verifyRemoteSession(conversation.id);
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(ValueKey('recover-draft:${conversation.id}')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        'unsent draft',
      );
      expect(h.transport.emitted.where((event) => event.$1 == 'run'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
