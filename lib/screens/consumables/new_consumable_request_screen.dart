import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/consumable_request_model.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_catalog_picker.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_item_editor_dialog.dart';
import 'package:store_collection_app/services/consumable_request_service.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

typedef ConsumableRequestSubmitter =
    Future<void> Function(List<ConsumableRequestItem> items, String notes);

class NewConsumableRequestScreen extends StatefulWidget {
  final String branchId;
  final String branchName;
  final String? brandId;
  final ProductCatalogService? catalogService;
  final ConsumableRequestSubmitter? submitter;

  const NewConsumableRequestScreen({
    super.key,
    required this.branchId,
    required this.branchName,
    this.brandId,
    this.catalogService,
    this.submitter,
  });

  @override
  State<NewConsumableRequestScreen> createState() =>
      _NewConsumableRequestScreenState();
}

class _NewConsumableRequestScreenState
    extends State<NewConsumableRequestScreen> {
  final _service = ConsumableRequestService();
  late final ProductCatalogService _catalog =
      widget.catalogService ?? ProductCatalogService();
  final _notesController = TextEditingController();
  final List<ConsumableRequestItem> _items = [];
  late final Future<String> _brandIdFuture = _loadBrandId();
  bool _isSaving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<String> _loadBrandId() async {
    final supplied = widget.brandId?.trim() ?? '';
    if (supplied.isNotEmpty) return supplied;
    final branch = await FirebaseFirestore.instance
        .collection('branches')
        .doc(widget.branchId)
        .get();
    final brandId = branch.data()?['brand_id']?.toString().trim() ?? '';
    if (brandId.isEmpty) throw StateError('الفرع غير مرتبط بعلامة تجارية.');
    return brandId;
  }

  Future<ConsumableRequestItem?> _selectAndEditItem(
    String brandId, {
    ConsumableRequestItem? existing,
  }) async {
    final selection = await showCatalogPicker(
      context,
      brandId: brandId,
      service: _catalog,
      mode: CatalogPickerMode.consumption,
      title: existing == null ? 'إضافة مادة' : 'تغيير المادة',
    );
    if (!mounted || selection == null) return null;
    final edited = await showDialog<PurchaseItemEditorResult>(
      context: context,
      builder: (_) => PurchaseItemEditorDialog.catalog(
        productName: selection.product.name,
        unitValue: selection.unit.displayValue,
        catalogUnits: selection.product.units,
        initialCatalogUnitId: selection.unit.id,
        initialQuantity: existing?.requestedQuantity ?? 1,
        showPricing: false,
        confirmLabel: existing == null ? 'إضافة' : 'حفظ التعديل',
      ),
    );
    if (edited == null) return null;
    final unit = selection.product.unitById(edited.catalogUnitId ?? '');
    if (unit == null) return null;
    return _catalogItem(selection.product, unit, edited.quantity);
  }

  ConsumableRequestItem _catalogItem(
    ProductCatalogModel product,
    CatalogUnit unit,
    double quantity,
  ) {
    return ConsumableRequestItem(
      productId: product.id,
      productVersion: product.version,
      productCode: product.legacyCode,
      groupId: product.groupId,
      name: product.name,
      unitId: unit.id,
      unit: unit.displayValue,
      rawUnit: unit.rawValue,
      requestedQuantity: quantity,
    );
  }

  Future<void> _addItem(String brandId) async {
    final item = await _selectAndEditItem(brandId);
    if (item != null && mounted) setState(() => _items.add(item));
  }

  Future<void> _editItem(String brandId, int index) async {
    final item = await _selectAndEditItem(brandId, existing: _items[index]);
    if (item != null && mounted) setState(() => _items[index] = item);
  }

  Future<void> _save() async {
    if (_items.isEmpty ||
        _items.any((item) => item.productId == null || item.unitId == null)) {
      _showSnack('أضف مادة مرتبطة بالكتالوج على الأقل');
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (widget.submitter != null) {
        await widget.submitter!(
          List.unmodifiable(_items),
          _notesController.text,
        );
      } else {
        await _service.createRequest(
          branchId: widget.branchId,
          branchName: widget.branchName,
          items: _items,
          notes: _notesController.text,
        );
      }
      if (!mounted) return;
      _showSnack('تم إنشاء طلب المستهلكات بنجاح');
      Navigator.pop(context);
    } catch (error) {
      if (mounted) _showSnack('تعذر حفظ الطلب: $error');
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
        body: FutureBuilder<String>(
          future: _brandIdFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data?.isEmpty != false) {
              return const Center(child: Text('تعذر تحميل كتالوج مواد الفرع.'));
            }
            final brandId = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _branchSummary(),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('consumption-add-catalog-item'),
                  onPressed: _isSaving ? null : () => _addItem(brandId),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('إضافة مادة'),
                ),
                const SizedBox(height: 14),
                if (_items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'لم تتم إضافة مواد بعد',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ..._items.asMap().entries.map(
                    (entry) => _itemCard(brandId, entry.key, entry.value),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات مدير الفرع',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('إرسال الطلب للمدير العام'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _itemCard(String brandId, int index, ConsumableRequestItem item) {
    return Card(
      key: Key('consumption-item-$index'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('${_formatNumber(item.requestedQuantity)} ${item.unit}'),
                  if (item.productCode?.isNotEmpty == true)
                    Text(
                      item.productCode!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              key: Key('consumption-edit-$index'),
              tooltip: 'تعديل المادة والوحدة والكمية',
              onPressed: _isSaving ? null : () => _editItem(brandId, index),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              key: Key('consumption-remove-$index'),
              tooltip: 'إزالة',
              color: AppTheme.errorColor,
              onPressed: _isSaving
                  ? null
                  : () => setState(() => _items.removeAt(index)),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _branchSummary() => Card(
    child: ListTile(
      leading: const Icon(Icons.storefront_rounded),
      title: const Text('الفرع الطالب'),
      subtitle: Text(widget.branchName),
    ),
  );

  String _formatNumber(double value) => NumberFormat('#,##0.##').format(value);

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
