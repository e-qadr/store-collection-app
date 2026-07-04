import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/consumable_request_model.dart';
import 'package:store_collection_app/services/consumable_request_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class NewConsumableRequestScreen extends StatefulWidget {
  final String branchId;
  final String branchName;

  const NewConsumableRequestScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<NewConsumableRequestScreen> createState() =>
      _NewConsumableRequestScreenState();
}

class _NewConsumableRequestScreenState
    extends State<NewConsumableRequestScreen> {
  final _service = ConsumableRequestService();
  final _itemController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final _notesController = TextEditingController();
  final List<ConsumableRequestItem> _items = [];

  bool _isSaving = false;

  @override
  void dispose() {
    _itemController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_items.isEmpty && _hasDraftItem()) {
      _addItem();
    }
    if (_items.isEmpty) {
      _showSnack('أضف منتجاً واحداً على الأقل');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _service.createRequest(
        branchId: widget.branchId,
        branchName: widget.branchName,
        items: _items,
        notes: _notesController.text,
      );
      if (!mounted) return;
      _showSnack('تم إنشاء طلب المستهلكات بنجاح');
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
          title: const Text('طلب استهلاك منتج للعرض'),
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
                  controller: _itemController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المنتج',
                    prefixIcon: Icon(Icons.inventory_2_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'الكمية المطلوبة',
                          prefixIcon: Icon(Icons.numbers_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _unitController,
                        decoration: const InputDecoration(
                          labelText: 'الوحدة',
                          prefixIcon: Icon(Icons.straighten_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _addItem,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('إضافة المنتج'),
                ),
                const SizedBox(height: 16),
                _itemsTable(),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات مدير الفرع',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
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

  Widget _itemsTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.managerColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.table_rows_rounded, color: AppTheme.managerColor),
                SizedBox(width: 8),
                Text(
                  'مسودة الطلب',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'لم تتم إضافة منتجات بعد',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 22,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('المنتج')),
                  DataColumn(label: Text('الكمية')),
                  DataColumn(label: Text('الوحدة')),
                  DataColumn(label: Text('إجراء')),
                ],
                rows: _items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;
                  return DataRow(
                    cells: [
                      DataCell(Text('${index + 1}')),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(_formatNumber(item.requestedQuantity))),
                      DataCell(Text(item.unit)),
                      DataCell(
                        IconButton(
                          tooltip: 'حذف',
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: AppTheme.errorColor,
                          onPressed: _isSaving
                              ? null
                              : () => setState(() => _items.removeAt(index)),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasDraftItem() =>
      _itemController.text.trim().isNotEmpty ||
      _quantityController.text.trim().isNotEmpty ||
      _unitController.text.trim().isNotEmpty;

  void _addItem() {
    final name = _itemController.text.trim();
    final unit = _unitController.text.trim();
    final quantity = _parseNumber(_quantityController.text);
    if (name.isEmpty || unit.isEmpty || quantity <= 0) {
      _showSnack('أدخل اسم المنتج والكمية والوحدة');
      return;
    }

    setState(() {
      _items.add(
        ConsumableRequestItem(
          name: name,
          unit: unit,
          requestedQuantity: quantity,
        ),
      );
      _itemController.clear();
      _quantityController.clear();
      _unitController.clear();
    });
  }

  String _formatNumber(double value) => NumberFormat('#,##0.##').format(value);

  double _parseNumber(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
