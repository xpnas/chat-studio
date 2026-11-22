import 'dart:async';
import 'package:flutter/material.dart';
import '../../l10n.dart';
import '../../state/conversation_state.dart';
import '../../data/speech_playback.dart';
import 'reading_anchor.dart';
import 'reading_handle.dart';

/// Only conversation data and protocol operations vary between chat types.
class ChatReadingSnapshot {
  const ChatReadingSnapshot({
    required this.id,
    required this.draft,
    required this.messageCount,
    required this.liveRevision,
    this.readingOlder = false,
    this.hasNewer = false,
    this.canLoadEarlier = false,
  });
  final Object? id, liveRevision;
  final ConversationDraft draft;
  final int messageCount;
  final bool readingOlder, hasNewer, canLoadEarlier;
}

/// One reading interaction for single, group and BOT conversations. Protocol
/// adapters retain ownership of history, sends, approvals and read receipts.
mixin ChatReadingState<T extends StatefulWidget> on State<T> {
  ChatReadingSnapshot get readingSnapshot;
  bool get readingRouteVisible;
  bool get readingHintSeen;
  Future<void> markReadingHintSeen();
  void beginHistoryReading();
  Future<void> showLatestHistory();
  Future<void> loadEarlierHistory();
  Future<void> confirmLatestVisible();

  final readingScroll = ScrollController();
  final readingProgress = ValueNotifier<double>(0);
  final readingAnchors = ReadingAnchor();
  final readingStageKey = GlobalKey();
  Object? _lastSession, _liveRevision;
  ConversationDraft? _lastDraft;
  bool _restoringView = false,
      _historyScheduled = false,
      _readScheduled = false;
  int _lastLength = 0, _gestureRevision = 0, _hintSerial = 0;
  bool _userScrolling = false, _hintOffered = false;
  bool _jumpingToLatest = false;
  bool composerCollapsed = false, showReadingJump = false;
  bool hasNewReadingContent = false, showReadingHint = false;
  Timer? _hintTimer;

  void initReading({bool restoreInitial = false}) {
    final view = readingSnapshot;
    _lastSession = view.id;
    _lastDraft = view.draft;
    _lastLength = view.messageCount;
    _liveRevision = view.liveRevision;
    readingScroll.addListener(readingScrollChanged);
    if (restoreInitial) _restoreDraft(view.draft);
    scheduleEarlierHistory();
    scheduleReadReceipt();
  }

  void readingScrollChanged() {
    if (!mounted || !readingScroll.hasClients) return;
    readingProgress.value = historyReadProgress(readingScroll.position);
    scheduleEarlierHistory();
    scheduleReadReceipt();
    if (!_restoringView && identical(_lastDraft, readingSnapshot.draft)) {
      readingSnapshot.draft.scrollOffset = readingScroll.offset;
    }
    final pixels = readingScroll.offset.clamp(
      readingScroll.position.minScrollExtent,
      readingScroll.position.maxScrollExtent,
    );
    final jump = pixels > 220;
    final restore = composerCollapsed && pixels <= 24;
    if (jump != showReadingJump ||
        restore ||
        (pixels <= 24 && hasNewReadingContent)) {
      setState(() {
        if (pixels <= 24) hasNewReadingContent = false;
        showReadingJump = jump;
        if (restore) composerCollapsed = false;
      });
    }
  }

  void scheduleReadReceipt() {
    if (!mounted || _readScheduled) return;
    _readScheduled = true;
    final view = readingSnapshot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readScheduled = false;
      if (!mounted ||
          view.id != readingSnapshot.id ||
          !identical(view.draft, readingSnapshot.draft) ||
          _restoringView ||
          _jumpingToLatest ||
          _userScrolling ||
          !readingRouteVisible ||
          !readingScroll.hasClients ||
          !readingScroll.position.hasContentDimensions) {
        return;
      }
      if (readingScroll.offset > 120) {
        beginHistoryReading();
      } else if (readingScroll.offset <= 24) {
        if (readingSnapshot.readingOlder) {
          unawaited(showLatestHistory());
        } else {
          unawaited(confirmLatestVisible());
        }
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void scheduleEarlierHistory() {
    if (!mounted || _historyScheduled) return;
    _historyScheduled = true;
    final draft = readingSnapshot.draft;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyScheduled = false;
      if (!mounted ||
          !identical(draft, readingSnapshot.draft) ||
          _restoringView ||
          !readingScroll.hasClients ||
          !readingScroll.position.hasContentDimensions ||
          !readingSnapshot.canLoadEarlier) {
        return;
      }
      if (readingScroll.position.extentAfter <= 240) {
        unawaited(loadEarlierHistory());
      }
    });
  }

  bool chatScrolled(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _gestureRevision++;
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _userScrolling = false;
      scheduleReadReceipt();
    } else if (notification is ScrollUpdateNotification &&
        _userScrolling &&
        (notification.scrollDelta ?? 0) > 0 &&
        notification.metrics.pixels > 160 &&
        !composerCollapsed &&
        readingSnapshot.messageCount > 0) {
      setState(() => composerCollapsed = true);
      _offerReadingHint();
    }
    return false;
  }

  void _offerReadingHint() {
    if (_hintOffered || readingHintSeen) return;
    _hintOffered = true;
    final serial = ++_hintSerial;
    unawaited(markReadingHintSeen());
    setState(() => showReadingHint = true);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && serial == _hintSerial) {
        setState(() => showReadingHint = false);
      }
    });
  }

  void expandReadingComposer() {
    _userScrolling = false;
    setState(() => composerCollapsed = false);
  }

  Future<void> jumpToLatest() async {
    if (_jumpingToLatest) return;
    final view = readingSnapshot, gesture = _gestureRevision;
    _jumpingToLatest = true;
    _userScrolling = false;
    setState(() => composerCollapsed = false);
    bool valid() =>
        mounted &&
        readingSnapshot.id == view.id &&
        identical(readingSnapshot.draft, view.draft) &&
        gesture == _gestureRevision;
    try {
      await showLatestHistory();
      await WidgetsBinding.instance.endOfFrame;
      if (!valid() || !readingScroll.hasClients) return;
      await readingScroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      await WidgetsBinding.instance.endOfFrame;
      // The editor expands and the latest projection can arrive during the
      // animation. Finish at the latest edge after their final layout.
      if (valid() && readingScroll.hasClients) readingScroll.jumpTo(0);
    } finally {
      _jumpingToLatest = false;
      if (mounted) scheduleReadReceipt();
    }
  }

  void _restoreDraft(ConversationDraft draft) {
    _restoringView = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(readingSnapshot.draft, draft)) return;
      if (readingScroll.hasClients) {
        readingScroll.jumpTo(
          draft.scrollOffset.clamp(0, readingScroll.position.maxScrollExtent),
        );
      }
      _restoringView = false;
      readingScrollChanged();
      scheduleEarlierHistory();
      scheduleReadReceipt();
    });
  }

  void readingChanged() {
    if (!mounted) return;
    scheduleEarlierHistory();
    scheduleReadReceipt();
    final view = readingSnapshot, gesture = _gestureRevision;
    final liveChanged = view.liveRevision != _liveRevision;
    if (view.hasNewer) hasNewReadingContent = true;
    if (view.id == _lastSession &&
        !_jumpingToLatest &&
        !_userScrolling &&
        readingStageKey.currentContext != null) {
      final box =
          readingStageKey.currentContext!.findRenderObject() as RenderBox;
      readingAnchors.preserve(
        readingScroll,
        box.localToGlobal(Offset.zero).dy,
        () =>
            mounted &&
            readingSnapshot.id == view.id &&
            !_jumpingToLatest &&
            gesture == _gestureRevision &&
            !_userScrolling,
      );
    }
    if (liveChanged) {
      if (readingScroll.hasClients && readingScroll.offset > 120) {
        hasNewReadingContent = true;
      }
      _liveRevision = view.liveRevision;
    }
    if (_lastSession != view.id || !identical(_lastDraft, view.draft)) {
      if (readingScroll.hasClients && !_restoringView) {
        _lastDraft?.scrollOffset = readingScroll.offset;
      }
      _lastSession = view.id;
      _lastDraft = view.draft;
      _liveRevision = view.liveRevision;
      readingAnchors.clear();
      hasNewReadingContent = false;
      showReadingHint = false;
      _hintSerial++;
      readingProgress.value = 0;
      composerCollapsed = false;
      _userScrolling = false;
      _lastLength = view.messageCount;
      _restoreDraft(view.draft);
      return;
    }
    if (view.messageCount != _lastLength) {
      _lastLength = view.messageCount;
      if (!_jumpingToLatest &&
          readingScroll.hasClients &&
          readingScroll.offset < 120) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              readingSnapshot.id == view.id &&
              gesture == _gestureRevision &&
              !_userScrolling &&
              readingScroll.hasClients &&
              readingScroll.offset < 120) {
            readingScroll.animateTo(
              0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }
  }

  Widget readingLayout({
    required Widget history,
    required Widget editor,
    Widget? handle,
    Widget? stop,
    required Widget Function(Widget) wrapReading,
    List<Widget> footer = const [],
  }) => ChatReadingLayout(
    stageKey: readingStageKey,
    history: history,
    editor: editor,
    handle: handle,
    stop: stop,
    wrapReading: wrapReading,
    onScroll: chatScrolled,
    onMetrics: readingScrollChanged,
    showHint: showReadingHint,
    showJump: showReadingJump,
    hasNewContent: hasNewReadingContent,
    onJump: jumpToLatest,
    footer: footer,
  );

  void disposeReading() {
    readingScroll.dispose();
    readingProgress.dispose();
    _hintTimer?.cancel();
    _hintSerial++;
  }
}

