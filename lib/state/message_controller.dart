import 'package:flutter/foundation.dart';
import '../data/models.dart';
import '../data/speech_playback.dart';
import '../data/studio_api.dart';

/// The account/session context used by the shared chat presentation widgets.
/// Rendering stays identical while downloads, playback and reconciliation use
/// the conversation's own authorized client.
abstract interface class MessageController implements Listenable {
  StudioApi? get api;
  String get profile;
  bool get messageScopeValid;
  String get messageAgentId;
  String? get messageSenderName;
  SpeechPlayback get speech;
  String audioAttachmentId(MessageAttachment file);
  void playAudioAttachment(MessageAttachment file);
  void reconnect();
}
