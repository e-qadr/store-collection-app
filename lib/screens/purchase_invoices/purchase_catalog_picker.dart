import 'dart:async';

import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';

enum CatalogPickerMode { purchase, consumption, transfer }

class CatalogSelection {
  final ProductCatalogModel product;
  final CatalogUnit unit;

  const CatalogSelection({required this.product, required this.unit});
}

typedef PurchaseCatalogSelection = CatalogSelection;

/// Returns a human-readable group name only. Product group IDs are internal
/// catalog identities and must never be rendered as a fallback label.
String? catalogGroupDisplayName(
  ProductCatalogModel product,
  Map<String, String> groupNames,
) {
  final name = groupNames[product.groupId]?.trim() ?? '';
  return name.isEmpty || name == product.groupId ? null : name;
}

/// Local, brand-scoped material search. The service caches catalog pages, so
/// typing filters the loaded catalog rather than querying Firestore per key.
Future<PurchaseCatalogSelection?> showPurchaseCatalogPicker(
  BuildContext context, {
  required String brandId,
  ProductCatalogService? service,
  String title = 'اختيار مادة من الكتالوج',
  List<ProductCatalogModel>? products,
}) {
  return showCatalogPicker(
    context,
    brandId: brandId,
    service: service,
    title: title,
    mode: CatalogPickerMode.purchase,
    products: products,
  );
}

Future<CatalogSelection?> showCatalogPicker(
  BuildContext context, {
  required String brandId,
  required CatalogPickerMode mode,
  ProductCatalogService? service,
  String title = 'اختيار مادة من الكتالوج',
  List<ProductCatalogModel>? products,
}) {
  return showDialog<CatalogSelection>(
    context: context,
    builder: (_) => _PurchaseCatalogPickerDialog(
      brandId: brandId,
      service: service,
      title: title,
      mode: mode,
      products: products,
    ),
  );
}

class _PurchaseCatalogPickerDialog extends StatefulWidget {
  final String brandId;
  final ProductCatalogService? service;
  final String title;
  final CatalogPickerMode mode;
  final List<ProductCatalogModel>? products;

  const _PurchaseCatalogPickerDialog({
    required this.brandId,
    required this.service,
    required this.title,
    required this.mode,
    this.products,
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
  Map<String, String> _groupNames = const {};
  String? _expandedProductId;
  String? _expandedUnitId;
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
      if (widget.products != null) {
        final filtered = filterCatalogProducts(widget.products!, _search.text);
        if (!mounted) return;
        setState(() {
          _products = filtered;
          _groupNames = const {};
          _hasMore = false;
        });
        return;
      }
      final service = widget.service ?? ProductCatalogService();
      final pageFuture = service.fetchActiveProductsPage(
        brandId: widget.brandId,
        search: _search.text,
        offset: reset ? 0 : _products.length,
        pageSize: 40,
      );
      final groupNamesFuture = service.fetchActiveGroupNames(
        brandId: widget.brandId,
      );
      final page = await pageFuture;
      Map<String, String> groupNames = const {};
      try {
        groupNames = await groupNamesFuture;
      } catch (_) {
        // Group names are presentation-only. The product list remains usable
        // and unresolved groups stay hidden instead of exposing raw IDs.
      }
      if (!mounted) return;
      setState(() {
        _products = reset ? page.products : [..._products, ...page.products];
        _groupNames = groupNames;
        _hasMore = page.hasMore;
        if (!_products.any((entry) => entry.id == _expandedProductId)) {
          _expandedProductId = null;
          _expandedUnitId = null;
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
    Navigator.pop(context, CatalogSelection(product: product, unit: unit));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        key: Key('shared-catalog-picker-${widget.mode.name}'),
        title: Text(widget.title),
        content: SizedBox(
          width: 560,
          height: 520,
          child: Column(
            children: [
              TextField(
                key: const Key('shared-catalog-search'),
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
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              else if (_products.isEmpty)
                const Expanded(
                  child: Center(child: Text('لا توجد مواد مطابقة للبحث.')),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _products.length + (_hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == _products.length) {
                        return TextButton.icon(
                          onPressed: _loading
                              ? null
                              : () => _load(reset: false),
                          icon: const Icon(Icons.expand_more_rounded),
                          label: const Text('تحميل نتائج إضافية'),
                        );
                      }
                      final product = _products[index];
                      final expanded = product.id == _expandedProductId;
                      final code = product.legacyCode?.trim() ?? '';
                      final groupName = catalogGroupDisplayName(
                        product,
                        _groupNames,
                      );
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: Key('shared-catalog-product-${product.id}'),
                          onTap: () {
                            if (product.units.length == 1) {
                              _select(product, product.units.single);
                            } else {
                              setState(() {
                                _expandedProductId = expanded
                                    ? null
                                    : product.id;
                                _expandedUnitId = expanded
                                    ? null
                                    : product
                                              .unitById(product.primaryUnitId)
                                              ?.id ??
                                          product.units.first.id;
                              });
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 4,
                            ),
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (product.units.length > 1)
                                      Icon(
                                        expanded
                                            ? Icons.expand_less
                                            : Icons.expand_more,
                                      ),
                                  ],
                                ),
                                if (code.isNotEmpty || groupName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 3,
                                      right: 34,
                                    ),
                                    child: Text(
                                      [
                                        if (code.isNotEmpty) code,
                                        if (groupName != null)
                                          'المجموعة: $groupName',
                                      ].join(' • '),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                if (expanded)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 8,
                                      right: 34,
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: product.units
                                          .map((unit) {
                                            final selected =
                                                unit.id == _expandedUnitId;
                                            final colors = Theme.of(
                                              context,
                                            ).colorScheme;
                                            return ChoiceChip(
                                              key: Key(
                                                'shared-catalog-unit-${product.id}-${unit.id}',
                                              ),
                                              selected: selected,
                                              label: Text(unit.displayValue),
                                              labelStyle: TextStyle(
                                                color: selected
                                                    ? colors.onPrimaryContainer
                                                    : colors.onSurface,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              backgroundColor: colors
                                                  .surfaceContainerHighest,
                                              selectedColor:
                                                  colors.primaryContainer,
                                              side: BorderSide(
                                                color: selected
                                                    ? colors.primary
                                                    : colors.outlineVariant,
                                              ),
                                              checkmarkColor:
                                                  colors.onPrimaryContainer,
                                              avatar: Icon(
                                                Icons.straighten_rounded,
                                                size: 18,
                                                color: selected
                                                    ? colors.onPrimaryContainer
                                                    : colors.onSurface,
                                              ),
                                              onSelected: (_) =>
                                                  _select(product, unit),
                                            );
                                          })
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