class ChatBody extends StatelessWidget {
  const ChatBody({super.key, required this.child, this.notices = const []});
  final Widget child;
  final List<Widget> notices;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Column(
          children: [
            ...notices,
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

class ChatConnectionLine extends StatelessWidget {
  const ChatConnectionLine({
    super.key,
    required this.connected,
    required this.syncing,
    required this.onReconnect,
  });
  final bool connected, syncing;
  final VoidCallback onReconnect;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = !connected || syncing;
    return Semantics(
      container: true,
      label: context.tr(
        syncing
            ? '正在同步对话状态…'
            : connected
            ? '聊天已连接'
            : '正在连接聊天服务…',
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: connected ? null : onReconnect,
        child: LinearProgressIndicator(
          minHeight: 2,
          value: active ? (syncing ? .62 : .22) : 0,
          color: active
              ? (syncing ? colors.primary : colors.tertiary)
              : colors.primary.withValues(alpha: .18),
          backgroundColor: colors.surfaceContainerHighest.withValues(
            alpha: .32,
          ),
        ),
      ),
    );
  }
}

class ChatReadingLayout extends StatelessWidget {
  const ChatReadingLayout({
    super.key,
    required this.stageKey,
    required this.history,
    required this.editor,
    this.handle,
    this.stop,
    required this.wrapReading,
    required this.onScroll,
    required this.onMetrics,
    required this.showHint,
    required this.showJump,
    required this.hasNewContent,
    required this.onJump,
    this.footer = const [],
  });
  final GlobalKey stageKey;
  final Widget history, editor;
  final Widget? handle, stop;
  final Widget Function(Widget) wrapReading;
  final bool Function(ScrollNotification) onScroll;
  final VoidCallback onMetrics;
  final bool showHint, showJump, hasNewContent;
  final Future<void> Function() onJump;
  final List<Widget> footer;
  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          onMetrics();
          return false;
        },
        child: Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: onScroll,
                child: wrapReading(
                  SizedBox.expand(
                    key: const Key('reading-stage'),
                    child: Stack(
                      key: stageKey,
                      children: [
                        history,
                        if (showHint && handle != null)
                          Positioned(
                            left: 45,
                            right: 45,
                            bottom: 72,
                            child: IgnorePointer(
                              child: Center(
                                child: Material(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: .94),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      context.tr('轻点底部线条，继续输入'),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (handle != null)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 10,
                            child: Center(
                              child: RepaintBoundary(child: handle!),
                            ),
                          ),
                        if (stop != null)
                          Positioned(
                            right: 20,
                            bottom: showJump ? 70 : 12,
                            child: stop!,
                          ),
                        if (showJump)
                          Positioned(
                            bottom: 12,
                            right: 20,
                            child: FloatingActionButton.small(
                              heroTag: 'jump',
                              tooltip: context.tr('回到最新消息'),
                              onPressed: onJump,
                              child: Badge(
                                isLabelVisible: hasNewContent,
                                label: Text(context.tr('新')),
                                child: const Icon(Icons.arrow_downward_rounded),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ...footer,
            editor,
          ],
        ),
      );
}

class ChatSpeechStatus extends StatelessWidget {
  const ChatSpeechStatus({super.key, required this.speech});
  final SpeechPlayback speech;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: speech,
    builder: (context, _) => speech.activeId != null
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.audiotrack_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr(speech.loading ? '正在加载语音…' : '正在播放语音'),
                  ),
                ),
                TextButton(
                  onPressed: () => speech.stop(),
                  child: Text(context.tr(speech.loading ? '取消' : '停止播放')),
                ),
              ],
            ),
          )
        : speech.error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              speech.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
  );
}

class ChatActivityStatus extends StatelessWidget {
  const ChatActivityStatus({
    super.key,
    required this.working,
    required this.activity,
  });
  final bool working;
  final String activity;
  @override
  Widget build(BuildContext context) => !working || activity.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Row(
            children: [
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  activity,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
}
