import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

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

enum AppUpdateDownloadStatus {
  idle,
  downloading,
  retrying,
  verifying,
  readyToInstall,
}

/// Persistent native download state. It is also available after Flutter has
/// been closed because Android stores the partial APK and this state itself.
@immutable
class AppUpdateDownloadState {
  const AppUpdateDownloadState({
    required this.status,
    required this.receivedBytes,
    required this.totalBytes,
    this.error,
    this.version,
    this.buildNumber,
  });

  final AppUpdateDownloadStatus status;
  final int receivedBytes;
  final int totalBytes;
  final String? error;
  final String? version;
  final int? buildNumber;

  factory AppUpdateDownloadState.fromMap(Map<Object?, Object?> values) {
    final statusValue = values['status'] as String? ?? 'idle';
    final status = switch (statusValue) {
      'downloading' => AppUpdateDownloadStatus.downloading,
      'retrying' => AppUpdateDownloadStatus.retrying,
      'verifying' => AppUpdateDownloadStatus.verifying,
      'ready' => AppUpdateDownloadStatus.readyToInstall,
      _ => AppUpdateDownloadStatus.idle,
    };
    final error = (values['error'] as String?)?.trim();
    return AppUpdateDownloadState(
      status: status,
      receivedBytes: (values['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (values['totalBytes'] as num?)?.toInt() ?? 0,
      error: error == null || error.isEmpty ? null : error,
      version: values['version'] as String?,
      buildNumber: (values['buildNumber'] as num?)?.toInt(),
    );
  }

  double? get fraction {
    if (totalBytes <= 0) return null;
    return (receivedBytes / totalBytes).clamp(0, 1);
  }

  bool belongsTo(AppUpdateInfo update) =>
      version == update.version && buildNumber == update.buildNumber;

  String get progressLabel {
    String formatBytes(int bytes) =>
        '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
    return switch (status) {
      AppUpdateDownloadStatus.downloading when totalBytes > 0 =>
        'تم تنزيل ${formatBytes(receivedBytes)} من ${formatBytes(totalBytes)} — '
            'متبقي ${formatBytes((totalBytes - receivedBytes).clamp(0, totalBytes))}',
      AppUpdateDownloadStatus.downloading =>
        'تم تنزيل ${formatBytes(receivedBytes)} من التحديث',
      AppUpdateDownloadStatus.retrying =>
        'انقطع الاتصال؛ سيُستأنف التنزيل تلقائياً من حيث توقف.',
      AppUpdateDownloadStatus.verifying => 'جارٍ التحقق من سلامة ملف التحديث…',
      AppUpdateDownloadStatus.readyToInstall => 'اكتمل التنزيل وهو جاهز للتثبيت.',
      AppUpdateDownloadStatus.idle => 'جاهز لتنزيل التحديث.',
    };
  }
}

/// The locally installed application identity shown in the settings screen.
@immutable
class InstalledAppVersion {
  const InstalledAppVersion({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;

  String get label => '$version ($buildNumber)';
}

enum AppUpdateCheckState { upToDate, updateAvailable, unsupported, failed }

/// Full, user-facing result of a manual update check.
@immutable
class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.state,
    required this.installedVersion,
    this.update,
    this.message,
  });

  final AppUpdateCheckState state;
  final InstalledAppVersion installedVersion;
  final AppUpdateInfo? update;
  final String? message;
}

enum AppUpdateInstallResult { installerOpened, permissionRequired }

/// Checks the published release manifest and delegates Android downloads to a
/// native foreground service. It never silently installs an APK: Android keeps
/// its own final installation confirmation.
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

  Future<InstalledAppVersion> installedVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return InstalledAppVersion(
      version: packageInfo.version,
      buildNumber: int.tryParse(packageInfo.buildNumber) ?? 0,
    );
  }

  /// Checks the manifest while preserving enough information for Settings to
  /// clearly explain whether the installed version is current.
  Future<AppUpdateCheckResult> checkUpdateStatus() async {
    final installed = await installedVersion();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AppUpdateCheckResult(
        state: AppUpdateCheckState.unsupported,
        installedVersion: installed,
        message: 'تحديثات الويب تصل تلقائياً عند إعادة تحميل الصفحة.',
      );
    }

    try {
      final uri = Uri.parse(manifestUrl);
      final response = await _client
          .get(uri, headers: const {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return AppUpdateCheckResult(
          state: AppUpdateCheckState.failed,
          installedVersion: installed,
          message: 'تعذر الوصول إلى معلومات التحديث حالياً.',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('ملف التحديث غير صالح.');
      }
      final update = AppUpdateInfo.fromJson(decoded, uri);
      if (update.isNewerThan(
        installedBuildNumber: installed.buildNumber,
        installedVersion: installed.version,
      )) {
        return AppUpdateCheckResult(
          state: AppUpdateCheckState.updateAvailable,
          installedVersion: installed,
          update: update,
        );
      }
      return AppUpdateCheckResult(
        state: AppUpdateCheckState.upToDate,
        installedVersion: installed,
      );
    } catch (_) {
      return AppUpdateCheckResult(
        state: AppUpdateCheckState.failed,
        installedVersion: installed,
        message:
            'تعذر التحقق من التحديث. تحقق من اتصال الإنترنت ثم أعد المحاولة.',
      );
    }
  }

  Future<AppUpdateInfo?> checkForUpdate() async {
    final result = await checkUpdateStatus();
    return result.state == AppUpdateCheckState.updateAvailable
        ? result.update
        : null;
  }

  Future<AppUpdateDownloadState> startOrResumeDownload(
    AppUpdateInfo update,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw StateError('التحديث الداخلي متاح لتطبيق أندرويد فقط.');
    }
    final values = await _channel.invokeMapMethod<Object?, Object?>(
      'startUpdateDownload',
      {
        'url': update.apkUrl.toString(),
        'sha256': update.sha256,
        'version': update.version,
        'buildNumber': update.buildNumber,
      },
    );
    return AppUpdateDownloadState.fromMap(values ?? const {});
  }

  Future<AppUpdateDownloadState> downloadState() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const AppUpdateDownloadState(
        status: AppUpdateDownloadStatus.idle,
        receivedBytes: 0,
        totalBytes: 0,
      );
    }
    final values = await _channel.invokeMapMethod<Object?, Object?>(
      'getUpdateDownloadState',
    );
    return AppUpdateDownloadState.fromMap(values ?? const {});
  }

  /// Polling is deliberate here: the Android service may survive a complete
  /// Flutter process restart, so persistent state is more reliable than an
  /// activity-bound event channel.
  Stream<AppUpdateDownloadState> watchDownloadState(AppUpdateInfo update) async* {
    while (true) {
      final state = await downloadState();
      yield state;
      if (state.belongsTo(update) &&
          state.status == AppUpdateDownloadStatus.readyToInstall) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 650));
    }
  }

  Future<AppUpdateInstallResult> installDownloadedUpdate() async {
    final canInstall =
        await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    if (!canInstall) return AppUpdateInstallResult.permissionRequired;
    await _channel.invokeMethod<void>('installDownloadedUpdate');
    return AppUpdateInstallResult.installerOpened;
  }

  Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod<void>('openInstallSettings');
  }

  void dispose() => _client.close();
}
