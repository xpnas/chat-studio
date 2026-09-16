import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Touch navigation must also work over SelectableText, whose internal
/// horizontal recognizer consumes the gesture arena on Android. Observe touch
/// motion without disabling selection or competing with vertical scrolling.
class ChatSwipeRegion extends StatefulWidget {
  const ChatSwipeRegion({
    super.key,
    required this.child,
    required this.onSwipe,
  });
  final Widget child;
  final ValueChanged<bool> onSwipe;
  @override
  State<ChatSwipeRegion> createState() => _ChatSwipeRegionState();
}

class _ChatSwipeRegionState extends State<ChatSwipeRegion> {
  final _pointers = <int>{};
  int? _candidate;
  Offset _start = Offset.zero;
  Duration _startedAt = Duration.zero;
  bool _horizontal = false;

  void _down(PointerDownEvent event) {
    _pointers.add(event.pointer);
    if (_pointers.length != 1 || event.kind != PointerDeviceKind.touch) {
      _candidate = null;
      return;
    }
    _candidate = event.pointer;
    _start = event.position;
    _startedAt = event.timeStamp;
    _horizontal = false;
  }

  void _move(PointerMoveEvent event) {
    if (_candidate != event.pointer) return;
    final delta = event.position - _start;
    if (!_horizontal) {
      // A held touch belongs to text selection, not navigation. A vertical or
      // diagonal intent stays with the message list even if direction changes.
      if (event.timeStamp - _startedAt >= const Duration(milliseconds: 400)) {
        _candidate = null;
      } else if (delta.distance >= 18) {
        if (delta.dx.abs() > delta.dy.abs() * 1.5) {
          _horizontal = true;
        } else {
          _candidate = null;
        }
      }
    }
  }

  void _up(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    final delta = event.position - _start;
    final navigate =
        _candidate == event.pointer &&
        _horizontal &&
        delta.dx.abs() >= 64 &&
        delta.dx.abs() > delta.dy.abs() * 1.5;
    _candidate = null;
    if (navigate) widget.onSwipe(delta.dx > 0);
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (event) {
          // Code/table horizontal scrolling belongs to the inner scrollable.
          if (event.metrics.axis == Axis.horizontal &&
              (event is ScrollStartNotification ||
                  event is ScrollUpdateNotification)) {
            _candidate = null;
          }
          return false;
        },
        child: Listener(
          key: const Key('chat-drawer-swipe'),
          behavior: HitTestBehavior.translucent,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: (event) {
            _pointers.remove(event.pointer);
            _candidate = null;
          },
          child: widget.child,
        ),
      );
}
