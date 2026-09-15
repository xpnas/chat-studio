import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ekko_app/core/server_address.dart';
import 'package:ekko_app/data/models.dart';
import 'package:ekko_app/data/studio_api.dart';

class StreamClient extends http.BaseClient {
  StreamClient(this.handle);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handle;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handle(request);
}

const file = MessageAttachment(
  name: 'release.apk',
  path: '/server/release.apk',
  mimeType: 'application/vnd.android.package-archive',
);
void main() {
  test(
    '64 MB APK streams to disk beyond preview limit with credentials and progress',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ekko-large-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const size = 64 * 1024 * 1024;
      Stream<List<int>> chunks() async* {
        final block = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 42);
        for (var n = 0; n < 1024; n++) {
          yield block;
        }
      }

      final api =
          StudioApi(
              ServerAddress.parse('https://example.com'),
              client: StreamClient((r) async {
                expect(r.headers['Authorization'], 'Bearer test');
                expect(r.headers['X-Hermes-Profile'], 'work');
                expect(r.followRedirects, false);
                expect(r.url.queryParameters['variant'], isNull);
                return http.StreamedResponse(
                  chunks(),
                  200,
                  contentLength: size,
                );
              }),
            )
            ..token = 'test'
            ..profile = 'work';
      addTearDown(api.close);
      var last = 0;
      final downloaded = await api.downloadAttachment(
        file,
        directory,
        onProgress: (n, total) {
          expect(n, greaterThanOrEqualTo(last));
          expect(total, size);
          last = n;
        },
      );
      expect(await downloaded.length(), size);
      expect(last, size);
      final input = await downloaded.open();
      await input.setPosition(size - 1);
      expect(await input.readByte(), 42);
      await input.close();
    },
  );
  test('unknown length streams; cancellation removes partial file', () async {
    final dir = await Directory.systemTemp.createTemp('ekko-cancel-test-');
    addTearDown(() => dir.delete(recursive: true));
    final cancel = Completer<void>();
    Stream<List<int>> chunks() async* {
      yield [1, 2, 3];
      cancel.complete();
      yield [4, 5, 6];
    }

    final api = StudioApi(
      ServerAddress.parse('https://example.com'),
      client: StreamClient((_) async => http.StreamedResponse(chunks(), 200)),
    );
    addTearDown(api.close);
    await expectLater(
      api.downloadAttachment(file, dir, cancel: cancel.future),
      throwsA(isA<ApiException>()),
    );
    expect(await dir.list().toList(), isEmpty);
  });
  test('profile changes reject response and clean partial file', () async {
    final dir = await Directory.systemTemp.createTemp('ekko-scope-test-');
    addTearDown(() => dir.delete(recursive: true));
    late StudioApi api;
    Stream<List<int>> chunks() async* {
      yield [1];
      api.profile = 'other';
      yield [2];
    }

    api = StudioApi(
      ServerAddress.parse('https://example.com'),
      client: StreamClient((_) async => http.StreamedResponse(chunks(), 200)),
    );
    addTearDown(api.close);
    await expectLater(
      api.downloadAttachment(file, dir),
      throwsA(isA<ApiException>()),
    );
    expect(await dir.list().toList(), isEmpty);
  });
  for (final status in [401, 403, 404, 302]) {
    test('download rejects $status without exporting', () async {
      final dir = await Directory.systemTemp.createTemp('ekko-http-test-');
      addTearDown(() => dir.delete(recursive: true));
      final api = StudioApi(
        ServerAddress.parse('https://example.com'),
        client: StreamClient(
          (_) async => http.StreamedResponse(const Stream.empty(), status),
        ),
      );
      addTearDown(api.close);
      await expectLater(
        api.downloadAttachment(file, dir),
        throwsA(isA<ApiException>()),
      );
      expect(await dir.list().toList(), isEmpty);
    });
  }
  test('truncated download cannot be reported as successful', () async {
    final dir = await Directory.systemTemp.createTemp('ekko-short-test-');
    addTearDown(() => dir.delete(recursive: true));
    final api = StudioApi(
      ServerAddress.parse('https://example.com'),
      client: StreamClient(
        (_) async => http.StreamedResponse(
          Stream.value([1, 2]),
          200,
          contentLength: 100,
        ),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.downloadAttachment(file, dir),
      throwsA(isA<ApiException>()),
    );
    expect(await dir.list().toList(), isEmpty);
  });
}
