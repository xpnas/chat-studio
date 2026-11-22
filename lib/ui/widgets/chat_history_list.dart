import 'package:flutter/material.dart';

/// One transcript layout for ordinary and mixed BOT histories. Index zero is
/// always the latest item, directly above the composer, including short chats.
class ChatHistoryList extends StatelessWidget {
  const ChatHistoryList({
    super.key,
    this.listKey,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.findChildIndexCallback,
    this.physics,
  });
  final Key? listKey;
  final ScrollController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int? Function(Key)? findChildIndexCallback;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: listKey,
    controller: controller,
    reverse: true,
    physics: physics,
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.symmetric(vertical: 8),
    itemCount: itemCount,
    itemBuilder: itemBuilder,
    findChildIndexCallback: findChildIndexCallback,
  );
}
