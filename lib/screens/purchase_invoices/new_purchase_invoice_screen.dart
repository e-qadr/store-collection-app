import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_catalog_picker.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_item_editor_dialog.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';
import 'package:store_collection_app/services/purchase_invoice_api_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class NewPurchaseInvoiceScreen extends StatefulWidget {
  const NewPurchaseInvoiceScreen({super.key});

  @override
  State<NewPurchaseInvoiceScreen> createState() =>
      _NewPurchaseInvoiceScreenState();
}

class _NewPurchaseInvoiceScreenState extends State<NewPurchaseInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supplierName = TextEditingController();
  final _supplierNumber = TextEditingController();
  final _notes = TextEditingController();
  final _api = PurchaseInvoiceApiService();
  final _catalog = ProductCatalogService();
  final List<_PurchaseDraftItem> _items = [];
  String? _branchId;
  String _brandId = '';
  String _currency = 'YER';
  DateTime? _supplierDate;
  bool _submitting = false;
  String? _idempotencyKey;

  @override
  void dispose() {
    _supplierName.dispose();
    _supplierNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('فاتورة مشتريات جديدة')),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _branchSelector(),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('purchase-currency'),
                initialValue: _currency,
                decoration: const InputDecoration(
                  labelText: 'العملة',
                  prefixIcon: Icon(Icons.currency_exchange_rounded),
                ),
                items: const ['YER', 'SAR', 'USD']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (value) => setState(() => _currency = value ?? 'YER'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _supplierName,
                decoration: const InputDecoration(
                  labelText: 'اسم المورد (اختياري)',
                  prefixIcon: Icon(Icons.store_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _supplierNumber,
                decoration: const InputDecoration(
                  labelText: 'رقم فاتورة المورد / الورقية (اختياري)',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _submitting ? null : _pickDate,
                icon: const Icon(Icons.event_rounded),
                label: Text(
                  _supplierDate == null
                      ? 'تاريخ فاتورة المورد (اختياري)'
                      : _dateValue(_supplierDate!),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات المدير العام',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'المواد (${_items.length}/50)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    key: const Key('add-purchase-item'),
                    enabled:
                        !_submitting &&
                        _brandId.isNotEmpty &&
                        _items.length < 50,
                    onSelected: (value) {
                      if (value == 'catalog') _addCatalogItem();
                      if (value == 'unmatched') _addUnmatchedItem();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'catalog',
                        child: Text('اختيار مادة من الكتالوج'),
                      ),
                      PopupMenuItem(
                        value: 'unmatched',
                        child: Text('إدخال مادة جديدة غير مطابقة'),
                      ),
                    ],
                    child: const Chip(
                      avatar: Icon(Icons.add_rounded),
                      label: Text('إضافة مادة'),
                    ),
                  ),
                ],
              ),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'اختر الفرع المستلم ثم أضف مادة واحدة على الأقل.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              else
                ..._items.asMap().entries.map((entry) {
                  final item = entry.value;
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        item.isUnmatched
                            ? Icons.help_outline_rounded
                            : Icons.inventory_2_rounded,
                        color: item.isUnmatched
                            ? AppTheme.warningColor
                            : AppTheme.successColor,
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        '${item.quantity} ${item.unit}\n'
                        '${item.isUnmatched ? 'بانتظار مراجعة المحاسب' : 'مادة من كتالوج العلامة'}'
                        '${item.provisionalPrice == null ? '' : '\nسعر مورد أولي محفوظ بسرية'}',
                      ),
                      isThreeLine: item.provisionalPrice != null,
                      trailing: IconButton(
                        onPressed: _submitting
                            ? null
                            : () => setState(() => _items.removeAt(entry.key)),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 22),
              FilledButton.icon(
                key: const Key('submit-purchase-invoice'),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: const Text('إنشاء وإرسال للفرع المستلم'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _branchSelector() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        final branches = (snapshot.data?.docs ?? const []).where((doc) {
          final data = doc.data();
          return data['active'] != false && data['isActive'] != false;
        }).toList();
        return DropdownButtonFormField<String>(
          key: const Key('purchase-receiving-branch'),
          initialValue: _branchId,
          decoration: const InputDecoration(
            labelText: 'الفرع المستلم',
            prefixIcon: Icon(Icons.storefront_rounded),
          ),
          items: branches
              .map(
                (doc) => DropdownMenuItem(
                  value: doc.id,
                  child: Text(doc.data()['name']?.toString() ?? doc.id),
                ),
              )
              .toList(),
          validator: (value) => value == null ? 'اختر الفرع المستلم.' : null,
          onChanged: _submitting
              ? null
              : (value) {
                  final branch = branches
                      .where((doc) => doc.id == value)
                      .firstOrNull;
                  setState(() {
                    _branchId = value;
                    _brandId = branch?.data()['brand_id']?.toString() ?? '';
                    _items.clear();
                  });
                },
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _supplierDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selected != null && mounted) setState(() => _supplierDate = selected);
  }

  Future<void> _addCatalogItem() async {
    final selection = await showPurchaseCatalogPicker(
      context,
      brandId: _brandId,
      service: _catalog,
    );
    if (!mounted || selection == null) return;
    final product = selection.product;
    final unit = selection.unit;
    final draft = await showDialog<PurchaseItemEditorResult>(
      context: context,
      builder: (_) => PurchaseItemEditorDialog.catalog(
        productName: product.name,
        unitValue: unit.displayValue,
      ),
    );
    if (!mounted || draft == null) return;
    setState(
      () => _items.add(
        _PurchaseDraftItem.catalog(
          product: product,
          unit: unit,
          quantity: draft.quantity,
          provisionalPrice: draft.provisionalPrice,
        ),
      ),
    );
  }

  Future<void> _addUnmatchedItem() async {
    final draft = await showDialog<PurchaseItemEditorResult>(
      context: context,
      builder: (_) => const PurchaseItemEditorDialog.unmatched(),
    );
    if (!mounted || draft == null) return;
    setState(
      () => _items.add(
        _PurchaseDraftItem.unmatched(
          name: draft.materialName,
          group: draft.groupText,
          unit: draft.unitText,
          quantity: draft.quantity,
          provisionalPrice: draft.provisionalPrice,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _items.isEmpty) {
      _message('اختر الفرع وأضف مادة واحدة على الأقل.');
      return;
    }
    setState(() => _submitting = true);
    _idempotencyKey ??= PurchaseInvoiceApiService.generateIdempotencyKey();
    try {
      final result = await _api.createInvoice(
        receivingBranchId: _branchId!,
        currency: _currency,
        supplierName: _supplierName.text,
        supplierInvoiceNumber: _supplierNumber.text,
        supplierInvoiceDate: _supplierDate == null
            ? null
            : _dateValue(_supplierDate!),
        generalManagerNotes: _notes.text,
        idempotencyKey: _idempotencyKey!,
        items: _items.map((item) => item.toInput()).toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, result.invoiceId);
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _dateValue(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class _PurchaseDraftItem {
  final ProductCatalogModel? product;
  final CatalogUnit? catalogUnit;
  final String name;
  final String group;
  final String unit;
  final double quantity;
  final double? provisionalPrice;

  _PurchaseDraftItem.catalog({
    required ProductCatalogModel product,
    required CatalogUnit unit,
    required this.quantity,
    this.provisionalPrice,
  }) : product = product,
       catalogUnit = unit,
       name = product.name,
       group = '',
       unit = unit.displayValue;

  const _PurchaseDraftItem.unmatched({
    required this.name,
    required this.group,
    required this.unit,
    required this.quantity,
    this.provisionalPrice,
  }) : product = null,
       catalogUnit = null;

  bool get isUnmatched => product == null;

  PurchaseInvoiceCreateItem toInput() => isUnmatched
      ? PurchaseInvoiceCreateItem.unmatched(
          materialName: name,
          groupText: group,
          unitText: unit,
          orderedQuantity: quantity,
          provisionalUnitPrice: provisionalPrice,
        )
      : PurchaseInvoiceCreateItem.catalog(
          productId: product!.id,
          unitId: catalogUnit!.id,
          orderedQuantity: quantity,
          provisionalUnitPrice: provisionalPrice,
        );
}
