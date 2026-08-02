import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/inter_branch_invoice_model.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/services/inter_branch_invoice_api_service.dart';
import 'package:store_collection_app/services/inter_branch_invoice_service.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class NewInterBranchInvoiceScreen extends StatefulWidget {
  /// The authenticated manager's supplying branch. The backend independently
  /// resolves and verifies it; this value is only display/query context.
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
  final _service = InterBranchInvoiceService();
  final _catalogService = ProductCatalogService();
  final _searchController = TextEditingController();
  final _quantityController = TextEditingController();
  final _lineNotesController = TextEditingController();
  final _invoiceNotesController = TextEditingController();
  final List<InterBranchInvoiceItem> _items = [];

  late final Future<_CreationContext> _contextFuture;
  late String _idempotencyKey;
  Timer? _searchDebounce;
  List<ProductCatalogModel> _products = const [];
  List<_ReceivingBranch> _branches = const [];
  DocumentSnapshot<Map<String, dynamic>>? _productCursor;
  DocumentSnapshot<Map<String, dynamic>>? _branchCursor;
  bool _hasMoreProducts = false;
  bool _hasMoreBranches = false;
  bool _loadingProducts = false;
  bool _loadingBranches = false;
  bool _saving = false;
  String _brandId = '';
  String? _receivingBranchId;
  String? _selectedProductId;
  String? _selectedUnitId;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = InterBranchInvoiceApiService.generateIdempotencyKey();
    _contextFuture = _loadContext();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _quantityController.dispose();
    _lineNotesController.dispose();
    _invoiceNotesController.dispose();
    super.dispose();
  }

  Future<_CreationContext> _loadContext() async {
    final firestore = FirebaseFirestore.instance;
    final supplier = await firestore
        .collection('branches')
        .doc(widget.branchId)
        .get();
    final supplierData = supplier.data();
    if (supplierData == null ||
        supplierData['active'] == false ||
        supplierData['is_active'] == false) {
      throw StateError('الفرع المورد غير موجود أو غير نشط.');
    }
    final brandId = supplierData['brand_id']?.toString().trim() ?? '';
    if (brandId.isEmpty) {
      throw StateError('الفرع المورد غير مرتبط بعلامة تجارية.');
    }
    _brandId = brandId;
    await _loadBranches(reset: true);
    await _loadProducts(reset: true);
    return const _CreationContext();
  }

  Future<void> _loadBranches({required bool reset}) async {
    if (_loadingBranches || !mounted) return;
    setState(() => _loadingBranches = true);
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('branches')
          .orderBy('name')
          .limit(30);
      if (!reset && _branchCursor != null) {
        query = query.startAfterDocument(_branchCursor!);
      }
      final page = await query.get();
      final loaded = page.docs
          .where(
            (doc) =>
                doc.id != widget.branchId &&
                doc.data()['active'] != false &&
                doc.data()['is_active'] != false,
          )
          .map(
            (doc) => _ReceivingBranch(
              id: doc.id,
              name: doc.data()['name']?.toString() ?? 'فرع غير مسمى',
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _branches = reset ? loaded : [..._branches, ...loaded];
        _branchCursor = page.docs.isEmpty ? null : page.docs.last;
        _hasMoreBranches = page.docs.length == 30;
      });
    } finally {
      if (mounted) setState(() => _loadingBranches = false);
    }
  }

  Future<void> _loadProducts({required bool reset}) async {
    if (_loadingProducts || _brandId.isEmpty || !mounted) return;
    setState(() => _loadingProducts = true);
    try {
      final page = await _catalogService.fetchActiveProductsPage(
        brandId: _brandId,
        search: _searchController.text,
        after: reset ? null : _productCursor,
        pageSize: 30,
      );
      if (!mounted) return;
      setState(() {
        _products = reset ? page.products : [..._products, ...page.products];
        _productCursor = page.cursor;
        _hasMoreProducts = page.hasMore;
        if (reset &&
            !_products.any((product) => product.id == _selectedProductId)) {
          _selectedProductId = null;
          _selectedUnitId = null;
        }
      });
    } finally {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadProducts(reset: true),
    );
  }

  ProductCatalogModel? get _selectedProduct {
    for (final product in _products) {
      if (product.id == _selectedProductId) return product;
    }
    return null;
  }

  Future<void> _addItem() async {
    if (_items.length >= InterBranchInvoiceApiService.maxItems) {
      _showSnack(
        'الحد الأقصى ${InterBranchInvoiceApiService.maxItems} سطراً للفاتورة.',
      );
      return;
    }
    final product = _selectedProduct;
    final unit = product?.unitById(_selectedUnitId ?? '');
    final quantity = _parseNumber(_quantityController.text);
    if (product == null || unit == null || quantity <= 0) {
      _showSnack('اختر المنتج والوحدة وأدخل كمية صحيحة.');
      return;
    }
    if (_items.any(
      (item) => item.productId == product.id && item.unitId == unit.id,
    )) {
      _showSnack('تمت إضافة هذا المنتج والوحدة مسبقاً.');
      return;
    }
    setState(() {
      _items.add(
        InterBranchInvoiceItem(
          productId: product.id,
          productVersion: product.version,
          groupId: product.groupId,
          legacyCode: product.legacyCode,
          name: product.name,
          unitId: unit.id,
          unit: unit.displayValue,
          rawUnit: unit.rawValue,
          requestedQuantity: quantity,
          hasReceivedQuantity: false,
          lineNotes: _lineNotesController.text.trim(),
        ),
      );
      _quantityController.clear();
      _lineNotesController.clear();
      _selectedProductId = null;
      _selectedUnitId = null;
    });
  }

  Future<void> _save() async {
    if (_receivingBranchId == null || _items.isEmpty) {
      _showSnack('اختر الفرع المستلم وأضف منتجاً واحداً على الأقل.');
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await _service.createDirectInvoice(
        receivingBranchId: _receivingBranchId!,
        items: _items,
        idempotencyKey: _idempotencyKey,
        invoiceNotes: _invoiceNotesController.text,
      );
      if (!mounted) return;
      _showSnack(
        result.invoiceNumber.isEmpty
            ? 'تم إنشاء الفاتورة المباشرة بنجاح.'
            : 'تم إنشاء الفاتورة رقم ${result.invoiceNumber}.',
      );
      Navigator.pop(context, result.invoiceId);
    } on InterBranchInvoiceApiException catch (error) {
      if (mounted) {
        _showSnack(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showSnack('تعذر إنشاء الفاتورة. تحقق من البيانات وحاول مجدداً.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('إنشاء فاتورة تحويل مباشرة'),
          backgroundColor: AppTheme.managerColor,
        ),
        body: FutureBuilder<_CreationContext>(
          future: _contextFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'تعذر تجهيز شاشة الفاتورة. حاول مجدداً.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
              children: [
                _branchCard(),
                const SizedBox(height: 12),
                _catalogCard(),
                const SizedBox(height: 12),
                _itemsCard(),
                const SizedBox(height: 12),
                TextField(
                  controller: _invoiceNotesController,
                  inputFormatters: const [
                    _Utf8LengthLimitingTextInputFormatter(1000),
                  ],
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات الفاتورة (بدون أسعار)',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('إنشاء وإرسال للمراجعة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.managerColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _branchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardShadow(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الفرع المورد: ${widget.branchName}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _receivingBranchId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'الفرع المستلم',
              prefixIcon: Icon(Icons.call_received_rounded),
            ),
            items: _branches
                .map(
                  (branch) => DropdownMenuItem(
                    value: branch.id,
                    child: Text(branch.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _receivingBranchId = value),
          ),
          if (_hasMoreBranches)
            TextButton.icon(
              onPressed: _loadingBranches
                  ? null
                  : () => _loadBranches(reset: false),
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('تحميل فروع أخرى'),
            ),
        ],
      ),
    );
  }

  Widget _catalogCard() {
    final product = _selectedProduct;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardShadow(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'منتجات علامة الفرع المورد',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: const InputDecoration(
              labelText: 'بحث في دليل المنتجات',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey(
              'product-${_selectedProductId ?? 'none'}-${_products.length}',
            ),
            initialValue: _selectedProductId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'المنتج'),
            items: _products
                .map(
                  (item) => DropdownMenuItem(
                    value: item.id,
                    child: Text(item.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() {
              _selectedProductId = value;
              _selectedUnitId = null;
            }),
          ),
          if (_hasMoreProducts)
            TextButton.icon(
              onPressed: _loadingProducts
                  ? null
                  : () => _loadProducts(reset: false),
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('تحميل منتجات أخرى'),
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('unit-${product?.id ?? 'none'}'),
            initialValue: _selectedUnitId,
            decoration: const InputDecoration(labelText: 'الوحدة'),
            items: (product?.units ?? const <CatalogUnit>[])
                .map(
                  (unit) => DropdownMenuItem(
                    value: unit.id,
                    child: Text(unit.displayValue),
                  ),
                )
                .toList(),
            onChanged: product == null
                ? null
                : (value) => setState(() => _selectedUnitId = value),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _quantityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: const InputDecoration(labelText: 'الكمية الموردة'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lineNotesController,
            inputFormatters: const [_Utf8LengthLimitingTextInputFormatter(100)],
            decoration: const InputDecoration(labelText: 'ملاحظة السطر'),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : _addItem,
            icon: const Icon(Icons.add_rounded),
            label: const Text('إضافة المنتج'),
          ),
        ],
      ),
    );
  }

  Widget _itemsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardShadow(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'سطور الفاتورة (${_items.length}/${InterBranchInvoiceApiService.maxItems})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'لم تتم إضافة منتجات بعد',
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._items.asMap().entries.map(
              (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.value.name),
                subtitle: Text(
                  '${_formatNumber(entry.value.suppliedQuantity)} ${entry.value.unit}',
                ),
                trailing: IconButton(
                  tooltip: 'إزالة',
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppTheme.errorColor,
                  onPressed: _saving
                      ? null
                      : () => setState(() => _items.removeAt(entry.key)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double _parseNumber(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  String _formatNumber(double value) => NumberFormat('#,##0.##').format(value);
}

class _CreationContext {
  const _CreationContext();
}

class _ReceivingBranch {
  final String id;
  final String name;

  const _ReceivingBranch({required this.id, required this.name});
}

class _Utf8LengthLimitingTextInputFormatter extends TextInputFormatter {
  final int maxBytes;

  const _Utf8LengthLimitingTextInputFormatter(this.maxBytes);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (utf8.encode(newValue.text).length <= maxBytes) return newValue;
    final buffer = StringBuffer();
    var byteCount = 0;
    for (final character in newValue.text.characters) {
      final characterBytes = utf8.encode(character).length;
      if (byteCount + characterBytes > maxBytes) break;
      buffer.write(character);
      byteCount += characterBytes;
    }
    final text = buffer.toString();
    final offset = newValue.selection.end.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
