import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chatstudio/core/server_address.dart';
import 'package:chatstudio/data/mobile_media.dart';
import 'package:chatstudio/data/models.dart';
import 'package:chatstudio/data/studio_api.dart';
import 'package:chatstudio/main.dart';
import 'package:chatstudio/state/chat_timeline.dart';
import 'package:chatstudio/ui/widgets/chat_composer.dart';
import 'package:chatstudio/ui/widgets/attachment_tile.dart';
import 'package:chatstudio/ui/widgets/reading_handle.dart';
import 'package:chatstudio/ui/widgets/stable_markdown.dart';
import 'support.dart';

class MeterMedia implements MediaAccess, AudioLevelSource {
  final levels = StreamController<double>.broadcast();
  @override
  Stream<double> get audioLevels => levels.stream;
  @override
  Future<List<LocalAttachment>> pick({required bool images}) async => [];
  @override
  Future<void> startRecording() async {}
  @override
  Future<String?> stopRecording() async => null;
  @override
  Future<void> cancelRecording() async {}
  @override
  Future<void> dispose() async => levels.close();
}

void main() {
  test(
    'model and engine remembered per account/server/Profile, history does not overwrite new-chat choice',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.chooseModel(h.controller.models.last);
      h.controller.chooseEngine('hermes');
      await Future<void>.delayed(Duration.zero);
      await h.controller.openConversation(
        const Conversation(
          id: 'old',
          title: 'old',
          agent: 'ekko-agent',
          model: 'model-a',
          provider: 'test',
        ),
      );
      expect(h.controller.selectedModel?.id, 'model-a');
      h.controller.newChat();
      expect(h.controller.selectedModel?.id, 'model-b');
      expect(h.controller.engine, 'hermes');
      await h.controller.switchProfile('work');
      expect(h.controller.selectedModel?.id, 'model-a');
      expect(h.controller.engine, 'ekko-agent');
      await h.controller.switchProfile('default');
      expect(h.controller.selectedModel?.id, 'model-b');
      expect(h.controller.engine, 'hermes');
      await h.controller.logout();
      await h.login();
      expect(h.controller.selectedModel?.id, 'model-b');
      expect(jsonEncode(h.storage.choices), isNot(contains('web-token')));
      expect(jsonEncode(h.storage.choices), isNot(contains('password')));
      await h.controller.logout();
      await h.controller.login(
        'https://another.example',
        'Alex',
        'password',
        false,
      );
      expect(h.controller.selectedModel?.id, 'model-a');
    },
  );
  test(
    'removed remembered model announces fallback instead of silently switching',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      await h.controller.chooseModel(
        const ModelChoice(id: 'removed', provider: 'test', label: 'Removed'),
      );
      await h.controller.refreshWorkspace();
      expect(h.controller.selectedModel?.id, 'model-a');
      expect(h.controller.workspaceNotice, contains('已不可用'));
    },
  );
  test(
    'uncertain send is not retryable; confirmed failure prepares draft without emitting',
    () async {
      final h = TestHarness();
      addTearDown(h.dispose);
      await h.login();
      h.controller.send(
        '请继续',
        attachments: [
          {
            'type': 'file',
            'name': 'a.txt',
            'path': '/uploaded/a.txt',
            'media_type': 'text/plain',
            'size': 10,
          },
        ],
      );
      expect(h.controller.timeline.messages.last.delivery, 'sending');
      h.transport.receive('disconnected', {});
      expect(h.controller.timeline.messages.last.delivery, 'uncertain');
      final emitted = h.transport.emitted.length;
      h.controller.prepareRetry();
      expect(h.controller.retryRevision, 0);
      expect(h.transport.emitted.length, emitted);
      h.transport.receive('connected', {});
      h.transport.receive('run.failed', {
        'session_id': h.controller.sessionId,
        'error': '模型服务不可用',
        'run_id': 'confirmed-run',
      });
      expect(h.controller.timeline.messages.last.delivery, 'failed');
      expect(h.controller.error, isNull);
      final count = h.transport.emitted.length;
      h.controller.prepareRetry();
      expect(h.controller.retryInput, '请继续');
      expect(h.controller.retryAttachments.single['path'], '/uploaded/a.txt');
      expect(h.transport.emitted.length, count);
    },
  );
  test('snapshot absence does not authorize retry of uncertain input', () {
    final timeline = ChatTimeline()
      ..begin('possibly delivered', 'local:q')
      ..markUncertain();
    timeline.resume({'messages': [], 'isWorking': false});
    expect(timeline.messages.single.delivery, 'uncertain');
  });
  test(
    'tool events deduplicate and consecutive assistant rows form one turn',
    () {
      final timeline = ChatTimeline()..begin('q', 'u');
      timeline.apply('run.started', {'run_id': 'r'});
      timeline.apply('reasoning.delta', {'run_id': 'r', 'delta': 'plan'});
      for (var i = 0; i < 2; i++) {
        timeline.apply('tool.started', {
          'run_id': 'r',
          'tool_call_id': 't',
          'name': 'read_file',
        });
      }
      timeline.apply('tool.completed', {
        'run_id': 'r',
        'tool_call_id': 't',
        'name': 'read_file',
      });
      timeline.apply('message.delta', {'run_id': 'r', 'delta': 'result'});
      expect(timeline.displayMessages.last.tools.single.status, 'done');
      timeline.messages.add(
        const ChatMessage(
          id: 'more',
          role: 'assistant',
          content: 'more result',
        ),
      );
      expect(timeline.displayMessages.length, 2);
      expect(timeline.displayMessages.last.content, 'result\n\nmore result');
    },
  );
  test(
    'authoritative history preserves render identity and known attachment size',
    () {
      final timeline = ChatTimeline()
        ..begin(
          '[文件：x.txt]',
          'local:u',
          attachments: [
            const MessageAttachment(
              name: 'x.txt',
              path: '/x',
              mimeType: 'text/plain',
              size: 321,
            ),
          ],
        );
      timeline.replace([
        ChatMessage.fromJson({
          'id': 17,
          'role': 'user',
          'content': [
            {
              'type': 'file',
              'name': 'x.txt',
              'path': '/x',
              'media_type': 'text/plain',
            },
          ],
        }),
      ]);
      expect(timeline.messages.single.renderKey, 'local:u');
      expect(timeline.messages.single.attachments.single.size, 321);
    },
  );
  test('Markdown segmentation protects fences, nested lists, and tables', () {
    const code = 'intro\n\n```dart\nfirst\n\nsecond\n```\n\nafter';
    expect(markdownSegments(code), [
      'intro',
      '```dart\nfirst\n\nsecond\n```',
      'after',
    ]);
    expect(markdownSegments('1. one\n\n   nested\n2. two\n\nend'), [
      '1. one\n\n   nested\n2. two',
      'end',
    ]);
    expect(
      markdownSegments('| a | b |\n|---|---|\n| x | y |\n\nend').length,
      2,
    );
  });
  testWidgets(
    'unchanged Markdown blocks reuse widget while tail changes; complete does not change layout engine',
    (tester) async {
      String source = '### 标题\n\n第一段\n\n正在输出';
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, state) {
                update = state;
                return StableMarkdown(data: source);
              },
            ),
          ),
        ),
      );
      final first = tester.widget<MarkdownBody>(
        find.byType(MarkdownBody).first,
      );
      update(() => source += '更多内容');
      await tester.pump();
      expect(
        tester.widget<MarkdownBody>(find.byType(MarkdownBody).first),
        same(first),
      );
      expect(find.byType(MarkdownBody), findsNWidgets(3));
    },
  );
  testWidgets('wide tables and nested code do not overflow a phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StableMarkdown(
              data:
                  '| field | long field name and value |\n|---|---|\n| a | abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz |\n\n1. nested\n\n   ```text\n   long unbroken code abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz\n   ```\n\n2. another',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test(
    'upload progress reports streamed body bytes monotonically and preserves cancellation',
    () async {
      final samples = <double>[];
      final abort = Completer<void>();
      final request = ProgressMultipartRequest(
        'POST',
        Uri.parse('https://example.com'),
        onProgress: samples.add,
        abortTrigger: abort.future,
      );
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          List.filled(2048, 7),
          filename: 'a.bin',
        ),
      );
      final body = await request.finalize().toBytes();
      expect(body.length, request.contentLength);
      expect(samples.last, 1);
      expect(samples, orderedEquals([...samples]..sort()));
      expect(request.abortTrigger, same(abort.future));
    },
  );
  test(
    'attachment metadata and image downloads use only authenticated server route and bounded cache',
    () async {
      var count = 0;
      final api = StudioApi(
        ServerAddress.parse('https://studio.example'),
        client: MockClient((r) async {
          count++;
          expect(r.url.host, 'studio.example');
          expect(r.url.path, '/api/studio/files/download');
          expect(r.followRedirects, false);
          expect(r.headers['authorization'], 'Bearer token');
          expect(r.headers['x-hermes-profile'], 'default');
          expect(r.url.queryParameters['variant'], 'app-image');
          return http.Response.bytes([1, 2, 3], 200);
        }),
      )..token = 'token';
      addTearDown(api.close);
      const file = MessageAttachment(
        name: 'picture.png',
        path: '/uploads/x.png',
        mimeType: 'image/png',
        size: 500,
      );
      expect(await api.attachmentBytes(file, thumbnail: true), [1, 2, 3]);
      await api.attachmentBytes(file, thumbnail: true);
      expect(count, 1);
      expect(file.sizeLabel, '1 KB');
      expect(file.toBlock()['size'], 500);
    },
  );
  for (final code in [302, 401, 403, 404]) {
    test(
      'attachment status $code does not return arbitrary bytes or follow redirect',
      () async {
        var unauthorized = false;
        final api = StudioApi(
          ServerAddress.parse('https://studio.example'),
          client: MockClient(
            (r) async => http.Response(
              'bad',
              code,
              headers: {'location': 'https://evil.example'},
            ),
          ),
        )..onUnauthorized = () => unauthorized = true;
        addTearDown(api.close);
        await expectLater(
          api.attachmentBytes(
            const MessageAttachment(
              name: 'x',
              path: '/x',
              mimeType: 'text/plain',
            ),
          ),
          throwsA(isA<ApiException>()),
        );
        expect(unauthorized, code == 401);
      },
    );
  }
  testWidgets(
    'voice meter uses actual samples, silence hint appears, and cancel stays local',
    (tester) async {
      final h = TestHarness();
      h.override = (r) async => r.url.path.endsWith('profile-status')
          ? http.Response('{"configured":true,"activeProvider":"custom"}', 200)
          : h.response(r);
      await h.login();
      final media = MeterMedia(), input = TextEditingController();
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
      await tester.tap(find.byKey(const Key('voice-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      media.levels.add(.05);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('暂未检测到声音'), findsOneWidget);
      media.levels.add(.7);
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('voice-level')),
            )
            .value,
        .7,
      );
      expect(find.textContaining('暂未检测到声音'), findsNothing);
      await tester.tap(find.byTooltip('取消当前操作'));
      await tester.pumpAndSettle();
      expect(h.transport.emitted.where((e) => e.$1 == 'run'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      h.dispose();
      input.dispose();
    },
  );
  testWidgets(
    'reading handle fades after idle, wakes and interpolates rather than jumping',
    (tester) async {
      final progress = ValueNotifier<double>(.2);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadingHandle(progress: progress, onExpand: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        .68,
      );
      progress.value = .8;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('reading-progress-lines')),
                  )
                  .painter!
              as ReadingHandlePainter;
      expect(painter.progress, greaterThan(.2));
      expect(painter.progress, lessThan(.8));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      progress.dispose();
    },
  );
  testWidgets(
    'reading anchor keeps visible row and badge marks new text without jumping',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      h.controller.sessionId = 'anchor';
      h.controller.timeline.replace(
        List.generate(
          60,
          (i) => ChatMessage(
            id: 'm$i',
            role: i.isEven ? 'user' : 'assistant',
            content: 'message $i\n阅读原来的位置，不要跳动。',
          ),
        ),
      );
      h.controller.dismissError();
      await tester.pumpAndSettle();
      final list = find.byKey(const Key('message-list'));
      final controller = tester.widget<ListView>(list).controller!;
      controller.jumpTo(1800);
      await tester.pumpAndSettle();
      Finder? anchor;
      for (var i = 0; i < 60; i++) {
        final candidate = find.byKey(ValueKey('m$i'));
        if (candidate.evaluate().isNotEmpty) {
          final rect = tester.getRect(candidate);
          if (rect.top > 80 && rect.bottom < 500) {
            anchor = candidate;
            break;
          }
        }
      }
      expect(anchor, isNotNull);
      final before = tester.getTopLeft(anchor!).dy;
      h.controller.timeline.messages.add(
        const ChatMessage(
          id: 'stream',
          role: 'assistant',
          content: 'new text\n\nnew paragraph',
          pending: true,
        ),
      );
      h.controller.timeline.liveRevision++;
      h.controller.dismissError();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, closeTo(before, 2));
      expect(find.text('新'), findsOneWidget);
      h.controller.timeline.prepend([
        const ChatMessage(id: 'older', role: 'user', content: '更早'),
      ]);
      h.controller.dismissError();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(anchor).dy, closeTo(before, 2));
      await tester.tap(find.byTooltip('回到最新消息'));
      await tester.pumpAndSettle();
      expect(find.text('新'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'history refresh retains previously loaded earlier rows and stable identities',
    () {
      final timeline = ChatTimeline();
      timeline.replace(
        List.generate(
          100,
          (i) => ChatMessage(
            id: '$i',
            role: i.isEven ? 'user' : 'assistant',
            content: 'line $i',
          ),
        ),
      );
      timeline.replace(
        List.generate(
          60,
          (i) => ChatMessage(
            id: '${i + 40}',
            role: (i + 40).isEven ? 'user' : 'assistant',
            content: 'line ${i + 40}',
          ),
        ),
        keepOlder: true,
      );
      expect(timeline.messages.length, 100);
      expect(timeline.messages.first.id, '0');
    },
  );
  test('repeated text does not steal another persisted row identity', () {
    final timeline = ChatTimeline()
      ..replace(const [
        ChatMessage(id: '1', role: 'user', content: 'same'),
        ChatMessage(id: '2', role: 'user', content: 'same'),
      ]);
    timeline.replace(const [
      ChatMessage(id: '1', role: 'user', content: 'same'),
      ChatMessage(id: '2', role: 'user', content: 'same'),
    ]);
    expect(timeline.messages.map((m) => m.renderKey), ['1', '2']);
  });
  test(
    'attachment request rejects oversized responses before collecting bytes',
    () async {
      final api = StudioApi(
        ServerAddress.parse('https://example.com'),
        client: MockClient.streaming(
          (request, body) async => http.StreamedResponse(
            const Stream<List<int>>.empty(),
            200,
            contentLength: 26 * 1024 * 1024,
          ),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.attachmentBytes(
          const MessageAttachment(
            name: 'large.bin',
            path: '/large',
            mimeType: 'application/octet-stream',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('过大'),
          ),
        ),
      );
    },
  );
  test('late attachment bytes cannot cross a Profile switch', () async {
    final response = Completer<http.Response>();
    final started = Completer<void>();
    final api = StudioApi(
      ServerAddress.parse('https://example.com'),
      client: MockClient((request) {
        started.complete();
        return response.future;
      }),
    );
    addTearDown(api.close);
    final result = api.attachmentBytes(
      const MessageAttachment(
        name: 'a.txt',
        path: '/a',
        mimeType: 'text/plain',
      ),
    );
    final expectation = expectLater(result, throwsA(isA<ApiException>()));
    await started.future;
    api.profile = 'work';
    response.complete(http.Response('private bytes', 200));
    await expectation;
  });
  testWidgets(
    'failed message retry restores editable text and remote references but never automatically sends',
    (tester) async {
      final h = TestHarness();
      await h.login();
      await tester.pumpWidget(
        ChatStudioApp(controller: h.controller, initialize: false),
      );
      h.controller.send(
        'original',
        attachments: [
          {
            'type': 'file',
            'name': 'a.txt',
            'path': '/a',
            'media_type': 'text/plain',
            'size': 5,
          },
        ],
      );
      h.transport.receive('run.failed', {
        'session_id': h.controller.sessionId,
        'error': '暂时不可用',
      });
      await tester.pumpAndSettle();
      final runs = h.transport.emitted.where((e) => e.$1 == 'run').length;
      await tester.tap(find.text('编辑后重试'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('message-input')))
            .controller!
            .text,
        'original',
      );
      expect(find.byType(InputChip), findsOneWidget);
      expect(h.transport.emitted.where((e) => e.$1 == 'run').length, runs);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('retry does not overwrite a newer draft', (tester) async {
    final h = TestHarness();
    await h.login();
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    h.controller.send('original');
    h.transport.receive('run.failed', {
      'session_id': h.controller.sessionId,
      'error': '失败',
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('message-input')), 'new draft');
    h.controller.prepareRetry();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('message-input')))
          .controller!
          .text,
      'new draft',
    );
    expect(find.textContaining('清空现有草稿'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'expired thumbnail displays readable retry state instead of an empty placeholder',
    (tester) async {
      final h = TestHarness();
      await h.login();
      h.override = (request) async => request.url.path.endsWith('/download')
          ? http.Response('{}', 404)
          : h.response(request);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentTile(
              file: const MessageAttachment(
                name: 'gone.png',
                path: '/gone',
                mimeType: 'image/png',
              ),
              controller: h.controller,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('附件已失效'), findsOneWidget);
      final before = h.requests
          .where((r) => r.url.path.endsWith('/download'))
          .length;
      await tester.tap(find.textContaining('点击重试'));
      await tester.pumpAndSettle();
      expect(
        h.requests.where((r) => r.url.path.endsWith('/download')).length,
        before + 1,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      h.dispose();
    },
  );
  testWidgets('first reading hint persists once without adding a footer row', (
    tester,
  ) async {
    final h = TestHarness();
    await h.login();
    await tester.pumpWidget(
      ChatStudioApp(controller: h.controller, initialize: false),
    );
    h.controller.sessionId = 'hint';
    h.controller.timeline.replace(
      List.generate(
        60,
        (i) => ChatMessage(
          id: 'hint-$i',
          role: i.isEven ? 'user' : 'assistant',
          content: 'history message $i\nline two',
        ),
      ),
    );
    h.controller.dismissError();
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('message-list')),
      const Offset(0, 420),
    );
    await tester.pumpAndSettle();
    expect(h.storage.hintSeen, true);
    expect(find.text('轻点底部线条，继续输入'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('轻点底部线条，继续输入'), findsNothing);
    await tester.tap(find.byKey(const Key('expand-composer')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('message-list')),
      const Offset(0, 300),
    );
    await tester.pumpAndSettle();
    expect(find.text('轻点底部线条，继续输入'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'older resumed run cannot acknowledge or fail an unmatched uncertain send',
    () {
      final timeline = ChatTimeline()
        ..begin('unmatched new input', 'local:unknown')
        ..markUncertain();
      timeline.resume({
        'messages': [
          {'id': 1, 'role': 'user', 'content': 'older question'},
        ],
        'isWorking': true,
        'events': [
          {
            'event': 'run.started',
            'data': {'run_id': 'old'},
          },
        ],
      });
      expect(timeline.messages.last.delivery, 'uncertain');
      timeline.apply('run.failed', {'run_id': 'old', 'error': 'old failure'});
      expect(timeline.messages.last.delivery, 'uncertain');
    },
  );
}
