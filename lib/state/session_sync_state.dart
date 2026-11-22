import '../data/models.dart';

class ObservedSession {
  const ObservedSession({
    required this.id,
    required this.profile,
    this.working,
    this.unread,
    this.backgroundPending = 0,
    this.lastMessageId = 0,
    this.readMessageId = 0,
    this.lastAttentionId = 0,
    this.readAttentionId = 0,
  });
  final String id, profile;
  final bool? working, unread;
  final int backgroundPending,
      lastMessageId,
      readMessageId,
      lastAttentionId,
      readAttentionId;
  factory ObservedSession.fromJson(Map<String, dynamic> data) =>
      ObservedSession(
        id: text(data['sessionId']),
        profile: text(data['profile']).isEmpty
            ? 'default'
            : text(data['profile']),
        working: data['working'] is bool ? data['working'] as bool : null,
        unread: data['unread'] is bool ? data['unread'] as bool : null,
        backgroundPending: integer(data['backgroundPending']),
        lastMessageId: integer(data['lastMessageId']),
        readMessageId: integer(data['readMessageId']),
        lastAttentionId: integer(data['lastAttentionId']),
        readAttentionId: integer(data['readAttentionId']),
      );
}

/// A connection-local projection. Missing records never delete conversations.
class SessionSyncState {
  // Set only from an ownership-checked Person response in an account-bound controller.
  final allowedPersonSessions = <String>{};
  final sessions = <String, ObservedSession>{};
  int generation = 0;
  bool confirmed = false;
  String profile = 'default';
  final _events = <String>{};
  int reset(String nextProfile, {bool clearEvents = true}) {
    generation++;
    profile = nextProfile;
    sessions.clear();
    if (clearEvents) _events.clear();
    confirmed = false;
    return generation;
  }

  bool _allowed(ObservedSession row) =>
      row.id.isNotEmpty &&
      !row.id.startsWith('person-task-') &&
      (row.id.startsWith('person-main-')
          ? allowedPersonSessions.contains(row.id)
          : row.profile == profile);
  bool snapshot(int connection, dynamic rows) {
    if (connection != generation || rows is! List) return false;
    sessions.clear();
    for (final raw in rows) {
      final row = ObservedSession.fromJson(asMap(raw));
      if (_allowed(row)) sessions[row.id] = row;
    }
    confirmed = true;
    return true;
  }

  bool update(int connection, Map<String, dynamic> data) {
    if (connection != generation || !confirmed) return false;
    final row = ObservedSession.fromJson(data);
    if (!_allowed(row)) return false;
    sessions[row.id] = row;
    return true;
  }

  bool acceptEvent(int connection, String id) {
    if (connection != generation || id.isEmpty || !_events.add(id)) {
      return false;
    }
    if (_events.length > 512) _events.remove(_events.first);
    return true;
  }
}
