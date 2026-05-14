import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_providers.dart';
import '../../../features/chat/providers/chat_providers.dart';
import '../../../models/chat_message.dart';
import '../../../models/group_conversation.dart';
import '../../../services/chat_service.dart';

/// Full group chat screen for a session.
///
/// Shows sender name and avatar on every message (group context — multiple
/// senders). Own messages are right-aligned; others are left-aligned with
/// sender name above the bubble.
class SessionChatScreen extends ConsumerStatefulWidget {
  final String sessionId;

  const SessionChatScreen({super.key, required this.sessionId});

  @override
  ConsumerState<SessionChatScreen> createState() => _SessionChatScreenState();
}

class _SessionChatScreenState extends ConsumerState<SessionChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markRead();
      _jumpToBottom();
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _markRead() async {
    final myUid = ref.read(authStateProvider).valueOrNull?.id;
    if (myUid == null || myUid.isEmpty) return;
    try {
      await ref
          .read(chatServiceProvider)
          .markSessionChatRead(sessionId: widget.sessionId, userId: myUid);
    } catch (_) {
      // Fire-and-forget; silently ignore mark-read failures.
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;

    final currentUser = ref.read(currentUserProvider).valueOrNull;
    if (currentUser == null) return;

    _inputCtrl.clear();

    try {
      await ref
          .read(chatServiceProvider)
          .sendSessionMessage(
            sessionId: widget.sessionId,
            senderId: currentUser.id,
            senderName: currentUser.username,
            senderPhotoUrl: currentUser.profilePhotoUrl,
            text: text,
          );
      _jumpToBottom();
    } on DataException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Insert date-separator sentinels between messages that fall on different
  /// calendar days.
  List<dynamic> _buildItems(List<ChatMessage> msgs) {
    final items = <dynamic>[];
    DateTime? lastDate;
    for (final m in msgs) {
      final d = DateUtils.dateOnly(m.sentAt);
      if (lastDate == null || d != lastDate) {
        items.add(d);
        lastDate = d;
      }
      items.add(m);
    }
    return items;
  }

  String _dateLabel(DateTime d) {
    final today = DateUtils.dateOnly(DateTime.now());
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMMM d, y').format(d);
  }

  /// Resolve the screen title from the group conversation list.
  /// Falls back to "Group Chat" if not yet loaded.
  String _resolveTitle(AsyncValue<List<GroupConversation>> asyncGroups) {
    return asyncGroups.maybeWhen(
      data: (list) {
        try {
          return list
              .firstWhere((g) => g.sessionId == widget.sessionId)
              .sessionTitle;
        } catch (_) {
          return 'Group Chat';
        }
      },
      orElse: () => 'Group Chat',
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncMessages = ref.watch(sessionMessagesProvider(widget.sessionId));
    final asyncGroups = ref.watch(userGroupConversationsProvider);
    final myUid = ref.watch(authStateProvider).valueOrNull?.id ?? '';

    final title = _resolveTitle(asyncGroups);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(title),
      ),
      body: Column(
        children: [
          Expanded(
            child: asyncMessages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Could not load messages. Please try again.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.hint),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return const _EmptyGroupChat();
                }
                final items = _buildItems(messages);
                return ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    if (item is DateTime) {
                      return _DateSeparator(label: _dateLabel(item));
                    }
                    final msg = item as ChatMessage;
                    final isMe = msg.senderId == myUid;
                    return _GroupChatBubble(message: msg, isMe: isMe);
                  },
                );
              },
            ),
          ),
          _InputBar(controller: _inputCtrl, onSend: _send),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyGroupChat extends StatelessWidget {
  const _EmptyGroupChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.group_outlined, size: 48, color: AppColors.disabled),
          const SizedBox(height: 12),
          Text(
            'No messages yet',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.hint),
          ),
          const SizedBox(height: 4),
          Text(
            'Be the first to say hello!',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.hint),
          ),
        ],
      ),
    );
  }
}

// ── Date separator ────────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  final String label;
  const _DateSeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.hint),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }
}

// ── Group chat bubble ─────────────────────────────────────────────────────────

/// Renders a single message bubble with sender name + avatar visible above
/// the bubble for all messages (group context).
///
/// Own messages: right-aligned, accent background, no sender name shown.
/// Others: left-aligned, secondary background, sender name shown above bubble.
class _GroupChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const _GroupChatBubble({required this.message, required this.isMe});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final initial = message.senderName.isNotEmpty
        ? message.senderName[0].toUpperCase()
        : '?';
    final timeStr = DateFormat('h:mm a').format(message.sentAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => context.push('/user/${message.senderId}'),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.secondary,
                backgroundImage:
                    message.senderPhotoUrl != null &&
                        message.senderPhotoUrl!.isNotEmpty
                    ? NetworkImage(message.senderPhotoUrl!)
                    : null,
                child:
                    message.senderPhotoUrl == null ||
                        message.senderPhotoUrl!.isEmpty
                    ? Text(
                        initial,
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      message.senderName,
                      style: tt.labelSmall?.copyWith(
                        color: AppColors.hint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.accent : AppColors.secondary,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                      bottomRight: Radius.circular(isMe ? 4 : 16),
                    ),
                  ),
                  child: Text(
                    message.text,
                    style: tt.bodyMedium?.copyWith(
                      color: isMe ? Colors.white : AppColors.text,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    timeStr,
                    style: tt.labelSmall?.copyWith(color: AppColors.hint),
                  ),
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                isDense: true,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send_rounded),
            color: AppColors.accent,
            onPressed: onSend,
          ),
        ],
      ),
    );
  }
}
