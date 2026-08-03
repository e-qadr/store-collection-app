import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';

class PurchaseCatalogSelection {
  final ProductCatalogModel product;
  final CatalogUnit unit;

  const PurchaseCatalogSelection({required this.product, required this.unit});
}

Future<PurchaseCatalogSelection?> showPurchaseCatalogPicker(
  BuildContext context, {
  required String brandId,
  ProductCatalogService? service,
  String title = 'اختيار مادة من الكتالوج',
}) {
  return showDialog<PurchaseCatalogSelection>(
    context: context,
    builder: (_) => _PurchaseCatalogPickerDialog(
      brandId: brandId,
      service: service ?? ProductCatalogService(),
      title: title,
    ),
  );
}

class _PurchaseCatalogPickerDialog extends StatefulWidget {
  final String brandId;
  final ProductCatalogService service;
  final String title;

  const _PurchaseCatalogPickerDialog({
    required this.brandId,
    required this.service,
    required this.title,
  });

  @override
  State<_PurchaseCatalogPickerDialog> createState() =>
      _PurchaseCatalogPickerDialogState();
}

class _PurchaseCatalogPickerDialogState
    extends State<_PurchaseCatalogPickerDialog> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ProductCatalogModel> _products = const [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  String? _productId;
  String? _unitId;
  bool _loading = false;
  bool _hasMore = false;
  bool _pendingReset = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  ProductCatalogModel? get _product {
    for (final product in _products) {
      if (product.id == _productId) return product;
    }
    return null;
  }

  CatalogUnit? get _unit => _product?.unitById(_unitId ?? '');

  Future<void> _load({required bool reset}) async {
    if (_loading) {
      if (reset) _pendingReset = true;
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.fetchActiveProductsPage(
        brandId: widget.brandId,
        search: _search.text,
        after: reset ? null : _cursor,
        pageSize: 30,
      );
      if (!mounted) return;
      setState(() {
        _products = reset ? page.products : [..._products, ...page.products];
        _cursor = page.cursor;
        _hasMore = page.hasMore;
        if (reset && !_products.any((entry) => entry.id == _productId)) {
          _productId = null;
          _unitId = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحميل كتالوج العلامة.');
    } finally {
      if (mounted) {
        final reload = _pendingReset;
        _pendingReset = false;
        setState(() => _loading = false);
        if (reload) unawaited(_load(reset: true));
      }
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _load(reset: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final unit = _unit;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _search,
                  onChanged: _searchChanged,
                  decoration: const InputDecoration(
                    labelText: 'بحث باسم المادة',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey(
                    'purchase-product-${_products.length}-$_productId',
                  ),
                  initialValue: _productId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'المادة'),
                  items: _products
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.id,
                          child: Text(
                            entry.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _loading
                      ? null
                      : (value) => setState(() {
                          _productId = value;
                          _unitId = null;
                        }),
                ),
                if (_hasMore)
                  TextButton.icon(
                    onPressed: _loading ? null : () => _load(reset: false),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('تحميل منتجات أخرى'),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('purchase-unit-${product?.id ?? 'none'}'),
                  initialValue: _unitId,
                  decoration: const InputDecoration(labelText: 'الوحدة'),
                  items: (product?.units ?? const <CatalogUnit>[])
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.id,
                          child: Text(entry.displayValue),
                        ),
                      )
                      .toList(),
                  onChanged: product == null
                      ? null
                      : (value) => setState(() => _unitId = value),
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                if (!_loading && _products.isEmpty && _error == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('لا توجد مواد مطابقة للبحث.'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: product == null || unit == null
                ? null
                : () => Navigator.pop(
                    context,
                    PurchaseCatalogSelection(product: product, unit: unit),
                  ),
            child: const Text('اختيار'),
          ),
        ],
      ),
    );
  }
}
