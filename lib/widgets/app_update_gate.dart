import 'dart:async';

import 'package:flutter/material.dart';
import 'package:store_collection_app/services/app_update_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

/// Shows optional releases as a dialog and mandatory releases as a blocking
/// screen. The child is still shown while a non-blocking check is in progress.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  final _updateService = AppUpdateService();
  AppUpdateInfo? _mandatoryUpdate;
  AppUpdateDownloadState? _downloadState;
  String? _error;
  bool _downloading = false;
  bool _openingInstaller = false;
  bool _optionalDialogShown = false;
  StreamSubscription<AppUpdateDownloadState>? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _updateService.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final update = await _updateService.checkForUpdate();
    if (!mounted || update == null) return;

    if (update.mandatory) {
      final existingState = await _updateService.downloadState();
      if (!mounted) return;
      setState(() {
        _mandatoryUpdate = update;
        _downloadState = existingState.belongsTo(update)
            ? existingState
            : null;
        _downloading = existingState.belongsTo(update) &&
            existingState.status != AppUpdateDownloadStatus.idle &&
            existingState.status != AppUpdateDownloadStatus.readyToInstall;
      });
      if (_downloading) _watchDownload(update);
      return;
    }

    if (_optionalDialogShown) return;
    _optionalDialogShown = true;
    await _showOptionalUpdate(update);
  }

  Future<void> _showOptionalUpdate(AppUpdateInfo update) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: const Icon(
            Icons.system_update_alt_rounded,
            color: AppTheme.managerColor,
            size: 36,
          ),
          title: Text(update.title),
          content: Text('${update.message}\n\nالإصدار ${update.version}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('لاحقًا'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _startUpdate(update, mandatory: false);
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('تحديث الآن'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startUpdate(
    AppUpdateInfo update, {
    required bool mandatory,
  }) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
    });

    try {
      final state = await _updateService.startOrResumeDownload(update);
      if (!mounted) return;
      setState(() => _downloadState = state);
      _watchDownload(update);
      if (!mandatory && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('بدأ التنزيل في الخلفية وسيستمر حتى عند إغلاق التطبيق.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error =
            'تعذر بدء تنزيل التحديث: $error';
      });
      if (!mandatory && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_error!)));
      }
    }
  }

  void _watchDownload(AppUpdateInfo update) {
    _downloadSubscription?.cancel();
    _downloadSubscription = _updateService.watchDownloadState(update).listen(
      (state) {
        if (!mounted || !state.belongsTo(update)) return;
        setState(() {
          _downloadState = state;
          _downloading = state.status != AppUpdateDownloadStatus.readyToInstall &&
              state.status != AppUpdateDownloadStatus.idle;
          _error = state.status == AppUpdateDownloadStatus.retrying
              ? state.error
              : null;
        });
        if (state.status == AppUpdateDownloadStatus.readyToInstall) {
          _openInstaller(update, mandatory: update.mandatory);
        }
      },
      onError: (Object error) {
        if (mounted) setState(() => _error = 'تعذر متابعة حالة التحديث: $error');
      },
    );
  }

  Future<void> _openInstaller(
    AppUpdateInfo update, {
    required bool mandatory,
  }) async {
    if (_openingInstaller) return;
    _openingInstaller = true;
    try {
      final result = await _updateService.installDownloadedUpdate();
      if (!mounted) return;
      if (result == AppUpdateInstallResult.permissionRequired) {
        setState(() {
          _error =
              'اسمح للتطبيق بتثبيت التحديثات من إعدادات أندرويد، ثم اضغط «تثبيت التحديث».';
        });
        await _updateService.openInstallPermissionSettings();
      } else if (!mandatory) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فتح أندرويد شاشة تثبيت التحديث.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'اكتمل التنزيل لكن تعذر فتح التثبيت: $error');
      }
    } finally {
      _openingInstaller = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mandatoryUpdate = _mandatoryUpdate;
    return Stack(
      children: [
        widget.child,
        if (mandatoryUpdate != null)
          Positioned.fill(
            child: _MandatoryUpdateScreen(
              update: mandatoryUpdate,
              downloading: _downloading,
              downloadState: _downloadState,
              error: _error,
              onUpdate: () => _startUpdate(mandatoryUpdate, mandatory: true),
              onInstall: () => _openInstaller(mandatoryUpdate, mandatory: true),
            ),
          ),
      ],
    );
  }
}
class _MandatoryUpdateScreen extends StatelessWidget {
  const _MandatoryUpdateScreen({
    required this.update,
    required this.downloading,
    required this.downloadState,
    required this.error,
    required this.onUpdate,
    required this.onInstall,
  });

  final AppUpdateInfo update;
  final bool downloading;
  final AppUpdateDownloadState? downloadState;
  final String? error;
  final VoidCallback onUpdate;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final state = downloadState;
    final fraction = state?.fraction;
    final progressText = state?.progressLabel ?? 'جارٍ تجهيز تنزيل التحديث…';
    final readyToInstall = state?.status == AppUpdateDownloadStatus.readyToInstall;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: const Color(0xFFFFF8EE),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.system_update_rounded,
                          color: AppTheme.managerColor,
                          size: 66,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          update.title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(update.message, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text('الإصدار المطلوب: ${update.version}'),
                        const SizedBox(height: 24),
                        if (downloading) ...[
                          LinearProgressIndicator(value: fraction),
                          const SizedBox(height: 12),
                          Text(progressText),
                          const SizedBox(height: 8),
                          const Text(
                            'يمكنك إغلاق التطبيق؛ سيستمر التنزيل ويظهر تقدمه في إشعارات الهاتف.',
                            textAlign: TextAlign.center,
                          ),
                        ] else ...[
                          if (error != null) ...[
                            Text(
                              error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.errorColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: readyToInstall ? onInstall : onUpdate,
                              icon: Icon(
                                readyToInstall
                                    ? Icons.install_mobile_rounded
                                    : Icons.download_rounded,
                              ),
                              label: Text(
                                readyToInstall ? 'تثبيت التحديث' : 'تحديث الآن',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
