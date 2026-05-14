import 'enums.dart';

/// View-model returned by [ChatService.watchMyGroupConversations].
///
/// Combines denormalized fields from the member doc (sessionTitle,
/// sessionSubject, sessionStatus) with last-message metadata from
/// sessions/{sessionId}/groupChat/meta.
///
/// This is a read-only view-model for the Groups tab. It is NOT stored in
/// Firestore directly; it is assembled in memory by the chat service.
class GroupConversation {
  final String sessionId;
  final String sessionTitle;
  final Subject sessionSubject;
  final SessionStatus sessionStatus;

  /// Preview text of the last message in the group chat, or null if no
  /// messages have been sent yet.
  final String? lastMessageText;

  /// Server timestamp of the last message. Used for sorting DESC.
  /// Null if the groupChat/meta doc has no lastMessageAt yet.
  final DateTime? lastMessageAt;

  /// Unread message count for the current user in this group chat.
  final int unreadCountForMe;

  const GroupConversation({
    required this.sessionId,
    required this.sessionTitle,
    required this.sessionSubject,
    required this.sessionStatus,
    this.lastMessageText,
    this.lastMessageAt,
    required this.unreadCountForMe,
  });

  GroupConversation copyWith({
    String? sessionTitle,
    Subject? sessionSubject,
    SessionStatus? sessionStatus,
    String? lastMessageText,
    DateTime? lastMessageAt,
    int? unreadCountForMe,
  }) {
    return GroupConversation(
      sessionId: sessionId,
      sessionTitle: sessionTitle ?? this.sessionTitle,
      sessionSubject: sessionSubject ?? this.sessionSubject,
      sessionStatus: sessionStatus ?? this.sessionStatus,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCountForMe: unreadCountForMe ?? this.unreadCountForMe,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupConversation &&
          runtimeType == other.runtimeType &&
          sessionId == other.sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}
