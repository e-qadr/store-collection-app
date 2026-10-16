import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/services/app_update_service.dart';

void main() {
  final manifestUrl = Uri.parse('https://updates-alasalh.web.app/android.json');

  test('accepts a signed HTTPS Android update manifest', () {
    final update = AppUpdateInfo.fromJson(const {
      'version': '1.0.11',
      'buildNumber': 18,
      'mandatory': true,
      'apkUrl': 'store-collection-app-v1.0.11+18.apk',
      'sha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'title': 'تحديث إلزامي',
      'message': 'تحديث مهم',
    }, manifestUrl);

    expect(
      update.apkUrl.toString(),
      'https://updates-alasalh.web.app/store-collection-app-v1.0.11+18.apk',
    );
    expect(update.mandatory, isTrue);
    expect(
      update.isNewerThan(installedBuildNumber: 17, installedVersion: '1.0.10'),
      isTrue,
    );
  });

  test('does not consider an older or matching build a new update', () {
    final update = AppUpdateInfo.fromJson(const {
      'version': '1.0.10',
      'buildNumber': 17,
      'mandatory': false,
      'apkUrl': 'https://updates-alasalh.web.app/app.apk',
      'sha256':
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    }, manifestUrl);

    expect(
      update.isNewerThan(installedBuildNumber: 17, installedVersion: '1.0.10'),
      isFalse,
    );
    expect(
      update.isNewerThan(installedBuildNumber: 18, installedVersion: '1.0.11'),
      isFalse,
    );
  });

  test('rejects an update without HTTPS or a complete checksum', () {
    expect(
      () => AppUpdateInfo.fromJson(const {
        'version': '1.0.11',
        'buildNumber': 18,
        'apkUrl': 'http://example.test/app.apk',
        'sha256': 'short',
      }, manifestUrl),
      throwsFormatException,
    );
  });
}
