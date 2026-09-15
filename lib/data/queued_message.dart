import 'models.dart';

class QueuedMessage {
  const QueuedMessage(
    this.id,
    this.content, {
    this.status = 'queued',
    this.attachments = const [],
  });
  final String id, content, status;
  final List<MessageAttachment> attachments;
  factory QueuedMessage.fromJson(Map<String, dynamic> json) => QueuedMessage(
    text(json['id'] ?? json['queue_id']),
    messageText(json['content'] ?? json['input']),
  );
  QueuedMessage withStatus(String value) =>
      QueuedMessage(id, content, status: value, attachments: attachments);
}
