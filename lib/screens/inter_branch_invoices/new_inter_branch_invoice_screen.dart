import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/services/inter_branch_invoice_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class NewInterBranchInvoiceScreen extends StatefulWidget {
  final String branchId;
  final String branchName;

  const NewInterBranchInvoiceScreen({
    super.key,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<NewInterBranchInvoiceScreen> createState() =>
      _NewInterBranchInvoiceScreenState();
}

class _NewInterBranchInvoiceScreenState
    extends State<NewInterBranchInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = InterBranchInvoiceService();
  final _itemController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final List<InterBranchInvoiceItem> _items = [];
  late final Future<QuerySnapshot<Map<String, dynamic>>> _branchesFuture;

  String? _sendingBranchId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _branchesFuture = FirebaseFirestore.instance.collection('branches').get();
  }

  @override
  void dispose() {
    _itemController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_items.isEmpty && _hasDraftItem()) {
      _addItem();
    }
    if (_items.isEmpty || _sendingBranchId == null) {
      if (_sendingBranchId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اختر الفرع المرسل أولاً')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أضف منتجاً واحداً على الأقل')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      final branches = (await _branchesFuture).docs;
      final sendingBranch = branches.firstWhere(
        (branch) => branch.id == _sendingBranchId,
      );
      final data = sendingBranch.data();

      await _service.createRequest(
        itemName: _items.first.name,
        requestedQuantity: _items.first.requestedQuantity,
        unit: _items.first.unit,
        items: _items,
        receivingBranchId: widget.branchId,
        receivingBranchName: widget.branchName,
        sendingBranchId: sendingBranch.id,
        sendingBranchName: data['name']?.toString() ?? 'فرع غير مسمى',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء طلب الفاتورة بنجاح')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر حفظ الطلب: $e')));
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
          title: const Text('طلب فاتورة بين الفروع'),
          backgroundColor: AppTheme.managerColor,
        ),
        body: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
          future: _branchesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل الفروع'));
            }

            final branches =
                (snapshot.data?.docs ?? [])
                    .where((branch) => branch.id != widget.branchId)
                    .toList()
                  ..sort((a, b) {
                    final aName = a.data()['name']?.toString() ?? '';
                    final bName = b.data()['name']?.toString() ?? '';
                    return aName.compareTo(bName);
                  });

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              child: Form(
                key: _formKey,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: AppTheme.cardShadow(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBranchSummary(),
                      const SizedBox(height: 18),
                      DropdownButtonFormField<String>(
                        initialValue: _sendingBranchId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'الفرع المرسل',
                          prefixIcon: Icon(Icons.storefront_rounded),
                        ),
                        items: branches
                            .map(
                              (branch) => DropdownMenuItem(
                                value: branch.id,
                                child: Text(
                                  branch.data()['name']?.toString() ??
                                      'فرع غير مسمى',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        validator: (value) =>
                            value == null ? 'اختر الفرع المرسل' : null,
                        onChanged: branches.isEmpty
                            ? null
                            : (value) => setState(() {
                                _sendingBranchId = value;
                              }),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _itemController,
                        decoration: const InputDecoration(
                          labelText: 'اسم الصنف',
                          prefixIcon: Icon(Icons.inventory_2_rounded),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'العدد / الكمية',
                                prefixIcon: Icon(Icons.numbers_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
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
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: const Text('إضافة المنتج للفاتورة'),
                        onPressed: _isSaving ? null : _addItem,
                      ),
                      const SizedBox(height: 16),
                      _buildDraftInvoiceTable(),
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
                            : const Icon(Icons.save_rounded),
                        label: const Text('حفظ الطلب'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.managerColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBranchSummary() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.managerColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.call_received_rounded, color: AppTheme.managerColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'الفرع المستلم: ${widget.branchName}',
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

  Widget _buildDraftInvoiceTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE0E0E0)),
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
                Icon(Icons.receipt_long_rounded, color: AppTheme.managerColor),
                SizedBox(width: 8),
                Text(
                  'مسودة الفاتورة',
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
                headingRowColor: WidgetStatePropertyAll(
                  AppTheme.managerColor.withValues(alpha: 0.08),
                ),
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('الصنف')),
                  DataColumn(label: Text('العدد')),
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
                          tooltip: 'حذف المنتج',
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: AppTheme.errorColor,
                          onPressed: _isSaving
                              ? null
                              : () => setState(() {
                                  _items.removeAt(index);
                                }),
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

  bool _hasDraftItem() {
    return _itemController.text.trim().isNotEmpty ||
        _quantityController.text.trim().isNotEmpty ||
        _unitController.text.trim().isNotEmpty;
  }

  void _addItem() {
    final name = _itemController.text.trim();
    final unit = _unitController.text.trim();
    final quantity = _parseNumber(_quantityController.text);
    if (name.isEmpty || unit.isEmpty || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم المنتج والكمية والوحدة')),
      );
      return;
    }
    setState(() {
      _items.add(
        InterBranchInvoiceItem(
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
}
