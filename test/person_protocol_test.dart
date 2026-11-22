import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/person_api.dart';
import 'package:chatstudio/data/person_models.dart';
import 'package:chatstudio/data/person_history_cache.dart';
import 'package:chatstudio/state/person_timeline.dart';
import 'package:chatstudio/state/person_operations.dart';
import 'package:chatstudio/state/person_flow_details_controller.dart';
import 'session_tasks_test.dart' show taskApi, jsonResponse;

Map<String, dynamic> personPage({
  String id = 'cache',
  int revision = 0,
  List<Map<String, dynamic>>? refs,
  List<Map<String, dynamic>> messages = const [],
  List<Map<String, dynamic>> cards = const [],
  String before = '',
  bool hasMore = false,
  bool reset = false,
}) => {
  'id': id,
  'projection': personProjection,
  'messages': messages,
  'personFlows': {
    'flows': [],
    'cards': cards,
    'timeline': {
      'items':
          refs ??
          [
            for (final m in messages)
              {
                'kind': 'message',
                'id': '${m['id']}',
                'timestamp': m['timestamp'] ?? 1,
                'cursor': 'cursor-${m['id']}',
              },
          ],
      'before': before,
      'has_more': hasMore,
      'history_revision': revision,
      'reset': reset,
    },
  },
};
Map<String, dynamic> flow(
  String id, {
  int revision = 1,
  String state = 'stopped',
}) => {
  'id': id,
  'revision': revision,
  'title': 'Flow $id',
  'state': state,
  'round_limit': 0,
  'round_number': 1,
  'stages': [],
};

