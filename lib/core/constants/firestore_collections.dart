class FirestoreCollections {
  FirestoreCollections._();
  static const users = 'users';
  static const sessions = 'sessions';
  static const chats = 'chats';
  static const participants = 'participants';
  static const joinRequests = 'joinRequests';
  static const sessionFiles = 'files';
  static const messages = 'messages';
  static const friends = 'friends';
  static const friendRequests = 'friendRequests';

  static const notifications = 'notifications';

  /// Subcollection under sessions/{sessionId}/members/{userId}.
  /// Replaces the old top-level `participants` collection.
  static const members = 'members';

  /// Top-level collection for session member ratings.
  /// Doc ID is deterministic: {sessionId}_{raterId}_{ratedUserId}
  static const ratings = 'ratings';
}