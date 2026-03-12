import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import '../services/firestore_notification_service.dart';
import '../models/notification_model.dart';
import 'auth_provider.dart'; // reuse userServiceProvider

/// Singleton instance of [NotificationService] (local notifications + FCM).
final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

/// Singleton instance of [FirestoreNotificationService].
final firestoreNotificationServiceProvider =
    Provider<FirestoreNotificationService>(
        (ref) => FirestoreNotificationService());

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
  final tokenSub = notificationService.onTokenRefresh.listen((newToken) {
    userService.saveFcmToken(uid, newToken);
  });

  ref.onDispose(() => tokenSub.cancel());
});

/// Listens for new unread notifications in Firestore and shows them as
/// local notifications. Also marks them as read after displaying.
final notificationListenerProvider =
    StreamProvider.family<List<NotificationModel>, String>((ref, uid) {
  final firestoreNotifService =
      ref.read(firestoreNotificationServiceProvider);
  final notificationService = ref.read(notificationServiceProvider);

  final controller = StreamController<List<NotificationModel>>();
  final Set<String> shownIds = {};

  final sub =
      firestoreNotifService.streamUnreadNotifications(uid).listen(
    (notifications) {
      for (final notif in notifications) {
        // Only show each notification once per session
        if (!shownIds.contains(notif.id)) {
          shownIds.add(notif.id);
          notificationService.showNotificationFromData(
            title: notif.title,
            body: notif.body,
            data: {
              'type': notif.type,
              'taskId': notif.taskId,
              if (notif.userId != null) 'userId': notif.userId!,
            },
          );
          // Mark as read so it doesn't trigger again
          firestoreNotifService.markAsRead(notif.id);
        }
      }
      controller.add(notifications);
    },
    onError: (e) {
      // Log but don't crash — index may not be deployed yet
      debugPrint('Notification listener error: $e');
    },
  );

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});
