import 'dart:convert';
import 'package:ekko_app/data/speech_playback.dart';
import 'package:ekko_app/data/audio_transcription.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ekko_app/data/app_storage.dart';
import 'package:ekko_app/data/chat_transport.dart';
import 'package:ekko_app/data/studio_api.dart';
import 'package:ekko_app/state/app_controller.dart';

class MemoryStorage implements AppStorage {
  Map<String, dynamic>? session;
  String theme = 'system';
  final choices = <String, Map<String, dynamic>>{};
  bool hintSeen = false;
  @override
  Future<Map<String, dynamic>?> readChoice(String scope) async =>
      choices[scope];
  @override
  Future<void> saveChoice(String scope, Map<String, dynamic> choice) async {
    choices[scope] = choice;
  }

  @override
  Future<bool> readReadingHintSeen() async => hintSeen;
  @override
  Future<void> markReadingHintSeen() async {
    hintSeen = true;
  }

  @override
  Future<Map<String, dynamic>?> readSession() async => session;
  @override
  Future<void> saveSession(Map<String, dynamic> value) async {
    session = value;
  }

  @override
  Future<void> clearSession() async {
    session = null;
  }

  @override
  Future<String> deviceId() async => 'test-installation-id';
  @override
  Future<String> readTheme() async => theme;
  @override
  Future<void> saveTheme(String value) async {
    theme = value;
  }
}

class FakeTransport implements ChatTransport {
  SocketEvent? listener;
  final emitted = <(String, Map<String, dynamic>)>[];
  @override
  void connect(StudioApi api, SocketEvent onEvent) {
    listener = onEvent;
  }

  @override
  void emit(String event, Map<String, dynamic> data) {
    emitted.add((event, data));
  }

  void receive(String event, Map<String, dynamic> data) =>
      listener?.call(event, data);
  @override
  void dispose() {
    listener = null;
  }
}

class TestHarness {
  TestHarness({this.speech, this.transcription});
  final AudioTranscription? transcription;
  final SpeechPlayback? speech;
  final storage = MemoryStorage();
  final transport = FakeTransport();
  final requests = <http.Request>[];
  Future<http.Response> Function(http.Request)? override;
  late final controller = AppController(
    storage: storage,
    speech: speech,
    transcription: transcription,
    transport: transport,
    apiFactory: (address) => StudioApi(
      address,
      client: MockClient((request) async {
        requests.add(request);
        if (override != null) return override!(request);
        return response(request);
      }),
    ),
  );
  http.Response response(http.Request request) {
    final path = request.url.path;
    final body = switch (path) {
      '/api/auth/app-login' => {
        'token': 'device-token',
        'profiles': ['default', 'work'],
        'userId': 1,
      },
      '/api/auth/me' => {
        'user': {'id': 1, 'username': 'Alex', 'role': 'admin'},
      },
      '/api/app/profiles' => {
        'profiles': [
          {'name': 'default'},
          {'name': 'work'},
        ],
      },
      '/api/hermes/available-models' => {
        'default': 'model-a',
        'default_provider': 'test',
        'groups': [
          {
            'provider': 'test',
            'label': 'Test Provider',
            'models': ['model-a', 'model-b'],
            'api_key': 'MUST-NOT-BE-STORED',
          },
        ],
      },
      '/api/studio/sessions' => {
        'sessions': [
          {
            'id': 'history-1',
            'title': '探索新的可能',
            'profile': 'default',
            'agent': 'ekko-agent',
            'model': 'model-a',
            'provider': 'test',
            'preview': '一个好问题，是新发现的开始。',
          },
        ],
        'hasMore': false,
      },
      _ when path.endsWith('/messages/paginated') => {
        'messages': [
          {'id': 1, 'role': 'user', 'content': '你好'},
          {'id': 2, 'role': 'assistant', 'content': '你好！有什么可以帮你？'},
        ],
        'offset': 0,
        'total': 2,
        'hasMore': false,
      },
      _ => {'ok': true},
    };
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<void> login() async {
    await controller.initialize();
    await controller.login('https://example.com', 'Alex', 'password', false);
    transport.receive('connected', {});
  }

  void dispose() => controller.dispose();
}
