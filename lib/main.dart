import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';
import 'screens/splash/splash_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  
  // Initialize Firebase only on mobile and web platforms
  // (Linux/Windows don't have Firebase plugin support)
  if (defaultTargetPlatform != TargetPlatform.linux &&
      defaultTargetPlatform != TargetPlatform.windows) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Register background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize notification service (permissions, channel, listeners)
    final notificationService = NotificationService();
    await notificationService.initialize();
  }
  
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: SevadaarApp()));
}

class SevadaarApp extends StatelessWidget {
  const SevadaarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sevadaar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          primary: const Color(0xFF2E7D32),
          secondary: const Color(0xFF1565C0),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
