import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserService {
  FirebaseFirestore? _dbInstance;
  FirebaseFirestore get _db {
    try {
      return _dbInstance ??= FirebaseFirestore.instance;
    } catch (e) {
      throw Exception('Firebase not initialized.');
    }
  }

  Future<UserModel?> getUserById(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data()!, uid);
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async =>
      await _db.collection('users').doc(uid).update(data);

  Future<void> assignNgo(String uid, String ngoId) async =>
      await _db.collection('users').doc(uid).update({
        'ngoId': ngoId,
        'orgId': ngoId,
      });

  Future<void> updateRole(String uid, String role) async =>
      await _db.collection('users').doc(uid).update({'role': role});

  Future<void> updateNgoRequestStatus(String uid, String status) async =>
      await _db.collection('users').doc(uid).update({'ngoRequestStatus': status});

  Future<void> promoteToSuperAdmin(String uid, String ngoId) async =>
      await _db.collection('users').doc(uid).update({
        'role': 'super_admin',
        'ngoId': ngoId,
        'orgId': ngoId,
        'ngoRequestStatus': 'approved',
      });

  Stream<UserModel?> streamUser(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromMap(doc.data()!, uid);
    });
  }

  /// Stream all members belonging to a specific NGO.
  Stream<List<UserModel>> streamNgoMembers(String ngoId) {
    return _db
        .collection('users')
        .where('ngoId', isEqualTo: ngoId)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => UserModel.fromMap(d.data(), d.id)).toList());
  }

  /// Promote a volunteer to Admin for their NGO.
  Future<void> promoteToAdmin(String uid) async =>
      await _db.collection('users').doc(uid).update({'role': 'admin'});

  /// Demote an Admin back to Volunteer.
  Future<void> demoteToVolunteer(String uid) async =>
      await _db.collection('users').doc(uid).update({'role': 'volunteer'});

  /// Save or update the FCM token for push notifications.
  Future<void> saveFcmToken(String uid, String token) async {
    await _db.collection('users').doc(uid).update({'fcmToken': token});
  }
}
