import 'package:flutter/material.dart';
import '../../l10n.dart';

Widget messageSelectionMenu(
  BuildContext context,
  EditableTextState state,
  VoidCallback? select,
) => AdaptiveTextSelectionToolbar.buttonItems(
  anchors: state.contextMenuAnchors,
  buttonItems: [
    ...state.contextMenuButtonItems,
    if (select != null)
      ContextMenuButtonItem(
        label: context.tr('选择消息'),
        onPressed: () {
          ContextMenuController.removeAny();
          select();
        },
      ),
  ],
);
