import 'dart:async';

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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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
      home: const _AppBootstrap(),
    );
  }
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initializeServices();
  }

  Future<void> _initializeServices() async {
    await Firebase.initializeApp().timeout(const Duration(seconds: 20));
    if (!kIsWeb) {
      unawaited(LocalNotificationService.initialize());
    }
  }

  void _retry() {
    setState(() => _initialization = _initializeServices());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return const DeviceNotificationInitializer(child: AuthGate());
        }

        if (snapshot.hasError) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 64,
                        color: AppTheme.errorColor,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'تعذر تشغيل التطبيق',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'تحقق من اتصال الإنترنت ثم حاول مرة أخرى.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      ElevatedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.point_of_sale_rounded,
                    size: 72,
                    color: AppTheme.managerColor,
                  ),
                  SizedBox(height: 20),
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('جاري تشغيل تحصيل الكاشير...'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
