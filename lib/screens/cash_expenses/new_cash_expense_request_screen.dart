import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:store_collection_app/services/cash_expense_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class NewCashExpenseRequestScreen extends StatefulWidget {
  final String branchId;
  final String branchName;

  const NewCashExpenseRequestScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<NewCashExpenseRequestScreen> createState() =>
      _NewCashExpenseRequestScreenState();
}

class _NewCashExpenseRequestScreenState
    extends State<NewCashExpenseRequestScreen> {
  final _service = CashExpenseService();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _currencyController = TextEditingController(text: 'YER');
  final _notesController = TextEditingController();

  bool _isSaving = false;
  PlatformFile? _invoiceFile;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    _currencyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = _parseNumber(_amountController.text);
    if (_titleController.text.trim().isEmpty || amount <= 0) {
      _showSnack('أدخل عنوان المصروف والمبلغ بشكل صحيح');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _service.createRequest(
        branchId: widget.branchId,
        branchName: widget.branchName,
        title: _titleController.text,
        description: _descriptionController.text,
        amount: amount,
        currency: _currencyController.text,
        notes: _notesController.text,
        invoiceFileBytes: _invoiceFile?.bytes,
        invoiceFileName: _invoiceFile?.name,
      );
      if (!mounted) return;
      _showSnack('تم إنشاء طلب الصرف النقدي');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        'تعذر حفظ الطلب: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('طلب صرف نقدي'),
          backgroundColor: AppTheme.managerColor,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: AppTheme.cardShadow(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _branchSummary(),
                const SizedBox(height: 18),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان المصروف',
                    prefixIcon: Icon(Icons.receipt_long_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل المصروف',
                    prefixIcon: Icon(Icons.description_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'المبلغ المطلوب',
                          prefixIcon: Icon(Icons.payments_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _currencyController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'العملة',
                          prefixIcon: Icon(Icons.toll_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات مدير الفرع',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                _optionalInvoiceAttachment(),
                const SizedBox(height: 22),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('إرسال الطلب للمدير العام'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.managerColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _branchSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.managerColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.storefront_rounded, color: AppTheme.managerColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'الفرع الطالب: ${widget.branchName}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionalInvoiceAttachment() {
    final file = _invoiceFile;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                file == null
                    ? Icons.upload_file_rounded
                    : Icons.attach_file_rounded,
                color: file == null
                    ? AppTheme.textSecondary
                    : AppTheme.managerColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'فاتورة أو سند المصروف',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      file == null
                          ? 'اختياري - إذا لم يوجد سيظهر السند بدون ملف مرفق'
                          : file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isSaving ? null : _pickInvoiceFile,
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(file == null ? 'إرفاق ملف' : 'تغيير الملف'),
                ),
              ),
              if (file != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'إزالة الملف',
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _invoiceFile = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickInvoiceFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _showSnack('تعذر قراءة الملف المختار');
      return;
    }
    setState(() => _invoiceFile = file);
  }

  double _parseNumber(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
