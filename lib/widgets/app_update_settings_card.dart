import 'package:flutter/material.dart';
import 'package:store_collection_app/services/app_update_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

/// Lets the user inspect the installed version and manually check Android
/// releases without waiting for the automatic startup check.
class AppUpdateSettingsCard extends StatefulWidget {
  const AppUpdateSettingsCard({super.key});

  @override
  State<AppUpdateSettingsCard> createState() => _AppUpdateSettingsCardState();
}

class _AppUpdateSettingsCardState extends State<AppUpdateSettingsCard> {
  final _service = AppUpdateService();
  AppUpdateCheckResult? _result;
  bool _checking = true;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    if (_checking && _result != null) return;
    setState(() => _checking = true);
    final result = await _service.checkUpdateStatus();
    if (mounted) {
      setState(() {
        _checking = false;
        _result = result;
      });
    }
  }

  Future<void> _install(AppUpdateInfo update) async {
    if (_installing) return;
    setState(() => _installing = true);
    try {
      final state = await _service.startOrResumeDownload(update);
      if (!mounted) return;
      if (state.status == AppUpdateDownloadStatus.readyToInstall) {
        final result = await _service.installDownloadedUpdate();
        if (!mounted) return;
        if (result == AppUpdateInstallResult.permissionRequired) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('اسمح للتطبيق بتثبيت التحديثات ثم حاول مرة أخرى.'),
            ),
          );
          await _service.openInstallPermissionSettings();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم فتح شاشة تثبيت التحديث.')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('بدأ التنزيل في الخلفية. سيظهر تقدمه في إشعارات الهاتف.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر بدء تنزيل التحديث: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final update = result?.update;
    final status = switch (result?.state) {
      AppUpdateCheckState.upToDate => 'أنت تستخدم أحدث إصدار متاح.',
      AppUpdateCheckState.updateAvailable =>
        'يتوفر الإصدار ${update!.version} (${update.buildNumber}).',
      AppUpdateCheckState.unsupported => result!.message!,
      AppUpdateCheckState.failed => result?.message ?? 'تعذر التحقق حالياً.',
      null => 'جارٍ التحقق من حالة التحديث…',
    };
    final statusColor = switch (result?.state) {
      AppUpdateCheckState.upToDate => AppTheme.successColor,
      AppUpdateCheckState.updateAvailable => AppTheme.warningColor,
      AppUpdateCheckState.failed => AppTheme.errorColor,
      _ => AppTheme.textSecondary,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.system_update_alt_rounded),
                SizedBox(width: 10),
                Text(
                  'إدارة تحديث البرنامج',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              result == null
                  ? 'الإصدار الحالي: جارٍ التحميل…'
                  : 'الإصدار الحالي: ${result.installedVersion.version} '
                        '(البناء ${result.installedVersion.buildNumber})',
            ),
            const SizedBox(height: 6),
            Text(status, style: TextStyle(color: statusColor)),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _checking ? null : _checkForUpdates,
                  icon: _checking
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  label: Text(_checking ? 'جارٍ البحث…' : 'البحث عن تحديثات'),
                ),
                if (update != null)
                  FilledButton.icon(
                    onPressed: _installing ? null : () => _install(update),
                    icon: _installing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                    label: Text(_installing ? 'جارٍ التنزيل…' : 'تحديث الآن'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
