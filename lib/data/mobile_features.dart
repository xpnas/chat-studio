/// Build-time rollback switches; saved conversation identities remain intact.
abstract final class MobileFeatures {
  static const sessionTasks = bool.fromEnvironment(
    'STUDIO_SESSION_TASKS',
    defaultValue: true,
  );
  static const messageSelection = bool.fromEnvironment(
    'STUDIO_MESSAGE_SELECTION',
    defaultValue: true,
  );
  static const bots = bool.fromEnvironment('STUDIO_BOTS', defaultValue: true);
}
