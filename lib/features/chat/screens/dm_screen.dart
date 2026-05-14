import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_exceptions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../features/auth/providers/auth_providers.dart';
import '../../../features/chat/providers/chat_providers.dart';
import '../../../models/chat_message.dart';
import '../../../models/dm_conversation.dart';
import '../../../services/chat_service.dart';

class DmScreen extends ConsumerStatefulWidget {
  final String conversationId;

  const DmScreen({super.key, required this.conversationId});

  @override
  ConsumerState<DmScreen> createState() => _DmScreenState();
}

class _DmScreenState extends ConsumerState<DmScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Mark conversation as read after the first frame so the listener is
    // attached and the unread badge disappears immediately.
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
          .markDmRead(conversationId: widget.conversationId, userId: myUid);
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
          .sendDmMessage(
            conversationId: widget.conversationId,
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

  List<dynamic> _buildItems(List<ChatMessage> msgs) {
    // Messages from Firestore are already ordered by sentAt ASC.
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

  /// Build the header title from the conversation metadata.
  /// Falls back to the conversation id if metadata is not yet loaded.
  Widget _buildTitle(
    BuildContext context,
    DmConversation? convo,
    String myUid,
  ) {
    // Derive the other user's uid from participantIds.
    // NOTE: Display name/avatar are not yet denormalized on the chats doc.
    // firebase-specialist should add otherUserName + otherUserPhotoUrl fields
    // so the header shows a real name instead of the uid.
    final otherUid =
        convo?.participantIds
            .firstWhere((id) => id != myUid, orElse: () => '')
            .toString() ??
        '';
    final displayLabel = otherUid.isNotEmpty ? otherUid : widget.conversationId;
    final initial = displayLabel.isNotEmpty
        ? displayLabel[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: otherUid.isNotEmpty ? () => context.push('/user/$otherUid') : null,
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.secondary,
            child: Text(
              initial,
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayLabel,
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  otherUid.isNotEmpty ? 'Tap to view profile' : '',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: AppColors.hint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncMessages = ref.watch(dmMessagesProvider(widget.conversationId));
    final myUid = ref.watch(authStateProvider).valueOrNull?.id ?? '';
    final convo = ref.watch(dmConversationByIdProvider(widget.conversationId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: _buildTitle(context, convo, myUid),
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
                  return _EmptyDm(
                    label:
                        convo?.participantIds
                            .firstWhere(
                              (id) => id != myUid,
                              orElse: () => 'your friend',
                            )
                            .toString() ??
                        'your friend',
                  );
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
                    return _ChatBubble(message: msg, isMe: isMe);
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

class _EmptyDm extends StatelessWidget {
  final String label;
  const _EmptyDm({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.waving_hand_outlined,
            size: 48,
            color: AppColors.disabled,
          ),
          const SizedBox(height: 12),
          Text(
            'Say hi to $label!',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.hint),
          ),
        ],
      ),
    );
  }
}

// ── Chat widgets ──────────────────────────────────────────────────────────────

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

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  const _ChatBubble({required this.message, required this.isMe});

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

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _InputBar({required this.controller, required this.onSend});

  void _showAttachOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.image_outlined,
                    color: AppColors.accent,
                  ),
                ),
                title: const Text('Send Image'),
                subtitle: const Text('Share a photo from your gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Image picker coming soon'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.attach_file_rounded,
                    color: AppColors.accent,
                  ),
                ),
                title: const Text('Send File'),
                subtitle: const Text('Share a document or PDF'),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('File picker coming soon'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

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
          GestureDetector(
            onTap: () => _showAttachOptions(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, color: AppColors.accent, size: 20),
            ),
          ),
          const SizedBox(width: 8),
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
