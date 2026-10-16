import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// A release published to the separate, public update hosting site.
///
/// The update manifest is deliberately independent from the web deployment.
/// This lets the web application be released without replacing or removing an
/// Android APK that older devices still need to download.
@immutable
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.mandatory,
    required this.apkUrl,
    required this.sha256,
    required this.title,
    required this.message,
  });

  final String version;
  final int buildNumber;
  final bool mandatory;
  final Uri apkUrl;
  final String sha256;
  final String title;
  final String message;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json, Uri manifestUrl) {
    final version = (json['version'] as String? ?? '').trim();
    final buildNumber = switch (json['buildNumber']) {
      final int value => value,
      final num value => value.toInt(),
      final String value => int.tryParse(value),
      _ => null,
    };
    final apkUrlValue = (json['apkUrl'] as String? ?? '').trim();
    final checksum = (json['sha256'] as String? ?? '').trim().toLowerCase();
    final resolvedApkUrl = manifestUrl.resolve(apkUrlValue);

    if (version.isEmpty ||
        buildNumber == null ||
        buildNumber < 1 ||
        resolvedApkUrl.scheme != 'https' ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      throw const FormatException('ملف التحديث غير صالح.');
    }

    return AppUpdateInfo(
      version: version,
      buildNumber: buildNumber,
      mandatory: json['mandatory'] == true,
      apkUrl: resolvedApkUrl,
      sha256: checksum,
      title: (json['title'] as String? ?? '').trim().isEmpty
          ? 'يتوفر تحديث جديد'
          : (json['title'] as String).trim(),
      message: (json['message'] as String? ?? '').trim().isEmpty
          ? 'يتضمن هذا الإصدار تحسينات وإصلاحات مهمة.'
          : (json['message'] as String).trim(),
    );
  }

  bool isNewerThan({
    required int installedBuildNumber,
    required String installedVersion,
  }) {
    if (buildNumber != installedBuildNumber) {
      return buildNumber > installedBuildNumber;
    }
    return _compareVersions(version, installedVersion) > 0;
  }

  static int _compareVersions(String left, String right) {
    final leftParts = left.split(RegExp(r'[^0-9]+'));
    final rightParts = right.split(RegExp(r'[^0-9]+'));
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index++) {
      final leftPart = index < leftParts.length
          ? int.tryParse(leftParts[index]) ?? 0
          : 0;
      final rightPart = index < rightParts.length
          ? int.tryParse(rightParts[index]) ?? 0
          : 0;
      if (leftPart != rightPart) {
        return leftPart.compareTo(rightPart);
      }
    }
    return 0;
  }
}

@immutable
class AppUpdateDownloadProgress {
  const AppUpdateDownloadProgress({
    required this.receivedBytes,
    this.totalBytes,
  });

  final int receivedBytes;
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0, 1);
  }
}

enum AppUpdateInstallResult { installerOpened, permissionRequired }

/// Checks the published release manifest, downloads a new signed APK and asks
/// Android's package installer to install it. It never silently installs an
/// APK and is intentionally inactive on web and non-Android platforms.
class AppUpdateService {
  AppUpdateService({http.Client? client}) : _client = client ?? http.Client();

  static const _channel = MethodChannel(
    'com.storecollection.store_collection_app/app_updates',
  );

  static const String manifestUrl = String.fromEnvironment(
    'APP_UPDATE_MANIFEST_URL',
    defaultValue: 'https://updates-alasalh.web.app/android.json',
  );

  final http.Client _client;

  Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final installedBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;
      final uri = Uri.parse(manifestUrl);
      final response = await _client
          .get(uri, headers: const {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final update = AppUpdateInfo.fromJson(decoded, uri);
      return update.isNewerThan(
            installedBuildNumber: installedBuildNumber,
            installedVersion: packageInfo.version,
          )
          ? update
          : null;
    } catch (_) {
      // A transient network error must never prevent the user from opening the
      // app. A mandatory update is enforced only after its manifest is read.
      return null;
    }
  }

  Future<AppUpdateInstallResult> downloadAndInstall(
    AppUpdateInfo update, {
    ValueChanged<AppUpdateDownloadProgress>? onProgress,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw StateError('التحديث الداخلي متاح لتطبيق أندرويد فقط.');
    }

    final cacheDirectory = await getTemporaryDirectory();
    final updateDirectory = Directory(
      '${cacheDirectory.path}${Platform.pathSeparator}updates',
    );
    await updateDirectory.create(recursive: true);
    final targetFile = File(
      '${updateDirectory.path}${Platform.pathSeparator}'
      'store-collection-app-v${update.version}+${update.buildNumber}.apk',
    );

    final request = http.Request('GET', update.apkUrl);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('تعذر تنزيل ملف التحديث.');
    }

    final contentLength = response.contentLength;
    var receivedBytes = 0;
    final fileSink = targetFile.openWrite();

    try {
      await for (final chunk in response.stream) {
        fileSink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(
          AppUpdateDownloadProgress(
            receivedBytes: receivedBytes,
            totalBytes: contentLength,
          ),
        );
      }
      await fileSink.close();
    } catch (_) {
      await fileSink.close();
      rethrow;
    }

    final downloadedChecksum = (await sha256.bind(targetFile.openRead()).first)
        .toString()
        .toLowerCase();
    if (downloadedChecksum != update.sha256) {
      await targetFile.delete();
      throw const FormatException('فشل التحقق من سلامة ملف التحديث.');
    }

    final canInstall =
        await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    if (!canInstall) return AppUpdateInstallResult.permissionRequired;

    await _channel.invokeMethod<void>('installApk', {'path': targetFile.path});
    return AppUpdateInstallResult.installerOpened;
  }

  Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod<void>('openInstallSettings');
  }

  void dispose() => _client.close();
}
