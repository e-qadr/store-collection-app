import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/models/product_price_model.dart';
import 'package:store_collection_app/screens/products/catalog_product_editor_dialog.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_catalog_picker.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_item_editor_dialog.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';
import 'package:store_collection_app/services/product_price_service.dart';
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
  final _prices = ProductPriceService();
  final List<_PurchaseDraftItem> _items = [];
  String? _branchId;
  String _brandId = '';
  String _currency = 'YER';
  DateTime? _supplierDate;
  bool _submitting = false;
  String? _idempotencyKey;

  double get _invoiceTotal => _items.fold(
    0,
    (total, item) => total + (item.provisionalPrice ?? 0) * item.quantity,
  );

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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _sectionTitle('بيانات الفاتورة'),
              _branchSelector(),
              const SizedBox(height: 12),
              TextFormField(
                controller: _supplierName,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم المورد',
                  prefixIcon: Icon(Icons.store_rounded),
                ),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'أدخل اسم المورد.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _supplierNumber,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'رقم فاتورة المورد / الورقية (اختياري)',
                  prefixIcon: Icon(Icons.numbers_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickDate,
                      icon: const Icon(Icons.event_rounded),
                      label: Text(
                        _supplierDate == null
                            ? 'تاريخ فاتورة المورد (اختياري)'
                            : _dateValue(_supplierDate!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 118,
                    child: DropdownButtonFormField<String>(
                      key: const Key('purchase-currency'),
                      initialValue: _currency,
                      decoration: const InputDecoration(labelText: 'العملة'),
                      items: const ['YER', 'SAR', 'USD']
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _submitting
                          ? null
                          : (value) => _changeCurrency(value ?? 'YER'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات الفاتورة (اختيارية)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _sectionTitle('المواد (${_items.length}/50)'),
                  ),
                  PopupMenuButton<String>(
                    key: const Key('add-purchase-item'),
                    enabled:
                        !_submitting &&
                        _brandId.isNotEmpty &&
                        _items.length < 50,
                    tooltip: 'إضافة مادة',
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
                        child: Text('إدخال مادة غير مطابقة'),
                      ),
                    ],
                    child: const Chip(
                      avatar: Icon(Icons.add_rounded),
                      label: Text('إضافة مادة'),
                    ),
                  ),
                ],
              ),
              if (_branchId == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'اختر الفرع المستلم أولًا لتظهر مواد علامته التجارية.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              else if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'أضف مادة واحدة على الأقل. الأسعار مرئية للمدير العام والمحاسب فقط.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              else ...[
                ..._items.indexed.map((entry) => _itemCard(entry.$1, entry.$2)),
                const SizedBox(height: 8),
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(Icons.calculate_rounded),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'الإجمالي التقديري للفاتورة',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          '${_money(_invoiceTotal)} $_currency',
                          key: const Key('purchase-invoice-total'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
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

  Widget _sectionTitle(String value) => Text(
    value,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
  );

  Widget _itemCard(int index, _PurchaseDraftItem item) {
    final hasPrice = item.provisionalPrice != null;
    return Card(
      key: Key('purchase-draft-item-$index'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.isUnmatched
                      ? Icons.help_outline_rounded
                      : Icons.inventory_2_rounded,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: _submitting ? null : () => _editItem(index),
                    child: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: _submitting ? null : () => _editItem(index),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: _submitting
                      ? null
                      : () => setState(() => _items.removeAt(index)),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            if (item.isUnmatched)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'مادة غير مطابقة — ستظهر في قائمة مراجعة المواد',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _unitEditor(index, item)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    key: Key('purchase-item-quantity-$index'),
                    initialValue: _number(item.quantity),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'الكمية',
                      isDense: true,
                    ),
                    onChanged: (value) {
                      final quantity = double.tryParse(value.trim());
                      if (quantity != null && quantity > 0) {
                        setState(
                          () =>
                              _items[index] = item.copyWith(quantity: quantity),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: Key('purchase-item-price-$index'),
                    initialValue: hasPrice
                        ? _money(item.provisionalPrice!)
                        : '',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'سعر الوحدة (سري)',
                      isDense: true,
                    ),
                    onChanged: (value) {
                      final text = value.trim();
                      final price = text.isEmpty ? null : double.tryParse(text);
                      if (price != null && price >= 0 || text.isEmpty) {
                        setState(
                          () => _items[index] = item.copyWith(
                            provisionalPrice: price,
                            clearPrice: text.isEmpty,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'الإجمالي',
                      isDense: true,
                    ),
                    child: Text(
                      hasPrice
                          ? '${_money(item.quantity * item.provisionalPrice!)} $_currency'
                          : 'غير محدد',
                    ),
                  ),
                ),
              ],
            ),
            if (item.lineNotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('ملاحظة: ${item.lineNotes}'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _unitEditor(int index, _PurchaseDraftItem item) {
    if (item.isUnmatched) {
      return TextFormField(
        key: Key('purchase-item-unit-$index'),
        initialValue: item.unit,
        decoration: const InputDecoration(labelText: 'الوحدة', isDense: true),
        onChanged: (value) {
          if (value.trim().isNotEmpty) {
            setState(() => _items[index] = item.copyWith(unit: value.trim()));
          }
        },
      );
    }
    return DropdownButtonFormField<String>(
      key: Key('purchase-item-unit-$index'),
      initialValue: item.catalogUnit!.id,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'الوحدة', isDense: true),
      items: item.product!.units
          .map(
            (unit) => DropdownMenuItem(
              value: unit.id,
              child: Text(unit.displayValue),
            ),
          )
          .toList(growable: false),
      onChanged: _submitting
          ? null
          : (unitId) {
              final unit = item.product!.unitById(unitId ?? '');
              if (unit != null) _changeCatalogUnit(index, item, unit);
            },
    );
  }

  Widget _branchSelector() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('branches')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        final branches = (snapshot.data?.docs ?? const [])
            .where((doc) {
              final data = doc.data();
              return data['active'] != false && data['isActive'] != false;
            })
            .toList(growable: false);
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
              .toList(growable: false),
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

  void _changeCurrency(String value) {
    if (value == _currency) return;
    setState(() {
      _currency = value;
      // Never reuse a price entered for another currency without conversion.
      for (var index = 0; index < _items.length; index++) {
        _items[index] = _items[index].copyWith(clearPrice: true);
      }
    });
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

  Future<ProductPriceLatest?> _latestPrice(
    ProductCatalogModel product,
    CatalogUnit unit,
  ) async {
    try {
      return await _prices.fetchLatest(
        brandId: _brandId,
        productId: product.id,
        unitId: unit.id,
        currency: _currency,
      );
    } catch (_) {
      // A missing suggestion must never block creation or expose an error to a
      // price-authorized user; the backend remains the source of truth.
      return null;
    }
  }

  Future<void> _addCatalogItem() async {
    final selection = await showPurchaseCatalogPicker(
      context,
      brandId: _brandId,
      service: _catalog,
      onCreateProduct: _createCatalogProductIfAuthorized,
    );
    if (!mounted || selection == null) return;
    final latest = await _latestPrice(selection.product, selection.unit);
    if (!mounted) return;
    final draft = await showDialog<PurchaseItemEditorResult>(
      context: context,
      builder: (_) => PurchaseItemEditorDialog.catalog(
        productName: selection.product.name,
        unitValue: selection.unit.displayValue,
        catalogUnits: selection.product.units,
        initialCatalogUnitId: selection.unit.id,
        initialProvisionalPrice: latest?.price,
        priceHelperText: latest == null
            ? 'لا يوجد سعر محفوظ لهذه المادة والوحدة.'
            : latest.sourceType == 'catalog_manual'
            ? 'اقتراح من تسعير دليل المواد.'
            : 'اقتراح من فاتورة سابقة: ${latest.sourceInvoiceId}',
        confirmLabel: 'إضافة',
      ),
    );
    if (!mounted || draft == null) return;
    final unit = selection.product.unitById(
      draft.catalogUnitId ?? selection.unit.id,
    );
    if (unit == null) return;
    setState(() {
      _items.add(
        _PurchaseDraftItem.catalog(
          product: selection.product,
          unit: unit,
          quantity: draft.quantity,
          provisionalPrice: draft.provisionalPrice,
          lineNotes: draft.lineNotes,
        ),
      );
    });
  }

  Future<CatalogSelection?> _createCatalogProductIfAuthorized() async {
    if (_brandId.trim().isEmpty) {
      _message('اختر الفرع المستلم أولاً.');
      return null;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _message('انتهت جلسة الدخول. سجل الدخول مجدداً.');
      return null;
    }
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = profile.data();
    final role = data?['role']?.toString();
    if (data == null ||
        (role != 'collector' && role != 'accountant') ||
        data['isActive'] == false) {
      // Do not turn an invoice screen into a catalog-management privilege.
      _message('إضافة مادة جديدة متاحة للمدير العام والمحاسب فقط.');
      return null;
    }
    final groups = await _catalog
        .watchGroups(brandId: _brandId, activeOnly: true)
        .first;
    if (!mounted) return null;
    if (groups.isEmpty) {
      _message('أضف مجموعة مواد نشطة من إدارة المواد أولاً.');
      return null;
    }
    final draft = await showCatalogProductEditor(context, groups: groups);
    if (!mounted || draft == null) return null;
    final actor = CatalogActor(
      uid: user.uid,
      name: data['name']?.toString().trim().isNotEmpty == true
          ? data['name'].toString().trim()
          : (role == 'collector' ? 'المدير العام' : 'المحاسب'),
      role: role!,
      active: data['isActive'] != false,
    );
    final productId = await _catalog.createProduct(
      actor: actor,
      brandId: _brandId,
      groupId: draft.groupId,
      name: draft.name,
      legacyCode: draft.legacyCode,
      units: draft.units,
      primaryUnitId: draft.primaryUnitId,
      sourceMetadata: const {'source_profile': 'manual'},
    );
    final product = await _catalog.fetchProduct(productId);
    if (product == null || product.units.isEmpty) {
      throw StateError('تعذر تحميل المادة التي أُنشئت.');
    }
    final unit = product.unitById(product.primaryUnitId) ?? product.units.first;
    return CatalogSelection(product: product, unit: unit);
  }

  Future<void> _addUnmatchedItem() async {
    final draft = await showDialog<PurchaseItemEditorResult>(
      context: context,
      builder: (_) =>
          const PurchaseItemEditorDialog.unmatched(confirmLabel: 'إضافة'),
    );
    if (!mounted || draft == null) return;
    setState(() {
      _items.add(
        _PurchaseDraftItem.unmatched(
          name: draft.materialName,
          group: draft.groupText,
          unit: draft.unitText,
          quantity: draft.quantity,
          provisionalPrice: draft.provisionalPrice,
          lineNotes: draft.lineNotes,
        ),
      );
    });
  }

  Future<void> _editItem(int index) async {
    final item = _items[index];
    if (!item.isUnmatched && item.product != null && item.catalogUnit != null) {
      final latest = await _latestPrice(item.product!, item.catalogUnit!);
      if (!mounted) return;
      final result = await showDialog<PurchaseItemEditorResult>(
        context: context,
        builder: (_) => PurchaseItemEditorDialog.catalog(
          productName: item.name,
          unitValue: item.unit,
          catalogUnits: item.product!.units,
          initialCatalogUnitId: item.catalogUnit!.id,
          initialQuantity: item.quantity,
          initialProvisionalPrice: item.provisionalPrice ?? latest?.price,
          initialLineNotes: item.lineNotes,
          priceHelperText: latest == null
              ? null
              : latest.sourceType == 'catalog_manual'
              ? 'آخر سعر محفوظ من تسعير دليل المواد.'
              : 'آخر سعر محفوظ: ${latest.sourceInvoiceId}',
        ),
      );
      if (!mounted || result == null) return;
      final unit = item.product!.unitById(
        result.catalogUnitId ?? item.catalogUnit!.id,
      );
      if (unit == null) return;
      setState(() {
        _items[index] = item.copyWith(
          catalogUnit: unit,
          quantity: result.quantity,
          provisionalPrice: result.provisionalPrice,
          lineNotes: result.lineNotes,
        );
      });
      return;
    }
    final result = await showDialog<PurchaseItemEditorResult>(
      context: context,
      builder: (_) => PurchaseItemEditorDialog.unmatched(
        initialMaterialName: item.name,
        initialGroupText: item.group,
        initialUnitText: item.unit,
        initialQuantity: item.quantity,
        initialProvisionalPrice: item.provisionalPrice,
        initialLineNotes: item.lineNotes,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _items[index] = _PurchaseDraftItem.unmatched(
        name: result.materialName,
        group: result.groupText,
        unit: result.unitText,
        quantity: result.quantity,
        provisionalPrice: result.provisionalPrice,
        lineNotes: result.lineNotes,
      );
    });
  }

  Future<void> _changeCatalogUnit(
    int index,
    _PurchaseDraftItem item,
    CatalogUnit unit,
  ) async {
    setState(
      () => _items[index] = item.copyWith(catalogUnit: unit, clearPrice: true),
    );
    final latest = await _latestPrice(item.product!, unit);
    if (!mounted || latest == null || index >= _items.length) return;
    final current = _items[index];
    if (current.product?.id == item.product!.id &&
        current.catalogUnit?.id == unit.id &&
        current.provisionalPrice == null) {
      setState(
        () => _items[index] = current.copyWith(provisionalPrice: latest.price),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _items.isEmpty) {
      _message('أكمل بيانات الفاتورة وأضف مادة واحدة على الأقل.');
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
        items: _items.map((item) => item.toInput()).toList(growable: false),
      );
      if (!mounted) return;
      Navigator.pop(context, result.invoiceId);
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  String _dateValue(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class _PurchaseDraftItem {
  final ProductCatalogModel? product;
  final CatalogUnit? catalogUnit;
  final String name;
  final String group;
  final String unit;
  final double quantity;
  final double? provisionalPrice;
  final String lineNotes;

  _PurchaseDraftItem.catalog({
    required ProductCatalogModel product,
    required CatalogUnit unit,
    required this.quantity,
    this.provisionalPrice,
    this.lineNotes = '',
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
    this.lineNotes = '',
  }) : product = null,
       catalogUnit = null;

  bool get isUnmatched => product == null;

  _PurchaseDraftItem copyWith({
    CatalogUnit? catalogUnit,
    String? unit,
    double? quantity,
    double? provisionalPrice,
    bool clearPrice = false,
    String? lineNotes,
  }) => _PurchaseDraftItem(
    product: product,
    catalogUnit: catalogUnit ?? this.catalogUnit,
    name: name,
    group: group,
    unit: catalogUnit?.displayValue ?? unit ?? this.unit,
    quantity: quantity ?? this.quantity,
    provisionalPrice: clearPrice
        ? null
        : provisionalPrice ?? this.provisionalPrice,
    lineNotes: lineNotes ?? this.lineNotes,
  );

  const _PurchaseDraftItem({
    required this.product,
    required this.catalogUnit,
    required this.name,
    required this.group,
    required this.unit,
    required this.quantity,
    required this.provisionalPrice,
    required this.lineNotes,
  });

  PurchaseInvoiceCreateItem toInput() => isUnmatched
      ? PurchaseInvoiceCreateItem.unmatched(
          materialName: name,
          groupText: group,
          unitText: unit,
          orderedQuantity: quantity,
          provisionalUnitPrice: provisionalPrice,
          lineNotes: lineNotes,
        )
      : PurchaseInvoiceCreateItem.catalog(
          productId: product!.id,
          unitId: catalogUnit!.id,
          orderedQuantity: quantity,
          provisionalUnitPrice: provisionalPrice,
          lineNotes: lineNotes,
        );
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

String _money(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);
