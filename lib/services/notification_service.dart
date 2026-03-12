import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// Top-level background message handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message received: ${message.messageId}');
}

/// High-importance Android notification channel for Sevadaar.
const AndroidNotificationChannel sevadaarChannel = AndroidNotificationChannel(
  'sevadaar_high_channel', // id
  'Sevadaar Notifications', // name
  description: 'High importance notifications for Sevadaar app',
  importance: Importance.high,
  playSound: true,
);

/// Manages Firebase Cloud Messaging and local notification display.
class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Callback invoked when user taps a notification while app is in foreground/background.
  void Function(RemoteMessage)? onNotificationTapped;

  /// Initialize messaging: request permissions, create channel, setup listeners.
  Future<void> initialize() async {
    // Request notification permission (Android 13+ / iOS)
    await _requestPermission();

    // Create the high-importance Android notification channel
    await _createAndroidChannel();

    // Initialize flutter_local_notifications
    await _initLocalNotifications();

    // Listen for foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Listen for notification taps when app is in background (not killed)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle notification that launched the app from killed state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }
  }

  /// Request notification permission from the user.
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    debugPrint('Notification permission: ${settings.authorizationStatus}');
  }

  /// Create the Android notification channel.
  Future<void> _createAndroidChannel() async {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(sevadaarChannel);
  }

  /// Initialize flutter_local_notifications plugin.
  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle tap on local notification shown while in foreground
        if (response.payload != null) {
          final data = jsonDecode(response.payload!) as Map<String, dynamic>;
          final message = RemoteMessage(data: data);
          _handleNotificationTap(message);
        }
      },
    );
  }

  /// Display a local notification when a message arrives in foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    showNotification(message);
  }

  /// Show a local notification with sound on Android.
  Future<void> showNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          sevadaarChannel.id,
          sevadaarChannel.name,
          channelDescription: sevadaarChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Called when user taps a notification (background or killed state).
  void _handleNotificationTap(RemoteMessage message) {
    onNotificationTapped?.call(message);
  }

  /// Get the current FCM registration token.
  Future<String?> getToken() async {
    final token = await _messaging.getToken();
    debugPrint('FCM Token: $token');
    return token;
  }

  /// Listen for token refresh events.
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}
