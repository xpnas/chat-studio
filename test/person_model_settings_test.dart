import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:chatstudio/data/person_api.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/state/person_controller.dart';
import 'package:chatstudio/ui/person_screens.dart';
import 'package:chatstudio/ui/person_create_screen.dart';
import 'package:chatstudio/ui/widgets/person_model_picker.dart';
import 'package:chatstudio/ui/widgets/conversation_drawer.dart';
import 'package:chatstudio/data/models.dart';
import 'person_widgets_test.dart' show widgetPerson;
import 'person_protocol_test.dart' show personPage;
import 'session_tasks_test.dart' show taskApi, jsonResponse;
import 'support.dart';

class ModelFixture {
  int revision = 4;
  Object owner = 7;
  Map<String, dynamic> model = {
    'profile': 'work',
    'provider': 'shared',
    'model': 'alpha',
    'apiMode': 'anthropic_messages',
  };
  final writes = <Map<String, dynamic>>[];
  final creations = <Map<String, dynamic>>[];
  int? reject;
  bool failCatalog = false;
  Completer<http.Response>? pendingWrite;
  bool failCreate = false;
  Map<String, dynamic> get catalog => {
    'groups': [
      for (final profile in ['work', 'other'])
        {
          'profile': profile,
          'provider': 'shared',
          'label': 'Shared provider',
          'models': ['alpha', 'beta', 'disabled'],
          'api_mode': 'anthropic_messages',
          'api_key': 'catalog-secret-must-not-be-retained',
          'model_meta': {
            'alpha': {'alias': '$profile Alpha'},
            'beta': {'alias': '$profile Beta'},
            'disabled': {'disabled': true},
          },
        },
    ],
  };
  Map<String, dynamic> get snapshot => {
    'session': {
      'id': 'person-main-a',
      'studio_user_id': 7,
      'title': 'Configured BOT',
      'profile': model['profile'],
    },
    'revision': revision,
    'settings': {
      'model': model,
      'agents': [
        {'id': 'worker'},
      ],
      'workspace': '/bot/work',
    },
    'tasks': [],
    'interactions': [],
    'history_revision': 0,
  };
  Future<http.Response?> handle(http.Request r) async {
    switch (r.url.path) {
      case '/api/app/profiles':
        return jsonResponse({
          'profiles': ['work', 'other', 'default'],
        });
      case '/api/studio/person/models':
        return failCatalog
            ? jsonResponse({'error': 'denied'}, 403)
            : jsonResponse(catalog);
      case '/api/studio/person/settings':
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        writes.add(body);
        if (pendingWrite != null) return pendingWrite!.future;
        if (reject != null) {
          return jsonResponse({'error': 'Conflict or denied'}, reject!);
        }
        if (body['expected_revision'] != revision) {
          return jsonResponse({'error': 'Settings changed'}, 409);
        }
        model = Map<String, dynamic>.from(body['model'] as Map);
        revision++;
        return jsonResponse({
          'settings': snapshot['settings'],
          'revision': revision,
        });
      case '/api/studio/person':
        return jsonResponse({
          ...snapshot,
          if (!r.url.queryParameters.containsKey('session_id')) 'session': null,
        });
      case '/api/studio/person/conversations':
        if (r.method == 'POST') {
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          creations.add(body);
          if (failCreate) return jsonResponse({'error': 'Unknown result'}, 500);
          return jsonResponse({
            'id': 'person-main-new',
            'title': body['title'],
            'profile': 'work',
            'studio_user_id': owner,
          });
        }
        return jsonResponse({
          'sessions': [
            {
              'id': 'person-main-a',
              'title': 'Existing BOT',
              'profile': 'work',
              'studio_user_id': owner,
            },
          ],
          'next_offset': null,
        });
    }
    return null;
  }

  StudioApi api() => taskApi((r) async => await handle(r) ?? jsonResponse({}));
  Future<PersonController> controller() async {
    final api = this.api()..profile = 'work';
    final c = widgetPerson(cards: false, client: api);
    await c.refreshSnapshot();
    return c;
  }
}

