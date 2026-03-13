import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/chat_service.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService();
});

final userChatsProvider = StreamProvider.family<List<ChatModel>, ChatParams>((ref, params) {
  final service = ref.watch(chatServiceProvider);
  return service.streamChatsForUser(params.uid, params.ngoId);
});

final chatMessagesProvider = StreamProvider.family<List<MessageModel>, String>((ref, chatId) {
  final service = ref.watch(chatServiceProvider);
  return service.streamMessages(chatId);
});

class ChatParams {
  final String uid;
  final String ngoId;

  const ChatParams({required this.uid, required this.ngoId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatParams &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          ngoId == other.ngoId;

  @override
  int get hashCode => uid.hashCode ^ ngoId.hashCode;
}
