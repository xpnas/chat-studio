import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Capture a visible paragraph's text position before live/history mutations.
/// Restore its screen position after layout, instead of preserving a raw offset.
class ReadingAnchor {
  final keys = <String, GlobalKey>{};
  Key keyFor(String id) => keys.putIfAbsent(id, () => GlobalKey());
  void prune(Set<String> owners) => keys.removeWhere((id, key) {
    if (owners.contains(id)) return false;
    final delimiter = id.lastIndexOf(':');
    return delimiter < 0 || !owners.contains(id.substring(0, delimiter));
  });
  void clear() => keys.clear();
  bool _scheduled = false;
  void preserve(
    ScrollController scroll,
    double viewportTop,
    bool Function() valid,
  ) {
    if (_scheduled || !scroll.hasClients || scroll.offset < 120) return;
    final candidates = keys.values
        .where((k) => k.currentContext?.findRenderObject() is RenderBox)
        .toList();
    GlobalKey? anchor;
    var best = double.infinity;
    final target = viewportTop + 24;
    for (final key in candidates) {
      final box = key.currentContext!.findRenderObject()! as RenderBox;
      if (!box.attached || !box.hasSize) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y + box.size.height < target || y > target + 300) continue;
      final distance = (y - target).abs();
      if (distance < best) {
        anchor = key;
        best = distance;
      }
    }
    if (anchor == null) return;
    final box = anchor.currentContext!.findRenderObject()! as RenderBox;
    final oldY = box.localToGlobal(Offset.zero).dy;
    RenderParagraph? paragraph;
    TextPosition? character;
    double? caretY;
    void inspect(RenderObject object) {
      if (paragraph != null) return;
      if (object is RenderParagraph && object.attached && object.hasSize) {
        final origin = object.localToGlobal(Offset.zero);
        if (origin.dy <= target && origin.dy + object.size.height >= target) {
          paragraph = object;
          character = object.getPositionForOffset(
            Offset(8, target - origin.dy),
          );
          caretY =
              origin.dy + object.getOffsetForCaret(character!, Rect.zero).dy;
          return;
        }
      }
      object.visitChildren(inspect);
    }

    inspect(box);
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!valid() || !scroll.hasClients) return;
      final current = anchor?.currentContext?.findRenderObject();
      if (current is! RenderBox || !current.attached || !current.hasSize) {
        return;
      }
      var delta = current.localToGlobal(Offset.zero).dy - oldY;
      if (paragraph?.attached == true && character != null && caretY != null) {
        delta =
            paragraph!.localToGlobal(Offset.zero).dy +
            paragraph!.getOffsetForCaret(character!, Rect.zero).dy -
            caretY!;
      }
      if (delta.abs() > .5) {
        // Reversed list: increasing pixels moves existing content down.
        scroll.jumpTo(
          (scroll.offset - delta).clamp(
            scroll.position.minScrollExtent,
            scroll.position.maxScrollExtent,
          ),
        );
      }
    });
  }
}
