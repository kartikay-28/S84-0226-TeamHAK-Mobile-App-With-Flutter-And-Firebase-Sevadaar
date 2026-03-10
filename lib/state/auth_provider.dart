import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/ngo_service.dart';
import '../services/user_service.dart';
import '../services/ngo_request_service.dart';

/// Singleton instance of [AuthService].
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Singleton instance of [NgoService].
final ngoServiceProvider = Provider<NgoService>((ref) => NgoService());

/// Singleton instance of [UserService].
final userServiceProvider = Provider<UserService>((ref) => UserService());

/// Singleton instance of [NgoRequestService].
final ngoRequestServiceProvider =
    Provider<NgoRequestService>((ref) => NgoRequestService());

/// Streams the raw Firebase Auth state (User? — logged in or not).
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.read(authServiceProvider).authStateChanges;
});

/// Holds the currently loaded Firestore [UserModel] after login.
/// Set explicitly after login / signup flows complete.
final currentUserProvider = StateProvider<UserModel?>((ref) => null);

/// Streams the current user's Firestore profile in real-time.
final userStreamProvider = StreamProvider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(null);
      return ref.read(userServiceProvider).streamUser(user.uid);
    },
    loading: () => Stream.value(null),
    error: (e, st) => Stream.error(e, st),
  );
});
