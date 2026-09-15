import '../data/studio_protocol.dart';
import '../data/mobile_media.dart';
import '../data/models.dart';
import 'chat_timeline.dart';
import 'dart:async';

/// In-memory UI state belongs to a conversation, not to the selected screen.
class ConversationDraft {
  String text = '';
  double scrollOffset = 0;
  final List<LocalAttachment> files = [];
  final List<MessageAttachment> uploaded = [];
  bool get isEmpty => text.isEmpty && files.isEmpty && uploaded.isEmpty;
}

class ConversationState {
  ConversationState(this.profile);
  final String profile;
  String? id;
  Conversation? conversation;
  final timeline = ChatTimeline();
  final draft = ConversationDraft();
  ModelChoice? model;
  String engine = StudioProtocol.builtInAgentId, reasoningEffort = '';
  bool syncing = false, loading = false, hasMore = false;
  int offset = 0, revision = 0, loadRequest = 0;
  String? historyPageError;
  String? submittedInput, retryInput;
  List<Map<String, dynamic>> submittedAttachments = [], retryAttachments = [];
  DateTime? submittedAt;
  bool awaitingStart = false;
  Timer? runTimer, syncTimer, interactionTimer, responseTimer, queueTimer;

  void cancelTimers() {
    runTimer?.cancel();
    syncTimer?.cancel();
    interactionTimer?.cancel();
    responseTimer?.cancel();
    queueTimer?.cancel();
  }
}

enum ConversationTaskStatus {
  idle,
  running,
  waiting,
  checking,
  completed,
  failed;

  bool get active => this == running || this == waiting || this == checking;
  String get label => switch (this) {
    idle => '',
    running => '任务执行中',
    waiting => '等待确认',
    checking => '任务状态待同步',
    completed => '任务已完成',
    failed => '任务失败',
  };
}
