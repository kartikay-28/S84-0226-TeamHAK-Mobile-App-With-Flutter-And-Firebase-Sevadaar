import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

/// Writes and reads notification documents in Firestore.
/// Replaces Cloud Functions — notifications are written directly by the app
/// and listened to by recipients to trigger local notifications.
class FirestoreNotificationService {
  FirebaseFirestore? _dbInstance;
  FirebaseFirestore get _db {
    try {
      return _dbInstance ??= FirebaseFirestore.instance;
    } catch (e) {
      throw Exception('Firebase not initialized.');
    }
  }

  /// Write a notification document for a single recipient.
  Future<void> sendNotification({
    required String recipientUid,
    required String title,
    required String body,
    required String type,
    required String taskId,
    String? userId,
  }) async {
    await _db.collection('notifications').add({
      'recipientUid': recipientUid,
      'title': title,
      'body': body,
      'type': type,
      'taskId': taskId,
      'userId': userId,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Send notifications to multiple recipients at once.
  Future<void> sendToMultiple({
    required List<String> recipientUids,
    required String title,
    required String body,
    required String type,
    required String taskId,
    String? userId,
  }) async {
    final batch = _db.batch();
    for (final uid in recipientUids) {
      final ref = _db.collection('notifications').doc();
      batch.set(ref, {
        'recipientUid': uid,
        'title': title,
        'body': body,
        'type': type,
        'taskId': taskId,
        'userId': userId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  /// Notify all volunteers in an NGO about a new task.
  Future<void> notifyVolunteersNewTask({
    required String ngoId,
    required String taskId,
    required String taskTitle,
    String? excludeUid,
  }) async {
    final snap = await _db
        .collection('users')
        .where('ngoId', isEqualTo: ngoId)
        .where('role', isEqualTo: 'volunteer')
        .get();

    final uids = snap.docs
        .map((d) => d.id)
        .where((uid) => uid != excludeUid)
        .toList();

    if (uids.isEmpty) return;

    await sendToMultiple(
      recipientUids: uids,
      title: 'New Task Assigned',
      body: 'You have a new task: $taskTitle',
      type: 'task',
      taskId: taskId,
    );
  }

  /// Notify admins in an NGO about a progress update.
  Future<void> notifyAdminsProgressUpdate({
    required String ngoId,
    required String taskId,
    required String taskTitle,
    required String volunteerId,
    required String volunteerName,
  }) async {
    final snap = await _db
        .collection('users')
        .where('ngoId', isEqualTo: ngoId)
        .where('role', whereIn: ['admin', 'super_admin'])
        .get();

    final uids = snap.docs.map((d) => d.id).toList();

    if (uids.isEmpty) return;

    await sendToMultiple(
      recipientUids: uids,
      title: 'Progress Update',
      body: '$volunteerName submitted a progress update for "$taskTitle"',
      type: 'progress',
      taskId: taskId,
      userId: volunteerId,
    );
  }

  /// Stream unread notifications for a user (for local notification display).
  Stream<List<NotificationModel>> streamUnreadNotifications(String uid) {
    return _db
        .collection('notifications')
        .where('recipientUid', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => NotificationModel.fromMap(d.data(), d.id))
          .toList();
      // Sort client-side to avoid needing a 3-field composite index
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  /// Mark a notification as read.
  Future<void> markAsRead(String notificationId) async {
    await _db
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }
}
