import 'dart:async';

import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';

class PurchaseCatalogSelection {
  final ProductCatalogModel product;
  final CatalogUnit unit;

  const PurchaseCatalogSelection({required this.product, required this.unit});
}

/// Local, brand-scoped material search. The service caches catalog pages, so
/// typing filters the loaded catalog rather than querying Firestore per key.
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
  String? _expandedProductId;
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
        offset: reset ? 0 : _products.length,
        pageSize: 40,
      );
      if (!mounted) return;
      setState(() {
        _products = reset ? page.products : [..._products, ...page.products];
        _hasMore = page.hasMore;
        if (!_products.any((entry) => entry.id == _expandedProductId)) {
          _expandedProductId = null;
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
    _debounce = Timer(const Duration(milliseconds: 220), () {
      _load(reset: true);
    });
  }

  void _select(ProductCatalogModel product, CatalogUnit unit) {
    Navigator.pop(context, PurchaseCatalogSelection(product: product, unit: unit));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 560,
          height: 520,
          child: Column(
            children: [
              TextField(
                key: const Key('purchase-catalog-search'),
                controller: _search,
                autofocus: true,
                onChanged: _searchChanged,
                decoration: const InputDecoration(
                  labelText: 'ابحث باسم المادة أو رمزها',
                  hintText: 'بحث مطابق، ثم بادئ، ثم يحتوي',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 10),
              if (_loading && _products.isEmpty)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                )
              else if (_products.isEmpty)
                const Expanded(child: Center(child: Text('لا توجد مواد مطابقة للبحث.')))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _products.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == _products.length) {
                        return TextButton.icon(
                          onPressed: _loading ? null : () => _load(reset: false),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('تحميل نتائج إضافية'),
                        );
                      }
                      final product = _products[index];
                      final expanded = product.id == _expandedProductId;
                      final code = product.legacyCode?.trim() ?? '';
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: Key('purchase-catalog-product-${product.id}'),
                          onTap: () {
                            if (product.units.length == 1) {
                              _select(product, product.units.single);
                            } else {
                              setState(() => _expandedProductId = expanded ? null : product.id);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.inventory_2_outlined),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        product.name,
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    if (product.units.length > 1)
                                      Icon(expanded ? Icons.expand_less : Icons.expand_more),
                                  ],
                                ),
                                if (code.isNotEmpty || product.groupId.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3, right: 34),
                                    child: Text(
                                      [if (code.isNotEmpty) code, 'المجموعة: ${product.groupId}'].join(' • '),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                if (expanded)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8, right: 34),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: product.units
                                          .map((unit) => ActionChip(
                                                key: Key('purchase-catalog-unit-${product.id}-${unit.id}'),
                                                label: Text(unit.displayValue),
                                                avatar: const Icon(Icons.straighten_rounded, size: 18),
                                                onPressed: () => _select(product, unit),
                                              ))
                                          .toList(growable: false),
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
              if (_loading && _products.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}
