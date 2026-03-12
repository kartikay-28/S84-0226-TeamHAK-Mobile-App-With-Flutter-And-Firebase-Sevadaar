import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirrors Firestore `notifications` collection.
/// Written by the app when a notifiable event occurs (task created, progress submitted).
/// Listened to by the recipient to trigger local notifications.
class NotificationModel {
  final String id;
  final String recipientUid; // Who receives this notification
  final String title;
  final String body;
  final String type; // "task" or "progress"
  final String taskId;
  final String? userId; // Volunteer ID (for progress type)
  final bool read;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.recipientUid,
    required this.title,
    required this.body,
    required this.type,
    required this.taskId,
    this.userId,
    this.read = false,
    required this.createdAt,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map, String id) {
    return NotificationModel(
      id: id,
      recipientUid: map['recipientUid'] ?? '',
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      type: map['type'] ?? '',
      taskId: map['taskId'] ?? '',
      userId: map['userId'],
      read: map['read'] ?? false,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'recipientUid': recipientUid,
        'title': title,
        'body': body,
        'type': type,
        'taskId': taskId,
        'userId': userId,
        'read': read,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