void main() {
  test(
    'BOT catalog keeps Profile identity and aliases without credentials or disabled models',
    () async {
      final f = ModelFixture();
      final options = await f.api().personModels();
      expect(options.length, 4);
      final work = options.firstWhere(
        (m) => m.profile == 'work' && m.id == 'alpha',
      );
      final other = options.firstWhere(
        (m) => m.profile == 'other' && m.id == 'alpha',
      );
      expect(work.key, isNot(other.key));
      expect(work.groupKey, isNot(other.groupKey));
      expect(work.label, 'work Alpha');
      expect(
        jsonEncode(options.map((m) => m.toSelection()).toList()),
        isNot(contains('catalog-secret')),
      );
    },
  );

  test(
    'BOT model write is revision scoped, blocks sends in flight and preserves other settings',
    () async {
      final f = ModelFixture(), wait = Completer<http.Response>();
      final c = await f.controller();
      addTearDown(c.dispose);
      c.draft.text = 'Do not lose this draft';
      final option = (await c.api.personModels()).firstWhere(
        (m) => m.id == 'beta' && m.profile == 'work',
      );
      f.pendingWrite = wait;
      final saving = c.changeModel(option);
      expect(c.modelSaving, true);
      expect(c.send('Too early'), false);
      expect(await c.changeModel(option), false);
      f.model = option.toSelection();
      f.revision++;
      wait.complete(
        jsonResponse({
          'settings': f.snapshot['settings'],
          'revision': f.revision,
        }),
      );
      expect(await saving, true);
      expect(f.writes.single, {
        'session_id': c.sessionId,
        'expected_revision': 4,
        'model': option.toSelection(),
      });
      expect(c.snapshot!.settings['workspace'], '/bot/work');
      expect(c.snapshot!.settings['agents'], [
        {'id': 'worker'},
      ]);
      expect(c.draft.text, 'Do not lose this draft');
      expect(c.snapshot!.settingsRevision, 5);
    },
  );

  for (final status in [403, 409, 500]) {
    test(
      'BOT model $status response reconciles without retrying the write',
      () async {
        final f = ModelFixture()..reject = status;
        final c = await f.controller();
        addTearDown(c.dispose);
        final option = (await c.api.personModels()).first;
        expect(await c.changeModel(option), false);
        expect(c.modelError, isNotNull);
        expect(f.writes.length, 1);
        expect(c.snapshot!.settings['model'], f.model);
        expect(c.modelSaving, false);
      },
    );
  }

  test('busy BOT refuses model writes', () async {
    final f = ModelFixture();
    final c = await f.controller();
    addTearDown(c.dispose);
    c.live.working = true;
    expect(await c.changeModel((await f.api().personModels()).first), false);
    expect(f.writes, isEmpty);
  });

  test(
    'changing BOT model Profile resumes its own scope and keeps run payload configuration-free',
    () async {
      final f = ModelFixture();
      final c = await f.controller();
      addTearDown(c.dispose);
      final selected = (await c.api.personModels()).firstWhere(
        (m) => m.profile == 'other',
      );
      expect(await c.changeModel(selected), true);
      expect(c.api.profile, 'other');
      c.onEvent('app.resumed', {
        ...personPage(),
        'session_id': c.sessionId,
        'isWorking': false,
      });
      expect(c.send('Continue with the saved BOT model'), true);
      final transport = c.transport as FakeTransport;
      expect(
        transport.emitted.singleWhere((e) => e.$1 == 'run').$2.keys.toSet(),
        {'session_id', 'queue_id', 'input'},
      );
    },
  );

  testWidgets(
    'uncertain BOT creation preserves input and requires checking the list before another create',
    (tester) async {
      final f = ModelFixture()..failCreate = true;
      final h = TestHarness();
      await h.login();
      f.owner = h.controller.account!.id;
      await tester.pumpWidget(
        MaterialApp(
          home: PersonCreateScreen(
            app: h.controller,
            api: f.api(),
            account: f.owner,
            valid: () => h.controller.authenticated,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('bot-name-input')),
        'Keep my new BOT',
      );
      await tester.ensureVisible(find.byKey(const Key('create-bot-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-bot-button')));
      await tester.pumpAndSettle();
      expect(f.creations.length, 1);
      expect(find.text('创建结果待确认，请返回列表刷新后检查'), findsOneWidget);
      expect(find.byKey(const Key('create-bot-button')), findsNothing);
      expect(find.text('Keep my new BOT'), findsOneWidget);
      expect(find.text('返回列表'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      h.dispose();
    },
  );

  testWidgets(
    'BOT model picker saves an authorized model and keeps ordinary model/draft isolated',
    (tester) async {
      final f = ModelFixture(), h = TestHarness();
      await h.login();
      final c = await f.controller();
      c.draft.text = 'BOT draft remains';
      final ordinaryModel = h.controller.selectedModel?.key;
      final choices = jsonEncode(h.storage.choices);
      await tester.pumpWidget(
        MaterialApp(
          home: PersonScreen(
            app: h.controller,
            sessionId: c.sessionId,
            controller: c,
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.syncing = false;
      c.changed();
      await tester.pump();
      await tester.tap(find.byKey(const Key('model-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find
            .descendant(
              of: find.byType(PersonModelPicker),
              matching: find.byType(TextField),
            )
            .first,
        'work Beta',
      );
      await tester.pumpAndSettle();
      final key = jsonEncode(['work', 'shared', 'beta']);
      await tester.tap(find.byKey(ValueKey('model:$key')));
      await tester.pumpAndSettle();
      expect(f.writes.single['model'], {
        'profile': 'work',
        'provider': 'shared',
        'model': 'beta',
        'apiMode': 'anthropic_messages',
      });
      expect(find.text('beta'), findsOneWidget);
      expect(c.draft.text, 'BOT draft remains');
      expect(h.controller.selectedModel?.key, ordinaryModel);
      expect(jsonEncode(h.storage.choices), choices);
      expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'BOT catalog failure can retry without changing the saved model',
    (tester) async {
      final f = ModelFixture()..failCatalog = true;
      final c = await f.controller(), h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        MaterialApp(
          home: PersonScreen(
            app: h.controller,
            sessionId: c.sessionId,
            controller: c,
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.syncing = false;
      c.changed();
      await tester.pump();
      await tester.tap(find.byKey(const Key('model-button')));
      await tester.pumpAndSettle();
      expect(find.text('BOT 模型列表加载失败，请重试'), findsOneWidget);
      f.failCatalog = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('选择模型'), findsOneWidget);
      expect(f.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      h.dispose();
    },
  );

  testWidgets(
    'BOT tab matches single header, searches above tabs and creates an isolated BOT session',
    (tester) async {
      // Keep the real device's pixel ratio for its native keyboard/insets.
      // Host tests still check the same layout at a narrow phone size.
      if (tester.binding is! LiveTestWidgetsFlutterBinding) {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final f = ModelFixture(), h = TestHarness();
      await h.login();
      f.owner = h.controller.account!.id;
      h.override = (r) async => await f.handle(r) ?? h.response(r);
      final opened = <Conversation>[];
      var ordinaryCreates = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: ConversationDrawer(
              controller: h.controller,
              onNewChat: () => ordinaryCreates++,
              onOpenConversation: opened.add,
              onOpenGroup: (_) {},
            ),
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final singleButton = tester.getRect(
        find.byKey(const Key('new-conversation-button')),
      );
      final singleSearch = tester.getRect(
        find.byKey(const ValueKey('conversation-search:0')),
      );
      await tester.tap(find.byKey(const Key('bot-tab')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('new-conversation-button'))),
        singleButton,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('conversation-search:2'))),
        singleSearch,
      );
      expect(
        singleSearch.bottom,
        lessThan(tester.getRect(find.byType(TabBar)).top),
      );
      final row = tester.widget<ListTile>(
        find.byKey(const ValueKey('bot-history:person-main-a')),
      );
      expect(row.minTileHeight, 54);
      await tester.enterText(
        find.byKey(const ValueKey('conversation-search:2')),
        'Find BOT',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        h.requests
            .lastWhere((r) => r.url.path.endsWith('/person/conversations'))
            .url
            .queryParameters['search'],
        'Find BOT',
      );
      await tester.tap(find.byKey(const Key('new-conversation-button')));
      await tester.pumpAndSettle();
      expect(find.byType(PersonCreateScreen), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('bot-name-input')),
        'My new BOT',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('create-bot-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-bot-button')));
      await tester.pumpAndSettle();
      expect(f.creations.single, {
        'title': 'My new BOT',
        'expected_revision': 4,
        'model': f.model,
      });
      expect(opened.single.id, 'person-main-new');
      expect(ordinaryCreates, 0);
      expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      h.dispose();
    },
  );
}
