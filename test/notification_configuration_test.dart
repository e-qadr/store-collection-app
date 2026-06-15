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

    expect(manifest, contains(channelId));
    expect(activity, contains(channelId));
    expect(pushServer, contains(channelId));
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    expect(manifest, contains('android.permission.INTERNET'));
  });
}
