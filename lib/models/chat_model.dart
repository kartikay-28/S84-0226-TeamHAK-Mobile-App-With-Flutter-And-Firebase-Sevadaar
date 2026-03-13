import 'package:cloud_firestore/cloud_firestore.dart';

class ChatModel {
  final String chatId;
  final String type; // 'group' or 'direct'
  final String? taskId; // only for 'group' tasks
  final String? title; // Group title or individual name placeholder
  final String ngoId;
  final List<String> participants;
  final String lastMessage;
  final DateTime lastMessageTime;
  final bool isArchived;

  const ChatModel({
    required this.chatId,
    required this.type,
    this.taskId,
    this.title,
    required this.ngoId,
    required this.participants,
    this.lastMessage = '',
    required this.lastMessageTime,
    this.isArchived = false,
  });

  factory ChatModel.fromMap(Map<String, dynamic> map, String id) {
    return ChatModel(
      chatId: id,
      type: map['type'] ?? 'direct',
      taskId: map['taskId'],
      title: map['title'],
      ngoId: map['ngoId'] ?? '',
      participants: List<String>.from(map['participants'] ?? []),
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: (map['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isArchived: map['isArchived'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      if (taskId != null) 'taskId': taskId,
      if (title != null) 'title': title,
      'ngoId': ngoId,
      'participants': participants,
      'lastMessage': lastMessage,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'isArchived': isArchived,
    };
  }
}
