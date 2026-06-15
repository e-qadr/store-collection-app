import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:store_collection_app/screens/auth/auth_gate.dart';
import 'package:store_collection_app/services/app_navigation_service.dart';
import 'package:store_collection_app/services/device_notification_service.dart';
import 'package:store_collection_app/services/local_notification_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/device_notification_initializer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await LocalNotificationService.initialize();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تحصيل الكاشير',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppNavigationService.navigatorKey,
      theme: AppTheme.lightTheme,
      home: const DeviceNotificationInitializer(child: AuthGate()),
    );
  }
}
