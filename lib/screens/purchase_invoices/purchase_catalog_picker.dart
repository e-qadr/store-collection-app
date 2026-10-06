import 'dart:async';

import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/catalog_operation_error.dart';

enum CatalogPickerMode { purchase, consumption, transfer }

class CatalogSelection {
  final ProductCatalogModel product;
  final CatalogUnit unit;

  const CatalogSelection({required this.product, required this.unit});
}

typedef PurchaseCatalogSelection = CatalogSelection;
typedef CatalogProductCreator = Future<CatalogSelection?> Function();

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
  CatalogProductCreator? onCreateProduct,
}) {
  return showCatalogPicker(
    context,
    brandId: brandId,
    service: service,
    title: title,
    mode: CatalogPickerMode.purchase,
    products: products,
    onCreateProduct: onCreateProduct,
  );
}

Future<CatalogSelection?> showCatalogPicker(
  BuildContext context, {
  required String brandId,
  required CatalogPickerMode mode,
  ProductCatalogService? service,
  String title = 'اختيار مادة من الكتالوج',
  List<ProductCatalogModel>? products,
  CatalogProductCreator? onCreateProduct,
}) {
  // A full-height, keyboard-aware sheet keeps the search results usable on
  // phones.  AlertDialog has a fixed centred layout, which left the result
  // list hidden behind the soft keyboard on smaller screens.
  return showModalBottomSheet<CatalogSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PurchaseCatalogPickerDialog(
      brandId: brandId,
      service: service,
      title: title,
      mode: mode,
      products: products,
      onCreateProduct: onCreateProduct,
    ),
  );
}

class _PurchaseCatalogPickerDialog extends StatefulWidget {
  final String brandId;
  final ProductCatalogService? service;
  final String title;
  final CatalogPickerMode mode;
  final List<ProductCatalogModel>? products;
  final CatalogProductCreator? onCreateProduct;

  const _PurchaseCatalogPickerDialog({
    required this.brandId,
    required this.service,
    required this.title,
    required this.mode,
    this.products,
    this.onCreateProduct,
  });

  @override
  State<_PurchaseCatalogPickerDialog> createState() =>
      _PurchaseCatalogPickerDialogState();
}