void main() {
  test(
    'flow result lookup pages to exact stage/message and respects its bound',
    () async {
      var reads = 0;
      final api = taskApi((request) {
        reads++;
        return jsonResponse({
          'flow': flow('f'),
          'messages': [
            {
              'id': reads == 1 ? 8 : 7,
              'stage_id': 'wanted',
              'session_id': 'person-main-b',
              'role': 'assistant',
              'content': 'exact',
            },
          ],
          'history_key': 'one',
          'has_more': reads == 1,
          'next_before_id': 3,
        });
      });
      final c = PersonFlowDetailsController(api, 'f', () => true);
      await c.refresh();
      expect((await c.locate(7, 'wanted'))!['id'], 7);
      expect(reads, 2);
      expect(await c.locate(7, 'other', maxPages: 1), isNull);
      c.dispose();
      api.close();
    },
  );
  test(
    'BOT account ownership, next_offset and unknown task state preserve resource boundaries',
    () async {
      final api = taskApi(
        (r) => jsonResponse({
          'sessions': [
            {
              'id': 'person-main-own',
              'studio_user_id': 7,
              'profile': 'other',
              'title': 'Mine',
            },
            {'id': 'person-main-foreign', 'studio_user_id': 8},
            {'id': 'person-task-worker', 'studio_user_id': 7},
          ],
          'next_offset': 50,
        }),
      );
      final page = await api.personConversations(7);
      expect(page.sessions.map((s) => s.id), ['person-main-own']);
      expect(page.nextOffset, 50);
      final unknown = PersonTask.fromJson({
        'id': 't',
        'status': 'future',
        'execution_state': 'future',
        'revision': 18,
        'requirements_revision': 4,
      });
      expect(unknown.canFollowUp, false);
      expect(unknown.revision, 18);
      expect(unknown.requirementsRevision, 4);
      api.close();
    },
  );
  test(
    'durable interaction and all manual write preconditions use their own fields',
    () async {
      final calls = <Map<String, dynamic>>[];
      final api = taskApi((r) {
        calls.add(jsonDecode(r.body) as Map<String, dynamic>);
        return jsonResponse({'id': 'f', 'state': 'stopped', 'revision': 10});
      });
      final interaction = PersonInteraction.fromJson({
        'id': 'q',
        'revision': 6,
        'kind': 'approval',
        'state': 'pending',
      });
      expect(interaction.event['durable'], true);
      expect(interaction.event['allow_permanent'], false);
      expect(interaction.event.containsKey('timeout_ms'), false);
      await api.answerPersonInteraction(interaction, 'once');
      await api.continuePersonTask('t', {
        'input': [
          {'type': 'text', 'text': 'more'},
        ],
        'expected_revision': 3,
        'expected_execution_id': 'e',
        'idempotency_key': 'key',
      });
      await api.applyPersonFlow({
        'action': 'stop',
        'flow_id': 'f',
        'expected_revision': 8,
        'idempotency_key': 'flow-key',
      });
      expect(calls.first, {'expected_revision': 6, 'answer': 'once'});
      expect(calls[1]['expected_execution_id'], 'e');
      expect(calls.last['expected_revision'], 8);
      await expectLater(
        api.applyPersonFlow({'action': 'complete'}),
        throwsArgumentError,
      );
      api.close();
    },
  );
  test(
    'typed mixed IDs, card-only pages, overlap and flow revisions never use messageTotal',
    () {
      final timeline = PersonTimeline();
      final first = PersonTimelinePage.fromJson(
        personPage(
          refs: [
            {'kind': 'message', 'id': '7'},
            {'kind': 'flow', 'id': '7'},
          ],
          messages: [
            {'id': 7, 'role': 'assistant', 'content': 'Visible'},
          ],
          cards: [flow('7', revision: 4)],
          before: 'opaque',
          hasMore: true,
        ),
      );
      timeline.applyLatest(first);
      expect(timeline.items.length, 2);
      expect(timeline.visibleReadCursor, 7);
      timeline.beginReading();
      final older = PersonTimelinePage.fromJson(
        personPage(
          id: '',
          refs: [
            {'kind': 'flow', 'id': 'older'},
            {'kind': 'flow', 'id': '7'},
          ],
          cards: [flow('older'), flow('7', revision: 2)],
          before: 'next',
          hasMore: true,
        ),
      );
      timeline.prepend(older, timeline.generation);
      expect(timeline.items.map((i) => i.key), [
        'flow:older',
        'message:7',
        'flow:7',
      ]);
      expect(timeline.flows['7']!.revision, 4);
      expect(timeline.visibleReadCursor, isNull);
      expect(timeline.hasMore, true);
      expect(timeline.latest!.id, 'cache');
      final newer = PersonTimelinePage.fromJson(
        personPage(
          id: 'new',
          messages: [
            {'id': 9, 'role': 'assistant', 'content': 'new'},
          ],
        ),
      );
      timeline.applyLatest(newer);
      expect(timeline.items.first.id, 'older');
      expect(timeline.hasNewer, true);
      timeline.showLatest();
      expect(timeline.items.single.id, '9');
      expect(
        () => PersonTimelinePage.fromJson({
          ...personPage(),
          'projection': 'future',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'history generations clear references while flow-only revisions retain the reading window',
    () {
      final timeline = PersonTimeline();
      timeline.applyLatest(
        PersonTimelinePage.fromJson(
          personPage(
            messages: [
              {'id': 1, 'role': 'assistant', 'content': 'old'},
            ],
          ),
        ),
      );
      final generation = timeline.generation;
      timeline.beginReading();
      timeline.mergeFlows([PersonFlow.fromJson(flow('f', revision: 10))]);
      expect(timeline.generation, generation);
      timeline.applyLatest(
        PersonTimelinePage.fromJson(personPage(id: 'clear', revision: 1)),
      );
      expect(timeline.items, isEmpty);
      expect(timeline.generation, greaterThan(generation));
      expect(
        timeline.prepend(
          PersonTimelinePage.fromJson(
            personPage(
              messages: [
                {'id': 1, 'role': 'assistant', 'content': 'late'},
              ],
            ),
          ),
          generation,
        ),
        false,
      );
      expect(timeline.items, isEmpty);
    },
  );
  test(
    'cache is atomic, scoped, projected and bounded; interrupted publish retains prior full page',
    () async {
      final root = await Directory.systemTemp.createTemp('person-cache-');
      addTearDown(() => root.delete(recursive: true));
      final cache = PersonHistoryCache(
        root,
        'server',
        'account',
        'person-main-a',
      );
      final page = personPage(
        messages: [
          {'id': 1, 'role': 'user', 'content': 'first'},
        ],
      );
      await cache.write({
        'latest': page,
        'window': [page],
      });
      await expectLater(
        cache.write(
          {'latest': personPage(id: 'broken'), 'window': []},
          beforePublish: () async {
            throw StateError('interrupted');
          },
        ),
        throwsStateError,
      );
      expect(asMap((await cache.read())!['latest'])['id'], 'cache');
      expect(
        await PersonHistoryCache(
          root,
          'server',
          'other-account',
          'person-main-a',
        ).read(),
        isNull,
      );
      expect(
        await PersonHistoryCache(
          root,
          'other-server',
          'account',
          'person-main-a',
        ).read(),
        isNull,
      );
      await cache.file.writeAsString('{broken');
      expect(await cache.read(), isNull);
      cache.close();
    },
  );
  test(
    'window evicts complete newest pages at 300 refs and preserves exact latest cache ID',
    () {
      PersonTimelinePage page(int start) => PersonTimelinePage.fromJson(
        personPage(
          id: 'page-$start',
          messages: [
            for (var i = start; i < start + 150; i++)
              {'id': i, 'role': 'assistant', 'content': '$i'},
          ],
          before: 'before-$start',
          hasMore: true,
        ),
      );
      final c = PersonTimeline();
      c.applyLatest(page(451));
      c.prepend(page(301), c.generation);
      c.prepend(page(151), c.generation);
      expect(c.items.length, 150);
      expect(c.items.first.id, '151');
      expect(c.items.last.id, '300');
      expect(
        {
          ...c.latest!.items.map((i) => i.key),
          ...c.items.map((i) => i.key),
        }.length,
        300,
      );
      expect(c.latest!.id, 'page-451');
      expect(c.before, 'before-151');
      expect(c.cacheData()!['latest'], c.latest!.raw);
    },
  );
  test(
    'unknown operations preserve key and payload, refuse changed retries and never replay on refresh',
    () async {
      var calls = 0;
      Map<String, dynamic>? saved;
      final inputs = <Map<String, dynamic>>[];
      final operation = PersonOperation(
        persist: (journal) async {
          saved = journal;
        },
        valid: () => true,
      );
      Future<Map<String, dynamic>> send(Map<String, dynamic> input) async {
        calls++;
        inputs.add(input);
        if (calls == 1) throw const ApiException('lost');
        return {'id': 'one'};
      }

      final input = {'action': 'create', 'title': 'One'};
      await operation.perform('flow', input, send);
      expect(operation.uncertain, true);
      expect(saved, isNotNull);
      await operation.perform(
        'flow',
        {'action': 'create', 'title': 'Different'},
        send,
        retry: true,
      );
      expect(calls, 1);
      final key = operation.payload!['idempotency_key'];
      await operation.perform('flow', input, send, retry: true);
      expect(calls, 2);
      expect(inputs.last['idempotency_key'], key);
      expect(saved, isNull);
      operation.dispose();
    },
  );
  test(
    'flow details advance on hidden empty pages and history_key invalidates old details',
    () async {
      final cursors = <String?>[];
      var generation = 0;
      final api = taskApi((r) {
        cursors.add(r.url.queryParameters['before_id']);
        return jsonResponse({
          'flow': flow('f'),
          'messages': cursors.length == 2
              ? [
                  {
                    'id': 1,
                    'role': 'assistant',
                    'content': 'Authorized',
                    'session_id': 'person-main-b',
                    'stage_id': 'stage',
                    'round_number': 1,
                  },
                ]
              : [],
          'has_more': cursors.length == 1,
          'next_before_id': 3,
          'history_key': 'history-$generation',
        });
      });
      final c = PersonFlowDetailsController(api, 'f', () => true);
      await c.refresh();
      expect(c.messages, isEmpty);
      expect(c.hasMore, true);
      await c.refresh(more: true);
      expect(cursors.last, '3');
      expect(c.messages.single['round_number'], 1);
      generation++;
      await c.refresh();
      expect(c.messages, isEmpty);
      expect(c.historyKey, 'history-1');
      c.dispose();
      api.close();
    },
  );
  test(
    'flow form validates contiguous groups, finite rounds and both self-handoff boundaries',
    () {
      const auth = {'a', 'b', 'c'};
      PersonFlowDraft draft(
        List<({String sessionId, String goal, String expectation, int group})>
        stages, {
        int rounds = 1,
      }) => PersonFlowDraft(
        creator: 'a',
        title: 'Route',
        goal: 'Outcome',
        stages: stages,
        rounds: rounds,
      );
      final b = (sessionId: 'b', goal: 'work', expectation: 'result', group: 0),
          c = (sessionId: 'c', goal: 'review', expectation: 'report', group: 1);
      expect(draft([b, c], rounds: 1000).validate(auth), isNull);
      expect(draft([b, c], rounds: 0).validate(auth), isNotNull);
      expect(draft([b, b]).validate(auth), isNotNull);
      expect(
        draft([
          (sessionId: 'a', goal: 'x', expectation: 'y', group: 0),
        ]).validate(auth),
        isNotNull,
      );
      expect(
        draft([
          b,
          c,
          (sessionId: 'b', goal: 'x', expectation: 'y', group: 2),
        ], rounds: 2).validate(auth),
        isNotNull,
      );
    },
  );
}
