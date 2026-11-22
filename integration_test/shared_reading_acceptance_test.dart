import 'package:integration_test/integration_test.dart';
import '../test/chat_reading_parity_test.dart' as reading;
import '../test/group_navigation_parity_test.dart' as navigation;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  reading.main();
  navigation.main();
}
