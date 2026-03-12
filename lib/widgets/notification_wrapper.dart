import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/notification_provider.dart';

/// Wraps any dashboard screen to activate notification listeners.
/// Watches [fcmTokenProvider] to save/refresh the FCM token, and
/// [notificationListenerProvider] to show local notifications for
/// Firestore notification documents.
class NotificationWrapper extends ConsumerStatefulWidget {
  final String uid;
  final Widget child;

  const NotificationWrapper({
    super.key,
    required this.uid,
    required this.child,
  });

  @override
  ConsumerState<NotificationWrapper> createState() =>
      _NotificationWrapperState();
}

class _NotificationWrapperState extends ConsumerState<NotificationWrapper> {
  @override
  Widget build(BuildContext context) {
    // Activate FCM token saving + refresh listener
    ref.watch(fcmTokenProvider(widget.uid));

    // Activate Firestore notification listener → shows local notifications
    ref.watch(notificationListenerProvider(widget.uid));

    return widget.child;
  }
}
