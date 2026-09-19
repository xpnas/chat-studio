import 'package:flutter/material.dart';
import '../../data/models.dart';
import '../../state/app_controller.dart';
import 'agent_avatar.dart';

class ChatTitle extends StatelessWidget {
  const ChatTitle({
    super.key,
    required this.controller,
    required this.title,
    this.agents,
  });
  final AppController controller;
  final String title;
  final List<GroupAgentSummary>? agents;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final participants = agents;
      return Row(
        children: [
          if (participants == null)
            AgentAvatar(controller: controller, size: 25)
          else if (participants.isEmpty)
            const Icon(Icons.groups_outlined, size: 25)
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * .46),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < participants.length; i++)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                        child: Tooltip(
                          message: participants[i].name,
                          child: AgentAvatar(
                            controller: controller,
                            agentId: participants[i].agent,
                            size: 25,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              key: const Key('chat-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    },
  );
}
