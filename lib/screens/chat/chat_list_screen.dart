import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/user_model.dart';
import '../../models/chat_model.dart';
import '../../state/chat_provider.dart';
import '../../services/task_service.dart';
import 'chat_room_screen.dart';

class _C {
  static const bg = Color(0xFFEEF2F8);
  static const blue = Color(0xFF4A6CF7);
  static const textPri = Color(0xFF0D1B3E);
  static const textSec = Color(0xFF6B7280);
}

class ChatListScreen extends ConsumerWidget {
  final UserModel currentUser;

  const ChatListScreen({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (currentUser.ngoId == null || currentUser.ngoId!.isEmpty) {
      return const Center(child: Text('You are not associated with an NGO yet.'));
    }

    final chatsAsync = ref.watch(userChatsProvider(ChatParams(
      uid: currentUser.uid,
      ngoId: currentUser.ngoId!,
    )));

    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        title: Text(
          'Chats',
          style: GoogleFonts.plusJakartaSans(
            color: _C.textPri,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showStartChatModal(context, ref),
        backgroundColor: _C.blue,
        child: const Icon(Icons.message_rounded, color: Colors.white),
      ),
      body: chatsAsync.when(
        data: (chats) {
          if (chats.isEmpty) {
            return const Center(
              child: Text(
                'No conversations yet.',
                style: TextStyle(color: _C.textSec),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index];
              final isGroup = chat.type == 'group';
              final title = chat.title ?? 'Chat';

              return Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: isGroup ? _C.blue.withValues(alpha:0.1) : Colors.grey.shade200,
                    child: Icon(
                      isGroup ? Icons.groups_rounded : Icons.person_rounded,
                      color: isGroup ? _C.blue : _C.textSec,
                    ),
                  ),
                  title: Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: _C.textPri,
                    ),
                  ),
                  subtitle: Text(
                    chat.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _C.textSec),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(
                          chat: chat,
                          currentUser: currentUser,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  void _showStartChatModal(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final taskService = TaskService(); // using to stream users
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Start a conversation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _C.textPri,
                  ),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<UserModel>>(
                  stream: taskService.streamNgoVolunteers(currentUser.ngoId!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final users = snapshot.data?.where((u) => u.uid != currentUser.uid).toList() ?? [];
                    if (users.isEmpty) {
                      return const Center(child: Text('No other members found.'));
                    }
                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _C.blue.withValues(alpha: 0.1),
                            child: Text(user.name[0].toUpperCase(), style: const TextStyle(color: _C.blue)),
                          ),
                          title: Text(user.name),
                          subtitle: Text(user.role),
                          onTap: () async {
                            Navigator.pop(context);
                            final service = ref.read(chatServiceProvider);
                            final chatId = await service.createOrGetDirectChat(
                              currentUserUid: currentUser.uid,
                              targetUserUid: user.uid,
                              ngoId: currentUser.ngoId!,
                            );
                            
                            // Let's open the chat room. We need a transient ChatModel for navigation, or load it.
                            final tempChat = ChatModel(
                              chatId: chatId,
                              type: 'direct',
                              title: user.name,
                              ngoId: currentUser.ngoId!,
                              participants: [currentUser.uid, user.uid],
                              lastMessage: '',
                              lastMessageTime: DateTime.now(),
                            );
                            if (context.mounted) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatRoomScreen(
                                    chat: tempChat,
                                    currentUser: currentUser,
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
