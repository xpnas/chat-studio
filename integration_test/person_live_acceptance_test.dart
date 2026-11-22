import 'package:integration_test/integration_test.dart';
import '../test/person_live_contract_test.dart' as live;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  live.main();
}
