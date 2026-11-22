import 'package:integration_test/integration_test.dart';
import '../test/agent_model_widgets_test.dart' as agents;
import '../test/session_sync_ui_test.dart' as sync;
import '../test/message_selection_test.dart' as selection;
import '../test/person_widgets_test.dart' as bots;
import '../test/language_test.dart' as language;
import '../test/history_window_sync_test.dart' as history;
import '../test/session_tasks_widgets_test.dart' as tasks;
import '../test/bot_navigation_test.dart' as bot_navigation;
import '../test/chat_rendering_consistency_test.dart' as chat_rendering;
import '../test/chat_reading_parity_test.dart' as chat_reading;
import '../test/group_chat_unification_test.dart' as groups;
import '../test/group_navigation_parity_test.dart' as group_navigation;
import '../test/person_model_settings_test.dart' as bot_settings;

// Native Android/iOS rendering and interaction with controlled API fixtures.
// Real Studio/CLI/model execution is measured by the separate live contracts.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  agents.main();
  sync.main();
  selection.main();
  bots.main();
  language.main();
  history.main();
  tasks.main();
  bot_navigation.main();
  chat_rendering.main();
  chat_reading.main();
  groups.main();
  group_navigation.main();
  bot_settings.main();
}
