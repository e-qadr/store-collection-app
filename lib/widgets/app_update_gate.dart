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
  AppUpdateDownloadProgress? _progress;
  String? _error;
  bool _downloading = false;
  bool _optionalDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    _updateService.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    final update = await _updateService.checkForUpdate();
    if (!mounted || update == null) return;

    if (update.mandatory) {
      setState(() => _mandatoryUpdate = update);
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
      _progress = null;
      _error = null;
    });

    try {
      final result = await _updateService.downloadAndInstall(
        update,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (!mounted) return;
      if (result == AppUpdateInstallResult.permissionRequired) {
        setState(() {
          _downloading = false;
          _error =
              'اسمح للتطبيق بتثبيت التحديثات من إعدادات أندرويد، ثم اضغط «تحديث الآن» مرة أخرى.';
        });
        await _updateService.openInstallPermissionSettings();
        return;
      }
      setState(() => _downloading = false);
      if (!mandatory && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فتح أندرويد شاشة تثبيت التحديث.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error =
            'تعذر تنزيل التحديث أو التحقق منه. تحقق من الإنترنت ثم أعد المحاولة.';
      });
      if (!mandatory && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_error!)));
      }
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
              progress: _progress,
              error: _error,
              onUpdate: () => _startUpdate(mandatoryUpdate, mandatory: true),
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
    required this.progress,
    required this.error,
    required this.onUpdate,
  });

  final AppUpdateInfo update;
  final bool downloading;
  final AppUpdateDownloadProgress? progress;
  final String? error;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final fraction = progress?.fraction;
    final progressText = fraction == null
        ? 'جارٍ تنزيل التحديث…'
        : 'جارٍ تنزيل التحديث ${(fraction * 100).toStringAsFixed(0)}٪';

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
                              onPressed: onUpdate,
                              icon: const Icon(Icons.download_rounded),
                              label: const Text('تحديث الآن'),
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
