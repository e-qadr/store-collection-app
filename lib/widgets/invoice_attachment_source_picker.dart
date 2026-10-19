import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:store_collection_app/theme/app_theme.dart';

/// اختيار موحّد لمرفق فاتورة المصروف.
///
/// الصور الملتقطة أو المختارة تُخفف قبل الرفع لتبقى مناسبة لحد الخادم
/// (10 ميغابايت) ولتسريع الإرسال عبر بيانات الهاتف. أما ملفات PDF فتُختار
/// كما هي من مدير الملفات.
class InvoiceAttachmentSourcePicker {
  static const _allowedExtensions = {'pdf', 'jpg', 'jpeg', 'png'};
  static const _maxFileSize = 10 * 1024 * 1024;

  static Future<PlatformFile?> pick(BuildContext context) async {
    final source = await showModalBottomSheet<_AttachmentSource>(
      context: context,
      backgroundColor: AppTheme.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إرفاق فاتورة المصروف',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'التقط صورة الآن، أو اختر صورة محفوظة أو ملف PDF.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              _sourceTile(
                context: sheetContext,
                source: _AttachmentSource.camera,
                icon: Icons.photo_camera_rounded,
                title: 'التقاط صورة',
                subtitle: 'استخدم كاميرا الجهاز مباشرة',
              ),
              _sourceTile(
                context: sheetContext,
                source: _AttachmentSource.gallery,
                icon: Icons.photo_library_rounded,
                title: 'اختيار من المعرض',
                subtitle: 'صورة محفوظة على الجهاز',
              ),
              _sourceTile(
                context: sheetContext,
                source: _AttachmentSource.file,
                icon: Icons.attach_file_rounded,
                title: 'اختيار ملف',
                subtitle: 'PDF أو صورة من مدير الملفات',
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return null;

    final file = switch (source) {
      _AttachmentSource.camera => await _pickImage(ImageSource.camera),
      _AttachmentSource.gallery => await _pickImage(ImageSource.gallery),
      _AttachmentSource.file => await _pickFile(),
    };
    if (file == null) return null;
    _validate(file);
    return file;
  }

  static Widget _sourceTile({
    required BuildContext context,
    required _AttachmentSource source,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OutlinedButton(
        onPressed: () => Navigator.pop(context, source),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          alignment: AlignmentDirectional.centerStart,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.managerColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_left_rounded),
          ],
        ),
      ),
    );
  }

  static Future<PlatformFile?> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions.toList()..sort(),
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single;
  }

  static Future<PlatformFile?> _pickImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) throw Exception('تعذر قراءة الصورة المختارة.');
    final name = image.name.trim();
    return PlatformFile(
      name: name.isEmpty ? 'expense_invoice.jpg' : name,
      size: bytes.length,
      bytes: Uint8List.fromList(bytes),
    );
  }

  static void _validate(PlatformFile file) {
    if (file.bytes == null || file.bytes!.isEmpty) {
      throw Exception('تعذر قراءة الملف المختار.');
    }
    final dotIndex = file.name.lastIndexOf('.');
    final extension =
        (file.extension ??
                (dotIndex < 0 ? '' : file.name.substring(dotIndex + 1)))
            .toLowerCase();
    if (!_allowedExtensions.contains(extension)) {
      throw Exception('الصيغ المدعومة هي PDF وJPG وPNG فقط.');
    }
    if (file.bytes!.length > _maxFileSize) {
      throw Exception('حجم المرفق أكبر من 10 ميغابايت.');
    }
  }
}

enum _AttachmentSource { camera, gallery, file }
