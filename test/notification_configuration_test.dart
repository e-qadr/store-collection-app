import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('تستخدم إعدادات Android وخادم الإرسال قناة الإشعارات نفسها', () {
    const channelId = 'high_importance_channel';
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/com/storecollection/store_collection_app/MainActivity.kt',
    ).readAsStringSync();
    final pushServer = File(
      'hostinger-push-server/server.js',
    ).readAsStringSync();
    final localNotifications = File(
      'lib/services/local_notification_service.dart',
    ).readAsStringSync();
    final androidGradle = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();
    final mainFile = File('lib/main.dart').readAsStringSync();

    expect(manifest, contains(channelId));
    expect(activity, contains(channelId));
    expect(pushServer, contains(channelId));
    expect(localNotifications, contains(channelId));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.permission.VIBRATE'));
    expect(androidGradle, contains('isCoreLibraryDesugaringEnabled = true'));
    expect(mainFile, contains('runApp(const MyApp())'));
    expect(
      mainFile.indexOf('runApp(const MyApp())'),
      lessThan(mainFile.indexOf('Firebase.initializeApp()')),
    );
    expect(mainFile, contains('Firebase.initializeApp().timeout'));
  });
}