class _PurchaseCatalogPickerDialogState
    extends State<_PurchaseCatalogPickerDialog> {
  late final ProductCatalogService _service =
      widget.service ?? ProductCatalogService();
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
      final pageFuture = _service.fetchActiveProductsPage(
        brandId: widget.brandId,
        search: _search.text,
        offset: reset ? 0 : _products.length,
        pageSize: 40,
      );
      final groupNamesFuture = _service.fetchActiveGroupNames(
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

  Future<void> _createProduct() async {
    final creator = widget.onCreateProduct;
    if (creator == null || _loading) return;
    setState(() => _loading = true);
    try {
      final selection = await creator();
      if (mounted && selection != null) Navigator.pop(context, selection);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              catalogOperationErrorText(error) ??
                  'تعذر إكمال العملية. تحقق من البيانات وحاول مرة أخرى.',
            ),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final availableHeight = media.size.height - media.viewInsets.bottom;
    final sheetHeight = (availableHeight - 12)
        .clamp(0.0, media.size.height * 0.92)
        .toDouble();
    final colors = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Material(
              key: Key('shared-catalog-picker-${widget.mode.name}'),
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: sheetHeight,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.oliveSurface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.inventory_2_outlined),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'ابحث عن المادة ثم اختر وحدتها لإضافتها.',
                                  style: TextStyle(
                                    color: AppTheme.textHint,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'إغلاق',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        key: const Key('shared-catalog-search'),
                        controller: _search,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: _searchChanged,
                        decoration: InputDecoration(
                          labelText: 'البحث في الكتالوج',
                          hintText: 'اسم المادة أو رمزها',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'مسح البحث',
                                  onPressed: () {
                                    _search.clear();
                                    _searchChanged('');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.format_list_bulleted_rounded,
                            size: 19,
                            color: AppTheme.darkOlive,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              _products.isEmpty
                                  ? 'نتائج البحث'
                                  : '${_products.length} مادة متاحة',
                              style: const TextStyle(
                                color: AppTheme.textHint,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const Text(
                            'اضغط لاختيار المادة',
                            style: TextStyle(
                              color: AppTheme.textHint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _loading && _products.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppTheme.errorColor,
                                  ),
                                ),
                              ),
                            )
                          : _products.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off_rounded,
                                      size: 38,
                                      color: colors.outline,
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'لا توجد مادة مطابقة.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'جرّب الاسم أو الرمز، ثم أضف مادة جديدة عند الحاجة.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppTheme.textHint,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              itemCount: _products.length + (_hasMore ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                if (index == _products.length) {
                                  return OutlinedButton.icon(
                                    onPressed: _loading
                                        ? null
                                        : () => _load(reset: false),
                                    icon: const Icon(Icons.expand_more_rounded),
                                    label: const Text('تحميل نتائج إضافية'),
                                  );
                                }
                                final product = _products[index];
                                final expanded =
                                    product.id == _expandedProductId;
                                final code = product.legacyCode?.trim() ?? '';
                                final groupName = catalogGroupDisplayName(
                                  product,
                                  _groupNames,
                                );
                                return Material(
                                  color: colors.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    key: Key(
                                      'shared-catalog-product-${product.id}',
                                    ),
                                    borderRadius: BorderRadius.circular(16),
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
                                                        .unitById(
                                                          product.primaryUnitId,
                                                        )
                                                        ?.id ??
                                                    product.units.first.id;
                                        });
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.oliveSurface,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Icon(
                                                  Icons.inventory_2_outlined,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 11),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      product.name,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      product.units.length == 1
                                                          ? 'الوحدة: ${product.units.single.displayValue}'
                                                          : '${product.units.length} وحدات — اختر الوحدة',
                                                      style: const TextStyle(
                                                        color:
                                                            AppTheme.textHint,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                product.units.length == 1
                                                    ? Icons
                                                          .arrow_back_ios_new_rounded
                                                    : expanded
                                                    ? Icons
                                                          .keyboard_arrow_up_rounded
                                                    : Icons
                                                          .keyboard_arrow_down_rounded,
                                                size: 20,
                                                color: AppTheme.darkOlive,
                                              ),
                                            ],
                                          ),
                                          if (code.isNotEmpty ||
                                              groupName != null)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 8,
                                                right: 47,
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
                                                top: 12,
                                                right: 47,
                                              ),
                                              child: Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: product.units
                                                    .map((unit) {
                                                      final selected =
                                                          unit.id ==
                                                          _expandedUnitId;
                                                      return ChoiceChip(
                                                        key: Key(
                                                          'shared-catalog-unit-${product.id}-${unit.id}',
                                                        ),
                                                        selected: selected,
                                                        label: Text(
                                                          unit.displayValue,
                                                        ),
                                                        labelStyle: TextStyle(
                                                          color: selected
                                                              ? colors
                                                                    .onPrimaryContainer
                                                              : colors
                                                                    .onSurface,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        backgroundColor: colors
                                                            .surfaceContainerHighest,
                                                        selectedColor: colors
                                                            .primaryContainer,
                                                        side: BorderSide(
                                                          color: selected
                                                              ? colors.primary
                                                              : colors
                                                                    .outlineVariant,
                                                        ),
                                                        checkmarkColor: colors
                                                            .onPrimaryContainer,
                                                        avatar: Icon(
                                                          Icons
                                                              .straighten_rounded,
                                                          size: 18,
                                                          color: selected
                                                              ? colors
                                                                    .onPrimaryContainer
                                                              : colors
                                                                    .onSurface,
                                                        ),
                                                        onSelected: (_) =>
                                                            _select(
                                                              product,
                                                              unit,
                                                            ),
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
                      const LinearProgressIndicator(),
                    if (widget.onCreateProduct != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border(
                            top: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                        child: OutlinedButton.icon(
                          key: const Key('purchase-add-new-catalog-material'),
                          onPressed: _loading ? null : _createProduct,
                          icon: const Icon(Icons.add_box_outlined),
                          label: const Text(
                            'لا تجد المادة؟ أضفها إلى الكتالوج',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
