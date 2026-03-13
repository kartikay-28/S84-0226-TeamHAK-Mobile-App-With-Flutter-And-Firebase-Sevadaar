import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task_model.dart';
import '../models/task_assignment_model.dart';
import '../models/progress_request_model.dart';
import '../models/user_model.dart';
import 'firestore_notification_service.dart';
import 'chat_service.dart';

class TaskService {
  FirebaseFirestore? _dbInstance;
  FirebaseFirestore get _db {
    try {
      return _dbInstance ??= FirebaseFirestore.instance;
    } catch (e) {
      throw Exception('Firebase not initialized.');
    }
  }

  final FirestoreNotificationService _notifService =
      FirestoreNotificationService();
  final ChatService _chatService = ChatService();

  String _assignmentId(String taskId, String volunteerId) =>
      '${taskId}_$volunteerId';

  // ── CREATE TASK ───────────────────────────────────────────────
  Future<String> createTask({
    required String title,
    required String description,
    required String adminId,
    required String ngoId,
    required int maxVolunteers,
    required DateTime deadline,
  }) async {
    final ref = _db.collection('tasks').doc();
    await ref.set({
      'title': title,
      'description': description,
      'adminId': adminId,
      'ngoId': ngoId,
      'maxVolunteers': maxVolunteers,
      'assignedVolunteers': [],
      'pendingInvites': [],
      'declinedBy': [],
      'status': 'inviting',
      'mainProgress': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
      'deadline': Timestamp.fromDate(deadline),
      'inviteDeadline': Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24))),
      'adminFinalNote': '',
    });

    // Notify all volunteers in the NGO about the new task
    await _notifService.notifyVolunteersNewTask(
      ngoId: ngoId,
      taskId: ref.id,
      taskTitle: title,
      excludeUid: adminId,
    );

    // Automatically create a group chat for the task
    await _chatService.createGroupChat(
      taskId: ref.id,
      title: title,
      ngoId: ngoId,
      participantIds: [adminId], // Only the admin at creation
    );

    return ref.id;
  }

  // ── STREAMS ───────────────────────────────────────────────────
  Stream<List<TaskModel>> streamAdminTasks(String adminId) {
    return _db
        .collection('tasks')
        .where('adminId', isEqualTo: adminId)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => TaskModel.fromMap(d.data(), d.id)).toList(),
        );
  }

  Stream<List<ProgressRequestModel>> streamPendingRequestsForAdmin(
    String adminId,
  ) {
    return _db
        .collection('progress_requests')
        .where('adminId', isEqualTo: adminId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ProgressRequestModel.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Stream<List<TaskAssignmentModel>> streamTaskAssignments(String taskId) {
    return _db
        .collection('task_assignments')
        .where('taskId', isEqualTo: taskId)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => TaskAssignmentModel.fromMap(d.data(), d.id))
              .toList(),
        );
  }

  Stream<TaskModel?> streamTask(String taskId) {
    return _db.collection('tasks').doc(taskId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return TaskModel.fromMap(doc.data()!, doc.id);
    });
  }

  Stream<List<UserModel>> streamNgoVolunteers(String ngoId) {
    return _db
        .collection('users')
        .where('ngoId', isEqualTo: ngoId)
        .where('role', isEqualTo: 'volunteer')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => UserModel.fromMap(d.data(), d.id)).toList(),
        );
  }

  // ── INVITE VOLUNTEERS ─────────────────────────────────────────
  Future<void> inviteVolunteers(
    String taskId,
    List<String> volunteerIds,
  ) async {
    await _db.collection('tasks').doc(taskId).update({
      'pendingInvites': FieldValue.arrayUnion(volunteerIds),
    });

    // Send notification to each invited volunteer
    final taskDoc = await _db.collection('tasks').doc(taskId).get();
    if (taskDoc.exists) {
      final taskTitle = taskDoc.data()!['title'] as String? ?? 'a task';
      await _notifService.sendToMultiple(
        recipientUids: volunteerIds,
        title: 'New Task Invitation',
        body: 'You have been invited to: $taskTitle',
        type: 'task',
        taskId: taskId,
      );
    }
  }

  Future<void> cancelInvite(String taskId, String volunteerId) async {
    await _db.collection('tasks').doc(taskId).update({
      'pendingInvites': FieldValue.arrayRemove([volunteerId]),
    });
  }

  // ── APPROVE PROGRESS REQUEST ──────────────────────────────────
  Future<void> approveProgressRequest(ProgressRequestModel request) async {
    final assignSnap = await _db
        .collection('task_assignments')
        .where('taskId', isEqualTo: request.taskId)
        .where('volunteerId', isEqualTo: request.volunteerId)
        .limit(1)
        .get();

    if (assignSnap.docs.isEmpty) {
      throw Exception('Assignment not found for this volunteer.');
    }

    final assignmentRef = assignSnap.docs.first.reference;

    final batch = _db.batch();
    batch.update(assignmentRef, {
      'individualProgress': request.requestedProgress,
    });
    batch.update(_db.collection('progress_requests').doc(request.requestId), {
      'status': 'approved',
    });
    await batch.commit();

    await _recalculateMainProgress(request.taskId);
  }

  // ── REJECT PROGRESS REQUEST ───────────────────────────────────
  Future<void> rejectProgressRequest(ProgressRequestModel request) async {
    await _db.collection('progress_requests').doc(request.requestId).update({
      'status': 'rejected',
    });
  }

  // ── REMOVE VOLUNTEER FROM TASK ────────────────────────────────
  Future<void> removeVolunteer(String taskId, String volunteerId) async {
    final assignSnap = await _db
        .collection('task_assignments')
        .where('taskId', isEqualTo: taskId)
        .where('volunteerId', isEqualTo: volunteerId)
        .limit(1)
        .get();

    final batch = _db.batch();

    if (assignSnap.docs.isNotEmpty) {
      batch.delete(assignSnap.docs.first.reference);
    }

    batch.update(_db.collection('tasks').doc(taskId), {
      'assignedVolunteers': FieldValue.arrayRemove([volunteerId]),
    });

    final pendingReqs = await _db
        .collection('progress_requests')
        .where('taskId', isEqualTo: taskId)
        .where('volunteerId', isEqualTo: volunteerId)
        .where('status', isEqualTo: 'pending')
        .get();

    for (final doc in pendingReqs.docs) {
      batch.update(doc.reference, {'status': 'rejected'});
    }

    await batch.commit();

    // Remove user from the group chat
    await _chatService.removeUserFromGroupChat(taskId, volunteerId);

    await _recalculateMainProgress(taskId);
  }

  // ── COMPLETE TASK ─────────────────────────────────────────────
  Future<void> completeTask(String taskId, String finalNote) async {
    final batch = _db.batch();
    batch.update(_db.collection('tasks').doc(taskId), {
      'status': 'completed',
      'adminFinalNote': finalNote,
      'mainProgress': 100.0,
    });

    final chatSnap = await _db
        .collection('chats')
        .where('taskId', isEqualTo: taskId)
        .limit(1)
        .get();

    if (chatSnap.docs.isNotEmpty) {
      batch.update(chatSnap.docs.first.reference, {'isArchived': true});
    }

    await batch.commit();
  }

  // ── VOLUNTEER STREAMS ──────────────────────────────────────────

  /// All tasks belonging to an NGO.
  Stream<List<TaskModel>> streamNgoTasks(String ngoId) {
    return _db
        .collection('tasks')
        .where('ngoId', isEqualTo: ngoId)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TaskModel.fromMap(d.data(), d.id)).toList());
  }

  /// Tasks where the volunteer is in assignedVolunteers.
  Stream<List<TaskModel>> streamVolunteerAssignedTasks(String volunteerId) {
    return _db
        .collection('tasks')
        .where('assignedVolunteers', arrayContains: volunteerId)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TaskModel.fromMap(d.data(), d.id)).toList());
  }

  /// Tasks the volunteer can respond to: all 'inviting' tasks in their NGO
  /// that they haven't already joined or declined.
  Stream<List<TaskModel>> streamVolunteerInvites(
    String volunteerId, {
    String? ngoId,
  }) {
    // When we know the NGO, show every open invitation for that NGO
    // so newly-joined volunteers see existing tasks.
    if (ngoId != null && ngoId.isNotEmpty) {
      return _db
          .collection('tasks')
          .where('ngoId', isEqualTo: ngoId)
          .where('status', isEqualTo: 'inviting')
          .snapshots()
          .map((snap) => snap.docs
              .map((d) => TaskModel.fromMap(d.data(), d.id))
              .where((t) =>
                  !t.assignedVolunteers.contains(volunteerId) &&
                  !t.declinedBy.contains(volunteerId))
              .toList());
    }
    // Fallback: only explicitly invited tasks.
    return _db
        .collection('tasks')
        .where('pendingInvites', arrayContains: volunteerId)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => TaskModel.fromMap(d.data(), d.id)).toList());
  }

  /// Get the volunteer's individual assignment for a task.
  Future<TaskAssignmentModel?> getVolunteerAssignment(
    String taskId,
    String volunteerId,
  ) async {
    final doc = await _db
        .collection('task_assignments')
        .doc(_assignmentId(taskId, volunteerId))
        .get();
    if (!doc.exists) return null;
    return TaskAssignmentModel.fromMap(doc.data()!, doc.id);
  }

  /// Stream the volunteer's assignment for a specific task.
  Stream<TaskAssignmentModel?> streamVolunteerAssignment(
    String taskId,
    String volunteerId,
  ) {
    return _db
        .collection('task_assignments')
        .doc(_assignmentId(taskId, volunteerId))
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return TaskAssignmentModel.fromMap(doc.data()!, doc.id);
    });
  }

  // ── ACCEPT / DECLINE INVITATIONS ──────────────────────────────

  /// Volunteer accepts an invitation: move from pendingInvites → assignedVolunteers
  /// and create a task_assignment document.
  Future<void> acceptInvite(String taskId, String volunteerId) async {
    final taskRef = _db.collection('tasks').doc(taskId);
    final assignRef =
        _db.collection('task_assignments').doc(_assignmentId(taskId, volunteerId));

    await _db.runTransaction((tx) async {
      final taskDoc = await tx.get(taskRef);
      if (!taskDoc.exists) throw Exception('Task not found.');

      final task = TaskModel.fromMap(taskDoc.data()!, taskDoc.id);
      final isAlreadyAssigned = task.assignedVolunteers.contains(volunteerId);
      final currentAssignedCount = task.assignedVolunteers.length;

      if (!isAlreadyAssigned && currentAssignedCount >= task.maxVolunteers) {
        throw Exception('Task is full.');
      }
      if (task.status == 'completed') {
        throw Exception('Task is already completed.');
      }

      final updates = <String, dynamic>{
        'pendingInvites': FieldValue.arrayRemove([volunteerId]),
      };

      if (!isAlreadyAssigned) {
        updates['assignedVolunteers'] = FieldValue.arrayUnion([volunteerId]);
      }

      final assignedCountAfter =
          isAlreadyAssigned ? currentAssignedCount : currentAssignedCount + 1;
      if (task.status == 'inviting' && assignedCountAfter >= task.maxVolunteers) {
        updates['status'] = 'active';
      }

      tx.update(taskRef, updates);
      tx.set(assignRef, {
        'taskId': taskId,
        'volunteerId': volunteerId,
        'individualProgress': 0.0,
      }, SetOptions(merge: true));
    });

    // Check if we need to add to chat outside transaction via quick fetch or assume since transaction succeeded
    // Actually in acceptInvite we add them:
    await _chatService.addUserToGroupChat(taskId, volunteerId);
  }

  /// Volunteer declines an invitation.
  Future<void> declineInvite(String taskId, String volunteerId) async {
    await _db.collection('tasks').doc(taskId).update({
      'pendingInvites': FieldValue.arrayRemove([volunteerId]),
      'declinedBy': FieldValue.arrayUnion([volunteerId]),
    });
  }

  // ── JOIN / DISMISS TASK (from NGO Tasks) ──────────────────────

  /// Volunteer joins a task directly (not through invitation).
  Future<void> joinTask(String taskId, String volunteerId) async {
    final taskRef = _db.collection('tasks').doc(taskId);
    final assignRef =
        _db.collection('task_assignments').doc(_assignmentId(taskId, volunteerId));

    await _db.runTransaction((tx) async {
      final taskDoc = await tx.get(taskRef);
      if (!taskDoc.exists) throw Exception('Task not found.');

      final task = TaskModel.fromMap(taskDoc.data()!, taskDoc.id);
      final isAlreadyAssigned = task.assignedVolunteers.contains(volunteerId);
      if (isAlreadyAssigned) {
        throw Exception('Already assigned to this task.');
      }
      if (task.assignedVolunteers.length >= task.maxVolunteers) {
        throw Exception('Task is full.');
      }
      if (task.status == 'completed') {
        throw Exception('Task is already completed.');
      }

      final updates = <String, dynamic>{
        'assignedVolunteers': FieldValue.arrayUnion([volunteerId]),
        'pendingInvites': FieldValue.arrayRemove([volunteerId]),
        'declinedBy': FieldValue.arrayRemove([volunteerId]),
      };

      final assignedCountAfter = task.assignedVolunteers.length + 1;
      if (task.status == 'inviting' && assignedCountAfter >= task.maxVolunteers) {
        updates['status'] = 'active';
      }

      tx.update(taskRef, updates);
      tx.set(assignRef, {
        'taskId': taskId,
        'volunteerId': volunteerId,
        'individualProgress': 0.0,
      }, SetOptions(merge: true));
    });

    await _chatService.addUserToGroupChat(taskId, volunteerId);
  }

  /// Volunteer dismisses a task they're not interested in.
  Future<void> dismissTask(String taskId, String volunteerId) async {
    await _db.collection('tasks').doc(taskId).update({
      'declinedBy': FieldValue.arrayUnion([volunteerId]),
    });
  }

  // ── SUBMIT PROGRESS REQUEST ───────────────────────────────────

  /// Volunteer submits a progress update request for admin approval.
  Future<void> submitProgressRequest({
    required String taskId,
    required String taskTitle,
    required String volunteerId,
    required String adminId,
    required double currentProgress,
    required double requestedProgress,
    required String note,
  }) async {
    final ref = _db.collection('progress_requests').doc();
    await ref.set({
      'taskId': taskId,
      'taskTitle': taskTitle,
      'volunteerId': volunteerId,
      'adminId': adminId,
      'currentProgress': currentProgress,
      'requestedProgress': requestedProgress,
      'mandatoryNote': note,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Notify admins about the progress submission
    final taskDoc = await _db.collection('tasks').doc(taskId).get();
    if (taskDoc.exists) {
      final ngoId = taskDoc.data()!['ngoId'] as String? ?? '';
      final volunteerDoc =
          await _db.collection('users').doc(volunteerId).get();
      final volunteerName =
          volunteerDoc.data()?['name'] as String? ?? 'A volunteer';

      if (ngoId.isNotEmpty) {
        await _notifService.notifyAdminsProgressUpdate(
          ngoId: ngoId,
          taskId: taskId,
          taskTitle: taskTitle,
          volunteerId: volunteerId,
          volunteerName: volunteerName,
        );
      }
    }
  }

  /// Stream progress requests for a specific volunteer on a task.
  Stream<List<ProgressRequestModel>> streamVolunteerProgressRequests(
    String taskId,
    String volunteerId,
  ) {
    return _db
        .collection('progress_requests')
        .where('taskId', isEqualTo: taskId)
        .where('volunteerId', isEqualTo: volunteerId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ProgressRequestModel.fromMap(d.data(), d.id))
            .toList());
  }

  // ── INTERNAL: Recalculate mainProgress ───────────────────────
  Future<void> _recalculateMainProgress(String taskId) async {
    final taskDoc = await _db.collection('tasks').doc(taskId).get();
    if (!taskDoc.exists) return;

    final task = TaskModel.fromMap(taskDoc.data()!, taskDoc.id);
    final assignedCount = task.assignedVolunteers.length;

    if (assignedCount == 0) {
      await _db.collection('tasks').doc(taskId).update({'mainProgress': 0.0});
      return;
    }

    final assignSnap = await _db
        .collection('task_assignments')
        .where('taskId', isEqualTo: taskId)
        .get();

    double sum = 0;
    for (final doc in assignSnap.docs) {
      sum += (doc.data()['individualProgress'] ?? 0.0).toDouble();
    }

    final mainProgress = sum / assignedCount;
    final updates = <String, dynamic>{'mainProgress': mainProgress};

    if (mainProgress >= 100.0 && task.status != 'completed') {
      updates['status'] = 'completed';
    }

    await _db.collection('tasks').doc(taskId).update(updates);
  }

  // ── ACTIVATE TASK (admin choice after invite period) ─────────
  Future<void> activateTask(String taskId) async {
    await _db.collection('tasks').doc(taskId).update({'status': 'active'});
  }

  // ── DELETE TASK ────────────────────────────────────────────────
  Future<void> deleteTask(String taskId) async {
    final batch = _db.batch();

    final assignments = await _db
        .collection('task_assignments')
        .where('taskId', isEqualTo: taskId)
        .get();
    for (final doc in assignments.docs) {
      batch.delete(doc.reference);
    }

    final requests = await _db
        .collection('progress_requests')
        .where('taskId', isEqualTo: taskId)
        .get();
    for (final doc in requests.docs) {
      batch.delete(doc.reference);
    }

    final chats = await _db
        .collection('chats')
        .where('taskId', isEqualTo: taskId)
        .get();
    for (final doc in chats.docs) {
      batch.delete(doc.reference);
    }

    batch.delete(_db.collection('tasks').doc(taskId));
    await batch.commit();
  }
}
