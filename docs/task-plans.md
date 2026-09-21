# Agent task plans

When the connected Studio server emits a structured task-plan event, Chat Studio presents it as a compact card in the conversation.

The card can show:

- the plan title;
- completed and total steps;
- the active step;
- pending, running, completed, failed, or skipped states;
- an expanded view of individual steps;
- completion, interruption, or failure information.

Task plans are optional. A normal answer or an Agent that does not emit the structured contract does not display a card. The client does not infer plans from model prose, tool arguments, or reasoning text.

Plans are associated with the conversation and are restored from the server conversation snapshot or live events. Server event revisions are used to avoid applying stale updates after reconnecting or returning from the background.
