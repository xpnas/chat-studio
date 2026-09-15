import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/mobile_media.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/ui/theme.dart';
import 'package:chatstudio/ui/widgets/chat_composer.dart';
import 'package:chatstudio/ui/widgets/message_bubble.dart';
import 'support.dart';

class FakeMedia implements MediaAccess {
  List<LocalAttachment> files = [];
  String? audio;
  bool denied = false;
  int started = 0, canceled = 0;
  @override
  Future<List<LocalAttachment>> pick({required bool images}) async => files;
  @override
  Future<void> startRecording() async {
    if (denied) throw StateError('麦克风权限被拒绝');
    started++;
  }

  @override
  Future<String?> stopRecording() async => audio;
  @override
  Future<void> cancelRecording() async {
    canceled++;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('Codex uses exact upstream routing, history stays writable', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    await h.login();
    h.controller.chooseEngine('codex');
    expect(h.controller.send('hello'), isTrue);
    final run = h.transport.emitted.last.$2;
    expect(run['agent_id'], 'codex');
    expect(run['source'], 'coding_agent');
    expect(run['mode'], 'scoped');
    expect(
      const Conversation(
        id: 'c',
        title: '',
        agent: 'codex',
        source: 'coding_agent',
      ).canContinue,
      isTrue,
    );
    expect(
      const Conversation(
        id: 'c',
        title: '',
        agent: 'codex',
        source: 'global_agent',
      ).canContinue,
      isFalse,
    );
    h.transport.receive('abort.completed', {
      'session_id': h.controller.sessionId,
    });
    await h.controller.openConversation(
      const Conversation(id: 'c', title: '', agent: 'codex'),
    );
    expect(h.controller.engine, 'codex');
  });
  test('capabilities parse installed Codex and STT, not TTS', () async {
    final h = TestHarness();
    addTearDown(h.dispose);
    h.override = (r) async => switch (r.url.path) {
      '/api/coding-agents' => http.Response(
        '{"tools":[{"id":"codex","installed":true}]}',
        200,
      ),
      '/api/studio/stt/profile-status' => http.Response(
        '{"configured":true,"activeProvider":"custom"}',
        200,
      ),
      _ => h.response(r),
    };
    await h.login();
    expect(h.controller.codexInstalled, true);
    expect(h.controller.sttProvider, 'custom');
    h.override = null;
    await h.controller.refreshCapabilities();
    expect(h.controller.sttProvider, isNull);
  });
  test(
    'empty tool-like rows hidden, reasoning and attachment labels preserved',
    () {
      expect(
        const ChatMessage(id: '', role: 'assistant', content: '  ').visible,
        false,
      );
      expect(
        const ChatMessage(id: '', role: 'tool', content: 'tool result').visible,
        false,
      );
      expect(
        const ChatMessage(
          id: '',
          role: 'assistant',
          content: '',
          reasoning: '计划',
        ).visible,
        true,
      );
      expect(
        messageText([
          {'type': 'image', 'name': '照片.png'},
          {'type': 'file', 'name': '需求.pdf'},
        ]),
        contains('需求.pdf'),
      );
    },
  );
  testWidgets('thought-only row has no avatar or ellipsis and is collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: const ChatMessage(
              id: 'r',
              role: 'assistant',
              content: '',
              reasoning: '内部计划',
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ChatStudioMark), findsNothing);
    expect(find.text('…'), findsNothing);
    expect(find.text('内部计划').hitTestable(), findsNothing);
    await tester.tap(find.text('思考过程'));
    await tester.pumpAndSettle();
    expect(find.text('内部计划').hitTestable(), findsOneWidget);
  });
  testWidgets('provider hierarchy pins current model; search retains parent', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    final models = List.generate(
      60,
      (i) => ModelChoice(
        id: 'm$i',
        provider: i < 30 ? 'a' : 'b',
        providerLabel: i < 30 ? '提供商 A' : '提供商 B',
        label: '模型 $i',
      ),
    );
    h.controller.models = models;
    h.controller.selectedModel = models.last;
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('AI 的回答可能有误，请核实重要信息。'), findsNothing);
    await tester.tap(find.text('模型 59'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('model:b::m59')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('provider:b'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('model:b::m59'))).dy,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('provider:b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('model:b::m59')), findsNothing);
    expect(find.byKey(const ValueKey('provider:a')), findsOneWidget);
    expect(find.byKey(const ValueKey('model:a::m0')), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, '搜索模型或提供商'), 'm42');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('provider:b')), findsOneWidget);
    expect(find.byKey(const ValueKey('model:b::m42')), findsOneWidget);
    expect(find.byKey(const ValueKey('provider:a')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('model:b::m42')));
    await tester.pumpAndSettle();
    expect(h.controller.selectedModel?.id, 'm42');
  });

  group('multipart contract', () {
    late Directory dir;
    late LocalAttachment file;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('chatstudio-test-');
      final f = File('${dir.path}/test.txt');
      await f.writeAsString('hello attachment');
      file = await LocalAttachment.fromPath(f.path, '需求.txt');
    });
    tearDown(() async => dir.delete(recursive: true));
    test(
      'file upload has auth, scope, file field and structured references',
      () async {
        final api =
            StudioApi(
                ServerAddress.parse('https://example.com'),
                client: MockClient((r) async {
                  expect(r.followRedirects, false);
                  expect(r.headers['authorization'], 'Bearer secret');
                  expect(r.headers['x-hermes-profile'], 'work');
                  expect(r.url.path, '/api/studio/uploads');
                  expect(r.body, contains('name="file"'));
                  expect(r.body, contains('hello attachment'));
                  return http.Response(
                    '{"files":[{"name":"test.txt","path":"/server/uploads/test.txt"}]}',
                    200,
                  );
                }),
              )
              ..token = 'secret'
              ..profile = 'work';
        addTearDown(api.close);
        final blocks = await api.uploadAttachments([file]);
        expect(blocks.single['type'], 'file');
        expect(blocks.single['path'], '/server/uploads/test.txt');
        final h = TestHarness();
        addTearDown(h.dispose);
        await h.login();
        expect(h.controller.send('', attachments: blocks), true);
        expect(h.transport.emitted.last.$2['input'], blocks);
        expect(
          h.controller.timeline.messages.single.content,
          contains('需求.txt'),
        );
      },
    );
    test(
      'transcription sends audio and provider and returns editable text',
      () async {
        final api = StudioApi(
          ServerAddress.parse('https://example.com'),
          client: MockClient((r) async {
            expect(r.url.path, '/api/studio/stt/transcribe');
            expect(r.body, contains('name="audio"'));
            expect(r.body, contains('audio/wav'));
            expect(r.body, contains('custom'));
            return http.Response(
              jsonEncode({'text': '语音识别结果'}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        addTearDown(api.close);
        expect(await api.transcribe(file.path, 'custom'), '语音识别结果');
      },
    );
    test('upload errors and limits never become partial messages', () async {
      final api = StudioApi(
        ServerAddress.parse('https://example.com'),
        client: MockClient((r) async => http.Response('{"files":[]}', 200)),
      );
      addTearDown(api.close);
      await expectLater(
        api.uploadAttachments([file]),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.uploadAttachments(List.filled(6, file)),
        throwsA(isA<ApiException>()),
      );
    });
    test('multipart 401 invalidates auth and redirects are rejected', () async {
      var unauthorized = false;
      final api = StudioApi(
        ServerAddress.parse('https://example.com'),
        client: MockClient(
          (r) async => http.Response('{"error":"expired"}', 401),
        ),
      )..onUnauthorized = () => unauthorized = true;
      addTearDown(api.close);
      await expectLater(
        api.uploadAttachments([file]),
        throwsA(isA<ApiException>()),
      );
      expect(unauthorized, true);
    });
  });

  Future<void> composer(
    WidgetTester tester,
    TestHarness h,
    FakeMedia media,
    TextEditingController input,
  ) async {
    await h.login();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(
            controller: h.controller,
            input: input,
            media: media,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('picker preview/removal and attachment-only send readiness', (
    tester,
  ) async {
    final h = TestHarness(),
        media = FakeMedia(),
        input = TextEditingController();
    media.files = [
      const LocalAttachment(
        path: '/fixture.txt',
        name: '需求.txt',
        size: 20,
        mimeType: 'text/plain',
      ),
    ];
    await composer(tester, h, media, input);
    await tester.tap(find.byKey(const Key('attachment-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('需求.txt'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('send-button'))).onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('移除 需求.txt'));
    await tester.pumpAndSettle();
    expect(find.text('需求.txt'), findsNothing);
    expect(
      tester.widget<IconButton>(find.byKey(const Key('send-button'))).onPressed,
      isNull,
    );
  });
  testWidgets(
    'STT unavailable never asks for microphone; permission denial is visible',
    (tester) async {
      final h = TestHarness(),
          media = FakeMedia(),
          input = TextEditingController();
      await composer(tester, h, media, input);
      await tester.tap(find.byKey(const Key('voice-button')));
      await tester.pumpAndSettle();
      expect(media.started, 0);
      expect(find.textContaining('STT'), findsOneWidget);
      h.override = (r) async => r.url.path.endsWith('profile-status')
          ? http.Response('{"configured":true,"activeProvider":"custom"}', 200)
          : h.response(r);
      media.denied = true;
      await tester.tap(find.byKey(const Key('voice-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('麦克风权限被拒绝'), findsOneWidget);
    },
  );
  testWidgets('recording cancellation and navigation never send a message', (
    tester,
  ) async {
    final h = TestHarness(),
        media = FakeMedia(),
        input = TextEditingController(text: '草稿');
    h.override = (r) async => r.url.path.endsWith('profile-status')
        ? http.Response('{"configured":true,"activeProvider":"custom"}', 200)
        : h.response(r);
    await composer(tester, h, media, input);
    await tester.tap(find.byKey(const Key('voice-button')));
    await tester.pump();
    await tester.pump();
    expect(media.started, 1);
    expect(find.text('完成'), findsOneWidget);
    h.controller.newChat();
    await tester.pumpAndSettle();
    expect(media.canceled, greaterThan(0));
    expect(find.text('完成'), findsNothing);
    expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
  });
  testWidgets('speech fills editable draft, cancellation ignores late result', (
    tester,
  ) async {
    final h = TestHarness(),
        media = FakeMedia()..audio = '/test.wav',
        input = TextEditingController(text: '原有草稿');
    await composer(tester, h, media, input);
    final oldApi = h.controller.api;
    final api = VoiceFixtureApi();
    h.controller.api = api;
    oldApi?.close();
    Future<void> record() async {
      await tester.tap(find.byKey(const Key('voice-button')));
      await tester.pump();
      await tester.pump();
      // The composer now animates height changes; wait before hit-testing controls.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('完成'));
      await tester.pump();
      await tester.pump();
    }

    await record();
    expect(api.calls, 1);
    api.result.complete('识别结果');
    await tester.pumpAndSettle();
    expect(input.text, '原有草稿\n识别结果');
    expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
    api.result = Completer<String>();
    await record();
    expect(api.calls, 2);
    await tester.tap(find.byTooltip('取消当前操作'));
    await tester.pumpAndSettle();
    api.result.complete('late text');
    await tester.pumpAndSettle();
    expect(input.text, '原有草稿\n识别结果');
    await tester.pumpWidget(const SizedBox.shrink());
    input.dispose();
    h.dispose();
  });
  for (final brightness in Brightness.values) {
    testWidgets(
      'subtle distinct rounded user and assistant surfaces $brightness',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: chatstudioTheme(brightness),
            home: const Scaffold(
              body: Column(
                children: [
                  MessageBubble(
                    message: ChatMessage(
                      id: 'user',
                      role: 'user',
                      content: '问题',
                    ),
                  ),
                  MessageBubble(
                    message: ChatMessage(
                      id: 'ai',
                      role: 'assistant',
                      content: '回答',
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final user =
            tester
                    .widget<Container>(
                      find.byKey(const ValueKey('message-surface:user')),
                    )
                    .decoration!
                as BoxDecoration;
        final ai =
            tester
                    .widget<Container>(
                      find.byKey(const ValueKey('message-surface:ai')),
                    )
                    .decoration!
                as BoxDecoration;
        expect(user.color, isNot(ai.color));
        expect(user.borderRadius, isNotNull);
        expect(ai.borderRadius, isNotNull);
      },
    );
  }
}

class VoiceFixtureApi extends StudioApi {
  VoiceFixtureApi() : super(ServerAddress.parse('https://example.com'));
  Completer<String> result = Completer<String>();
  int calls = 0;
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
    bool public = false,
  }) async => path.endsWith('profile-status')
      ? {'configured': true, 'activeProvider': 'custom'}
      : {};
  @override
  Future<String> transcribe(
    String path,
    String provider, {
    Future<void>? cancel,
    String fileName = 'voice.wav',
    String mimeType = 'audio/wav',
    int maxBytes = 4 * 1024 * 1024,
  }) {
    calls++;
    return result.future;
  }
}
