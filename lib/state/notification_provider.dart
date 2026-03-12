import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart'; // reuse userServiceProvider

/// Singleton instance of [NotificationService].
final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

/// Provider that initializes notifications and saves/refreshes the FCM token.
/// Call once after user is authenticated, passing the user's UID.
final fcmTokenProvider =
    FutureProvider.family<void, String>((ref, uid) async {
  final notificationService = ref.read(notificationServiceProvider);
  final userService = ref.read(userServiceProvider);

  // Get current token and save it
  final token = await notificationService.getToken();
  if (token != null) {
    await userService.saveFcmToken(uid, token);
  }

  // Listen for token refresh and update Firestore
  final sub = notificationService.onTokenRefresh.listen((newToken) {
    userService.saveFcmToken(uid, newToken);
  });

  // Cancel subscription when provider is disposed
  ref.onDispose(() => sub.cancel());
});
