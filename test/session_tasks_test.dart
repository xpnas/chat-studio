import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/protocol_capabilities.dart';
import 'package:chatstudio/data/session_tasks.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/state/session_tasks_controller.dart';

Map<String, dynamic> goal(
  String id, {
  String status = 'open',
  int updated = 1700000000001,
}) => {
  'id': id,
  'title': 'Goal $id',
  'summary': 'Persistent goal',
  'session_id': 's',
  'session_title': 'Session',
  'profile': 'work',
  'source_message_id': 7,
  'evidence_message_id': 9,
  'completion_evidence': 'proof',
  'status': status,
  'updated_at': updated,
};
http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
StudioApi taskApi(FutureOr<http.Response> Function(http.Request) handler) =>
    StudioApi(
        ServerAddress.parse('http://localhost:8080', allowLocalHttp: true),
        client: MockClient((request) async => handler(request)),
      )
      ..token = 'account'
      ..profile = 'work';

void main() {
  test(
    'authorized queries and exact timestamp PATCH keep three version types distinct',
    () async {
      final calls = <http.Request>[];
      final api = taskApi((r) {
        calls.add(r);
        return r.method == 'PATCH'
            ? jsonResponse({
                'session_id': 's',
                'revision': 8,
                'tasks': [goal('one', status: 'completed')],
              })
            : jsonResponse({
                'tasks': [goal('one')],
                'total': 9,
                'has_more': true,
              });
      });
      final page = await api.sessionGoals(
        status: 'completed',
        search: 'finish',
        order: 'oldest',
        offset: 50,
        limit: 10,
        allProfiles: true,
      );
      expect(calls.single.url.queryParameters, {
        'profile': '',
        'status': 'completed',
        'search': 'finish',
        'order': 'oldest',
        'offset': '50',
        'limit': '10',
      });
      expect(page.total, 9);
      expect(page.hasMore, true);
      final snapshot = await api.setGoalStatus(page.tasks.single, 'completed');
      expect(snapshot.revision, 8);
      expect(snapshot.tasks.single.status, 'completed');
      expect(jsonDecode(calls.last.body), {
        'status': 'completed',
        'expected_updated_at': 1700000000001,
      });
      expect(calls.last.url.path, '/api/studio/sessions/s/tasks/one/status');
      expect(
        calls.every(
          (r) =>
              !r.url.path.endsWith('/list') && !r.url.path.endsWith('/update'),
        ),
        true,
      );
      api.close();
    },
  );
  test(
    'missing capability, missing resource, forbidden and empty are different',
    () async {
      for (final status in [200, 403, 404, 501]) {
        final api = taskApi(
          (r) => jsonResponse(
            status == 200
                ? {'tasks': [], 'total': 0, 'has_more': false}
                : {'error': status == 404 ? 'Session not found' : 'Not Found'},
            status,
          ),
        );
        if (status == 200) {
          expect((await api.sessionGoals()).tasks, isEmpty);
        } else {
          await expectLater(api.sessionGoals(), throwsA(isA<ApiException>()));
        }
        expect(
          api.capabilities[ProtocolCapability.sessionTasks],
          status == 200
              ? CapabilityState.supported
              : status == 501
              ? CapabilityState.unsupported
              : status == 404
              ? CapabilityState.unknown
              : CapabilityState.unavailable,
        );
        api.close();
      }
    },
  );
  test(
    'filter generations reject old pages, duplicate pages use raw offset, permission withdraws data',
    () async {
      final old = Completer<http.Response>();
      var index = 0;
      final offsets = <String?>[];
      final api = taskApi((r) {
        offsets.add(r.url.queryParameters['offset']);
        index++;
        if (index == 1) return old.future;
        if (index == 4) return jsonResponse({'error': 'Forbidden'}, 403);
        return jsonResponse({
          'tasks': [goal('new', status: 'completed')],
          'total': 2,
          'has_more': index == 2,
        });
      });
      final c = SessionTasksController(api);
      final first = c.refresh();
      await c.filter(status: 'completed');
      old.complete(
        jsonResponse({
          'tasks': [goal('old')],
          'total': 5,
          'has_more': true,
        }),
      );
      await first;
      expect(c.tasks.map((g) => g.id), ['new']);
      await c.refresh(more: true);
      expect(c.tasks.length, 1);
      expect(offsets.last, '1');
      await c.refresh();
      expect(c.tasks, isEmpty);
      expect(c.error, contains('Forbidden'));
      c.dispose();
      api.close();
    },
  );
  test(
    'status conflict refreshes once without write replay; unknown requires read reconciliation',
    () async {
      var writes = 0, reads = 0, unknown = false;
      final api = taskApi((r) {
        if (r.method == 'PATCH') {
          writes++;
          if (unknown) throw http.ClientException('lost response');
          return jsonResponse({'error': 'changed'}, 409);
        }
        reads++;
        return jsonResponse({
          'tasks': [goal('one', updated: reads)],
          'total': 1,
          'has_more': false,
        });
      });
      final c = SessionTasksController(api);
      await c.refresh();
      await c.setStatus(c.tasks.single, 'completed');
      expect(writes, 1);
      expect(reads, 2);
      expect(c.notice, contains('已变化'));
      expect(c.tasks.single.updatedAt, 2);
      unknown = true;
      await c.setStatus(c.tasks.single, 'closed');
      expect(c.uncertain, isNotEmpty);
      await c.setStatus(c.tasks.single, 'closed');
      expect(writes, 2);
      await c.refresh();
      expect(c.uncertain, isEmpty);
      expect(writes, 2);
      c.dispose();
      api.close();
    },
  );
  test(
    'evidence lookup finds exact old page and supports cancellation, limit and denied resources',
    () async {
      final api = taskApi(
        (r) => jsonResponse({
          'messages': [
            {
              'id': r.url.queryParameters['offset'] == '0' ? 10 : 7,
              'role': 'user',
              'content': 'exact evidence',
            },
          ],
          'hasMore': r.url.queryParameters['offset'] == '0',
        }),
      );
      final lookup = EvidenceLookup(), task = SessionGoal.fromJson(goal('one'));
      expect((await lookup.locate(api, task, 7)).$1, EvidenceResult.found);
      expect(
        (await lookup.locate(api, task, 7, maxPages: 1)).$1,
        EvidenceResult.limit,
      );
      final delayed = Completer<http.Response>();
      final other = taskApi((r) => delayed.future);
      final pending = lookup.locate(other, task, 7);
      lookup.cancel();
      delayed.complete(
        jsonResponse({
          'messages': [
            {'id': 7, 'role': 'user', 'content': 'late'},
          ],
          'hasMore': false,
        }),
      );
      expect((await pending).$1, EvidenceResult.cancelled);
      final denied = taskApi((r) => jsonResponse({'error': 'denied'}, 403));
      expect(
        (await lookup.locate(denied, task, 7)).$1,
        EvidenceResult.forbidden,
      );
      api.close();
      other.close();
      denied.close();
    },
  );
}
