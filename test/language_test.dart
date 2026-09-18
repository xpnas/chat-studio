import 'package:flutter_test/flutter_test.dart';
import 'support.dart';

void main() {
  test(
    'language preference defaults to Chinese and persists English',
    () async {
      final first = TestHarness();
      await first.controller.initialize();
      expect(first.controller.language, 'zh');

      await first.controller.setLanguage('en');
      expect(first.controller.language, 'en');
      expect(first.storage.language, 'en');

      final second = TestHarness()..storage.language = first.storage.language;
      await second.controller.initialize();
      expect(second.controller.language, 'en');
    },
  );
}
