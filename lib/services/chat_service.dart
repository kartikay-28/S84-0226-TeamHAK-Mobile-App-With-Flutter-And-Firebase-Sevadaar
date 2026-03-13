import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import 'firestore_notification_service.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirestoreNotificationService _notifService = FirestoreNotificationService();

  // ── CREATE GROUP CHAT (For Tasks) ──────────────────────────────────────────‒
  Future<String> createGroupChat({
    required String taskId,
    required String title,
    required String ngoId,
    required List<String> participantIds,
  }) async {
    final ref = _db.collection('chats').doc(taskId);
    await ref.set({
      'type': 'group',
      'taskId': taskId,
      'title': title,
      'ngoId': ngoId,
      'participants': participantIds,
      'lastMessage': 'Group formed.',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'isArchived': false,
    });
    return ref.id;
  }

  // ── CREATE OR GET DIRECT CHAT ──────────────────────────────────────────────
  Future<String> createOrGetDirectChat({
    required String currentUserUid,
    required String targetUserUid,
    required String ngoId,
  }) async {
    // A deterministic ID based on the two UIDs
    final uids = [currentUserUid, targetUserUid]..sort();
    final chatId = '${uids[0]}_${uids[1]}';

    final docSnap = await _db.collection('chats').doc(chatId).get();
    if (!docSnap.exists) {
      await _db.collection('chats').doc(chatId).set({
        'type': 'direct',
        'ngoId': ngoId,
        'participants': uids,
        'lastMessage': 'Say hi!',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'isArchived': false,
      });
    }
    return chatId;
  }

  // ── ADD USER TO GROUP CHAT ──────────────────────────────────────────────────
  Future<void> addUserToGroupChat(String taskId, String newParticipantId) async {
    await _db.collection('chats').doc(taskId).update({
      'participants': FieldValue.arrayUnion([newParticipantId]),
    });
  }

  // ── REMOVE USER FROM GROUP CHAT ──────────────────────────────────────────────
  Future<void> removeUserFromGroupChat(String taskId, String participantId) async {
    await _db.collection('chats').doc(taskId).update({
      'participants': FieldValue.arrayRemove([participantId]),
    });
  }

  // ── SEND MESSAGE ─────────────────────────────────────────────────────────────
  Future<void> sendMessage({
    required String chatId,
    required UserModel sender,
    required String text,
  }) async {
    final chatRef = _db.collection('chats').doc(chatId);
    final messageRef = chatRef.collection('messages').doc();

    final batch = _db.batch();
    
    // Add the message
    batch.set(messageRef, {
      'senderId': sender.uid,
      'senderName': sender.name,
      'senderRole': sender.role,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update the last message in the chat document
    batch.update(chatRef, {
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // Optionally trigger notifications for the chat (Skipping detailed notification payload building for now)
    final chatDoc = await chatRef.get();
    if (chatDoc.exists) {
      final data = chatDoc.data()!;
      List<String> participants = List<String>.from(data['participants'] ?? []);
      participants.remove(sender.uid); // Don't notify sender

      if (participants.isNotEmpty) {
        final chatTitle = data['type'] == 'group' ? data['title'] : sender.name;
        await _notifService.sendToMultiple(
          recipientUids: participants,
          title: 'New message from $chatTitle',
          body: text,
          type: 'chat',
          taskId: data['taskId'], // Only populated for groups
        );
      }
    }
  }

  // ── STREAM CHATS FOR USER ────────────────────────────────────────────────────
  Stream<List<ChatModel>> streamChatsForUser(String uid, String ngoId) {
    return _db
        .collection('chats')
        .where('ngoId', isEqualTo: ngoId)
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => ChatModel.fromMap(d.data(), d.id)).toList(),
        );
  }

  // ── STREAM MESSAGES FOR CHAT ─────────────────────────────────────────────────
  Stream<List<MessageModel>> streamMessages(String chatId) {
    return _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true) // Newest first
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => MessageModel.fromMap(d.data(), d.id)).toList(),
        );
  }
}
