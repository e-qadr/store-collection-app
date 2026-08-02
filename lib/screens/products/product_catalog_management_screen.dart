import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/catalog_normalization.dart';

({CatalogUnit? unit2, CatalogUnit? unit3}) catalogEditorSecondaryUnitSlots(
  ProductCatalogModel? product,
) {
  if (product == null) return (unit2: null, unit3: null);

  final secondaryUnits = product.units
      .where((unit) => unit.id != product.primaryUnitId)
      .toList(growable: false);
  CatalogUnit? unit2;
  CatalogUnit? unit3;
  final legacyUnits = <CatalogUnit>[];

  for (final unit in secondaryUnits) {
    if (unit.id == 'unit_2' && unit2 == null) {
      unit2 = unit;
    } else if (unit.id == 'unit_3' && unit3 == null) {
      unit3 = unit;
    } else {
      legacyUnits.add(unit);
    }
  }

  if (unit2 == null && unit3 == null) {
    if (legacyUnits.length == 1 &&
        _legacySingleSecondaryWasUnit3(product.sourceMetadata)) {
      unit3 = legacyUnits.single;
    } else {
      if (legacyUnits.isNotEmpty) unit2 = legacyUnits.first;
      if (legacyUnits.length > 1) unit3 = legacyUnits[1];
    }
  } else {
    for (final unit in legacyUnits) {
      if (unit2 == null) {
        unit2 = unit;
      } else {
        unit3 ??= unit;
      }
    }
  }

  return (unit2: unit2, unit3: unit3);
}

bool _legacySingleSecondaryWasUnit3(Map<String, dynamic> sourceMetadata) {
  final rawUnit2 = sourceMetadata['raw_unit_2']?.toString().trim() ?? '';
  final rawUnit3 = sourceMetadata['raw_unit_3']?.toString().trim() ?? '';
  return rawUnit2.isEmpty && rawUnit3.isNotEmpty;
}

CatalogUnit catalogEditorUpdatedUnit({
  required CatalogUnit? existing,
  required String fallbackId,
  required String rawValue,
}) {
  final unchanged = existing?.rawValue == rawValue;
  return CatalogUnit(
    id: existing?.id ?? fallbackId,
    displayValue: unchanged ? existing!.displayValue : rawValue,
    rawValue: rawValue,
    normalizedValue: unchanged ? existing!.normalizedValue : null,
  );
}

class ProductCatalogManagementScreen extends StatefulWidget {
  final ProductCatalogService? service;

  const ProductCatalogManagementScreen({super.key, this.service});

  @override
  State<ProductCatalogManagementScreen> createState() =>
      _ProductCatalogManagementScreenState();
}

class _ProductCatalogManagementScreenState
    extends State<ProductCatalogManagementScreen> {
  late final ProductCatalogService _service;
  final _searchController = TextEditingController();
  String? _selectedBrandId;
  String? _selectedGroupId;
  bool _includeInactive = false;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProductCatalogService();
    _searchController.addListener(_refreshSearch);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshSearch)
      ..dispose();
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

  Future<CatalogActor> _currentActor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('انتهت جلسة الدخول. سجل الدخول مجدداً.');
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = profile.data();
    if (data == null || data['role'] != 'accountant') {
      throw Exception('إدارة دليل المواد متاحة للمحاسب فقط.');
    }
    return CatalogActor(
      uid: user.uid,
      name: data['name']?.toString().trim().isNotEmpty == true
          ? data['name'].toString().trim()
          : 'المحاسب',
      role: data['role'].toString(),
      active: data['isActive'] != false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text('دليل المواد والمنتجات'),
          backgroundColor: AppTheme.accountantColor,
          actions: [
            IconButton(
              tooltip: 'إضافة مجموعة',
              onPressed: _selectedBrandId == null || _mutating
                  ? null
                  : _createGroup,
              icon: const Icon(Icons.create_new_folder_rounded),
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('brands')
              .orderBy('name')
              .snapshots(),
          builder: (context, brandSnapshot) {
            if (brandSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (brandSnapshot.hasError) {
              return const _CatalogMessage(
                icon: Icons.cloud_off_rounded,
                text: 'تعذر تحميل العلامات التجارية.',
              );
            }
            final brands = brandSnapshot.data?.docs ?? const [];
            if (brands.isEmpty) {
              return const _CatalogMessage(
                icon: Icons.business_outlined,
                text: 'لا توجد علامات تجارية. يجب إنشاؤها من الإدارة أولاً.',
              );
            }
            final selectedBrandId =
                brands.any((brand) => brand.id == _selectedBrandId)
                ? _selectedBrandId!
                : brands.first.id;
            if (_selectedBrandId != selectedBrandId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _selectedBrandId != selectedBrandId) {
                  setState(() => _selectedBrandId = selectedBrandId);
                }
              });
            }
            return _buildForBrand(brands, selectedBrandId);
          },
        ),
      ),
    );
  }

  Widget _buildForBrand(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> brands,
    String brandId,
  ) {
    return StreamBuilder<List<ProductGroupModel>>(
      stream: _service.watchGroups(
        brandId: brandId,
        activeOnly: !_includeInactive,
      ),
      builder: (context, groupSnapshot) {
        final groups = groupSnapshot.data ?? const <ProductGroupModel>[];
        final effectiveGroupId =
            groups.any((group) => group.id == _selectedGroupId)
            ? _selectedGroupId
            : null;
        return Column(
          children: [
            _CatalogFilters(
              brands: brands,
              groups: groups,
              selectedBrandId: brandId,
              selectedGroupId: effectiveGroupId,
              includeInactive: _includeInactive,
              searchController: _searchController,
              onBrandChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedBrandId = value;
                  _selectedGroupId = null;
                });
              },
              onGroupChanged: (value) {
                setState(() => _selectedGroupId = value);
              },
              onIncludeInactiveChanged: (value) {
                setState(() {
                  _includeInactive = value;
                  _selectedGroupId = null;
                });
              },
              onCreateProduct: _mutating ? null : () => _createProduct(groups),
            ),
            if (_mutating) const LinearProgressIndicator(minHeight: 2),
            if (groupSnapshot.hasError)
              const Expanded(
                child: _CatalogMessage(
                  icon: Icons.error_outline_rounded,
                  text: 'تعذر تحميل مجموعات هذه العلامة.',
                ),
              )
            else
              Expanded(
                child: _ProductList(
                  stream: _service.watchProducts(
                    brandId: brandId,
                    groupId: effectiveGroupId,
                    activeOnly: !_includeInactive,
                  ),
                  searchText: _searchController.text,
                  groups: groups,
                  onEdit: (product) => _editProduct(product, groups),
                  onAccounting: _editAccountingProfile,
                  onHistory: _showHistory,
                  onArchive: _archiveProduct,
                  onReactivate: _reactivateProduct,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _createGroup() async {
    if (_mutating) return;
    final brandId = _selectedBrandId;
    if (brandId == null) return;
    final nameController = TextEditingController();
    final codeController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة مجموعة مواد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'اسم المجموعة *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: codeController,
              decoration: const InputDecoration(
                labelText: 'رمز المجموعة القديم (اختياري)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    final name = nameController.text.trim();
    final legacyCode = codeController.text.trim();
    nameController.dispose();
    codeController.dispose();
    if (accepted != true) return;
    if (name.isEmpty) {
      _message('اسم المجموعة مطلوب.', isError: true);
      return;
    }
    await _performMutation(
      operation: () async => _service.createGroup(
        actor: await _currentActor(),
        brandId: brandId,
        name: name,
        legacyCode: legacyCode.isEmpty ? null : legacyCode,
      ),
      successMessage: 'تمت إضافة المجموعة.',
    );
  }

  Future<void> _createProduct(List<ProductGroupModel> groups) async {
    if (_mutating) return;
    final brandId = _selectedBrandId;
    if (brandId == null) return;
    if (groups.where((group) => group.active).isEmpty) {
      _message('أضف مجموعة نشطة قبل إضافة المنتج.', isError: true);
      return;
    }
    final draft = await _showProductDialog(groups: groups);
    if (draft == null) return;
    await _performMutation(
      operation: () async => _service.createProduct(
        actor: await _currentActor(),
        brandId: brandId,
        groupId: draft.groupId,
        name: draft.name,
        legacyCode: draft.legacyCode,
        units: draft.units,
        primaryUnitId: draft.primaryUnitId,
        sourceMetadata: const {'source_profile': 'manual'},
      ),
      successMessage: 'تمت إضافة المنتج إلى الدليل.',
    );
  }

  Future<void> _editProduct(
    ProductCatalogModel product,
    List<ProductGroupModel> groups,
  ) async {
    if (_mutating) return;
    final draft = await _showProductDialog(product: product, groups: groups);
    if (draft == null) return;
    await _performMutation(
      operation: () async => _service.updateProduct(
        actor: await _currentActor(),
        productId: product.id,
        groupId: draft.groupId,
        name: draft.name,
        legacyCode: draft.legacyCode,
        units: draft.units,
        primaryUnitId: draft.primaryUnitId,
        sourceMetadata: product.sourceMetadata,
      ),
      successMessage: 'تم تحديث المنتج وحفظ سجل التغيير.',
    );
  }

  Future<void> _editAccountingProfile(ProductCatalogModel product) async {
    if (_mutating) return;
    ProductAccountingProfile? current;
    try {
      current = await _service
          .watchAccountingProfile(productId: product.id)
          .first;
    } catch (error) {
      _message(_errorText(error), isError: true);
      return;
    }
    if (!mounted) return;
    final referenceController = TextEditingController(
      text: current?.accountingReference ?? '',
    );
    final notesController = TextEditingController(text: current?.notes ?? '');
    var syncState = current?.syncState ?? 'not_synced';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('ربط ${product.name} بالنظام المحاسبي'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: referenceController,
                  decoration: const InputDecoration(
                    labelText: 'مرجع المنتج في النظام المحاسبي (اختياري)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: syncState,
                  decoration: const InputDecoration(labelText: 'حالة المزامنة'),
                  items: const [
                    DropdownMenuItem(
                      value: 'not_synced',
                      child: Text('غير متزامن'),
                    ),
                    DropdownMenuItem(
                      value: 'pending',
                      child: Text('بانتظار المزامنة'),
                    ),
                    DropdownMenuItem(value: 'synced', child: Text('متزامن')),
                    DropdownMenuItem(
                      value: 'sync_error',
                      child: Text('خطأ في المزامنة'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => syncState = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات المحاسب (اختياري)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    final reference = referenceController.text.trim();
    final notes = notesController.text.trim();
    referenceController.dispose();
    notesController.dispose();
    if (accepted != true) return;
    await _performMutation(
      operation: () async => _service.upsertAccountingProfile(
        actor: await _currentActor(),
        productId: product.id,
        accountingReference: reference.isEmpty ? null : reference,
        syncState: syncState,
        notes: notes.isEmpty ? null : notes,
      ),
      successMessage: 'تم تحديث مرجع المنتج وحالة المزامنة.',
    );
  }

  Future<_ProductDraft?> _showProductDialog({
    ProductCatalogModel? product,
    required List<ProductGroupModel> groups,
  }) async {
    final activeGroups = groups.where((group) => group.active).toList();
    if (product != null &&
        !activeGroups.any((group) => group.id == product.groupId)) {
      final current = groups.where((group) => group.id == product.groupId);
      if (current.isNotEmpty) activeGroups.add(current.first);
    }
    final nameController = TextEditingController(text: product?.name ?? '');
    final codeController = TextEditingController(
      text: product?.legacyCode ?? '',
    );
    final primaryController = TextEditingController(
      text: product?.unitById(product.primaryUnitId)?.rawValue ?? '',
    );
    final secondaryUnitSlots = catalogEditorSecondaryUnitSlots(product);
    final unit2Controller = TextEditingController(
      text: secondaryUnitSlots.unit2?.rawValue ?? '',
    );
    final unit3Controller = TextEditingController(
      text: secondaryUnitSlots.unit3?.rawValue ?? '',
    );
    String? groupId = activeGroups.any((group) => group.id == product?.groupId)
        ? product!.groupId
        : activeGroups.isEmpty
        ? null
        : activeGroups.first.id;
    String? validationError;

    final draft = await showDialog<_ProductDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(product == null ? 'إضافة منتج' : 'تعديل المنتج'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: groupId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'المجموعة *'),
                    items: activeGroups
                        .map(
                          (group) => DropdownMenuItem(
                            value: group.id,
                            child: Text(group.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => groupId = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المادة أو المنتج *',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'رمز المادة القديم (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: primaryController,
                    decoration: const InputDecoration(
                      labelText: 'الوحدة الأساسية *',
                      helperText: 'تُحفظ الكتابة الأصلية كما أدخلها المحاسب.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: unit2Controller,
                    decoration: const InputDecoration(
                      labelText: 'الوحدة 2 (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: unit3Controller,
                    decoration: const InputDecoration(
                      labelText: 'الوحدة 3 (اختياري)',
                    ),
                  ),
                  if (validationError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      validationError!,
                      style: const TextStyle(color: AppTheme.errorColor),
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'الوحدات مستقلة؛ لا يجري أي تحويل تلقائي بينها. ولا تُحفظ الأسعار في هذا المستند.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
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
            FilledButton.icon(
              onPressed: () {
                final name = nameController.text.trim();
                final primary = primaryController.text.trim();
                if (groupId == null || name.isEmpty || primary.isEmpty) {
                  setDialogState(() {
                    validationError =
                        'المجموعة واسم المنتج والوحدة الأساسية حقول مطلوبة.';
                  });
                  return;
                }
                final units = <CatalogUnit>[
                  catalogEditorUpdatedUnit(
                    existing: product?.unitById(product.primaryUnitId),
                    fallbackId: 'primary',
                    rawValue: primary,
                  ),
                  if (unit2Controller.text.trim().isNotEmpty)
                    catalogEditorUpdatedUnit(
                      existing: secondaryUnitSlots.unit2,
                      fallbackId: 'unit_2',
                      rawValue: unit2Controller.text.trim(),
                    ),
                  if (unit3Controller.text.trim().isNotEmpty)
                    catalogEditorUpdatedUnit(
                      existing: secondaryUnitSlots.unit3,
                      fallbackId: 'unit_3',
                      rawValue: unit3Controller.text.trim(),
                    ),
                ];
                Navigator.pop(
                  context,
                  _ProductDraft(
                    groupId: groupId!,
                    name: name,
                    legacyCode: codeController.text.trim().isEmpty
                        ? null
                        : codeController.text.trim(),
                    units: units,
                    primaryUnitId: units.first.id,
                  ),
                );
              },
              icon: const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    codeController.dispose();
    primaryController.dispose();
    unit2Controller.dispose();
    unit3Controller.dispose();
    return draft;
  }

  Future<void> _archiveProduct(ProductCatalogModel product) async {
    if (_mutating) return;
    final reason = await _askReason(
      title: 'أرشفة المنتج',
      prompt:
          'لن يُحذف «${product.name}». سيبقى صالحاً للفواتير السابقة ولن يظهر في الاختيارات الجديدة.',
    );
    if (reason == null) return;
    await _performMutation(
      operation: () async => _service.archiveProduct(
        actor: await _currentActor(),
        productId: product.id,
        reason: reason,
      ),
      successMessage: 'تمت أرشفة المنتج دون حذف بياناته.',
    );
  }

  Future<void> _reactivateProduct(ProductCatalogModel product) async {
    if (_mutating) return;
    final reason = await _askReason(
      title: 'إعادة تنشيط المنتج',
      prompt: 'اكتب سبب إعادة إظهار «${product.name}» في اختيارات الفواتير.',
    );
    if (reason == null) return;
    await _performMutation(
      operation: () async => _service.reactivateProduct(
        actor: await _currentActor(),
        productId: product.id,
        reason: reason,
      ),
      successMessage: 'أعيد تنشيط المنتج.',
    );
  }

  Future<String?> _askReason({
    required String title,
    required String prompt,
  }) async {
    final controller = TextEditingController();
    String? validationError;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(prompt),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'السبب *',
                  errorText: validationError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() => validationError = 'السبب مطلوب.');
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _showHistory(ProductCatalogModel product) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('سجل تغييرات ${product.name}'),
        content: SizedBox(
          width: 560,
          height: 420,
          child: StreamBuilder<List<ProductAuditEvent>>(
            stream: _service.watchProductAudit(productId: product.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return const _CatalogMessage(
                  icon: Icons.error_outline_rounded,
                  text: 'تعذر تحميل سجل المنتج.',
                );
              }
              final events = snapshot.data ?? const [];
              if (events.isEmpty) {
                return const _CatalogMessage(
                  icon: Icons.history_toggle_off_rounded,
                  text: 'لا توجد أحداث مسجلة.',
                );
              }
              return ListView.separated(
                itemCount: events.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final event = events[index];
                  final date = event.createdAt == null
                      ? 'بانتظار وقت الخادم'
                      : DateFormat('yyyy/MM/dd HH:mm').format(event.createdAt!);
                  return ListTile(
                    leading: const Icon(Icons.history_rounded),
                    title: Text(_auditActionLabel(event.action)),
                    subtitle: Text(
                      '${event.actorName} · $date'
                      '${event.reason == null ? '' : '\nالسبب: ${event.reason}'}',
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _message(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
      ),
    );
  }

  Future<void> _performMutation({
    required Future<void> Function() operation,
    required String successMessage,
  }) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    try {
      await operation();
      _message(successMessage);
    } catch (error) {
      _message(_errorText(error), isError: true);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  String _errorText(Object error) {
    final message = error.toString().replaceFirst(
      RegExp(r'^(Exception|Bad state|Invalid argument\(s\)):\s*'),
      '',
    );
    return switch (message) {
      'Only the accountant can manage the product catalog.' =>
        'إدارة دليل المواد متاحة للمحاسب فقط.',
      'The selected brand does not exist.' =>
        'العلامة التجارية المحددة غير موجودة.',
      'A normalized duplicate group already exists.' =>
        'توجد مجموعة مطابقة بعد توحيد طريقة الكتابة.',
      'The uncategorized system-group identity is reserved.' =>
        'مجموعة «غير مصنف» مجموعة نظامية ولا يمكن إنشاؤها يدويًا.',
      'The reserved uncategorized group ID is occupied by a conflicting document.' =>
        'تعذر تهيئة مجموعة «غير مصنف» بسبب تعارض في المعرّف المحجوز.',
      'A normalized duplicate product already exists.' =>
        'يوجد منتج مطابق في العلامة نفسها بالاسم أو الرمز.',
      'The selected product group was not found.' =>
        'مجموعة المنتج المحددة غير موجودة.',
      'The product group belongs to a different brand.' =>
        'المجموعة المحددة تتبع علامة تجارية أخرى.',
      'The selected product group is archived.' =>
        'المجموعة المحددة مؤرشفة ولا تقبل منتجات جديدة.',
      'Product was not found.' => 'المنتج غير موجود.',
      'Product is already archived.' => 'المنتج مؤرشف بالفعل.',
      'Product is already active.' => 'المنتج نشط بالفعل.',
      'Archived products must be reactivated before editing.' =>
        'يجب إعادة تنشيط المنتج المؤرشف قبل تعديله.',
      'Unsupported synchronization state.' => 'حالة المزامنة غير مدعومة.',
      _ => 'تعذر إكمال العملية. تحقق من البيانات وحاول مرة أخرى.',
    };
  }

  String _auditActionLabel(String action) {
    return switch (action) {
      'created' => 'إنشاء المنتج',
      'updated' => 'تعديل المنتج',
      'recategorized' => 'تغيير مجموعة المنتج',
      'archived' => 'أرشفة المنتج',
      'reactivated' => 'إعادة تنشيط المنتج',
      _ => action,
    };
  }
}

class _CatalogFilters extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> brands;
  final List<ProductGroupModel> groups;
  final String selectedBrandId;
  final String? selectedGroupId;
  final bool includeInactive;
  final TextEditingController searchController;
  final ValueChanged<String?> onBrandChanged;
  final ValueChanged<String?> onGroupChanged;
  final ValueChanged<bool> onIncludeInactiveChanged;
  final VoidCallback? onCreateProduct;

  const _CatalogFilters({
    required this.brands,
    required this.groups,
    required this.selectedBrandId,
    required this.selectedGroupId,
    required this.includeInactive,
    required this.searchController,
    required this.onBrandChanged,
    required this.onGroupChanged,
    required this.onIncludeInactiveChanged,
    required this.onCreateProduct,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedBrandId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'العلامة التجارية',
                    prefixIcon: Icon(Icons.business_rounded),
                  ),
                  items: brands
                      .map(
                        (brand) => DropdownMenuItem(
                          value: brand.id,
                          child: Text(
                            brand.data()['name']?.toString() ?? 'بدون اسم',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: onBrandChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: selectedGroupId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'المجموعة',
                    prefixIcon: Icon(Icons.category_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('كل المجموعات'),
                    ),
                    ...groups.map(
                      (group) => DropdownMenuItem<String?>(
                        value: group.id,
                        child: Text(group.name),
                      ),
                    ),
                  ],
                  onChanged: onGroupChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: searchController,
            decoration: InputDecoration(
              labelText: 'بحث بالاسم أو رمز المادة',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'مسح البحث',
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.clear_rounded),
                    ),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('عرض المنتجات والمجموعات المؤرشفة'),
            subtitle: const Text('لا تُحذف المنتجات المرتبطة بالفواتير.'),
            value: includeInactive,
            onChanged: onIncludeInactiveChanged,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCreateProduct,
              icon: const Icon(Icons.add_rounded),
              label: const Text('إضافة منتج إلى العلامة المحددة'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  final Stream<List<ProductCatalogModel>> stream;
  final String searchText;
  final List<ProductGroupModel> groups;
  final ValueChanged<ProductCatalogModel> onEdit;
  final ValueChanged<ProductCatalogModel> onAccounting;
  final ValueChanged<ProductCatalogModel> onHistory;
  final ValueChanged<ProductCatalogModel> onArchive;
  final ValueChanged<ProductCatalogModel> onReactivate;

  const _ProductList({
    required this.stream,
    required this.searchText,
    required this.groups,
    required this.onEdit,
    required this.onAccounting,
    required this.onHistory,
    required this.onArchive,
    required this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ProductCatalogModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const _CatalogMessage(
            icon: Icons.error_outline_rounded,
            text: 'تعذر تحميل دليل المواد.',
          );
        }
        final products = filterCatalogProducts(
          snapshot.data ?? const [],
          searchText,
        );
        if (products.isEmpty) {
          return const _CatalogMessage(
            icon: Icons.inventory_2_outlined,
            text: 'لا توجد منتجات مطابقة. استخدم زر الإضافة لإنشاء منتج.',
          );
        }
        final groupNames = {for (final group in groups) group.id: group.name};
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 92),
          itemCount: products.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final product = products[index];
            return Container(
              decoration: AppTheme.cardShadow(),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                leading: CircleAvatar(
                  backgroundColor: product.active
                      ? AppTheme.accountantColor.withValues(alpha: 0.1)
                      : Colors.grey.shade200,
                  child: Icon(
                    product.active
                        ? Icons.inventory_2_rounded
                        : Icons.inventory_2_outlined,
                    color: product.active
                        ? AppTheme.accountantColor
                        : Colors.grey,
                  ),
                ),
                title: Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    [
                      if (product.legacyCode != null)
                        'الرمز: ${product.legacyCode}',
                      'المجموعة: ${groupNames[product.groupId] ?? 'غير متاحة'}',
                      'الوحدات: ${product.units.map((unit) => unit.displayValue).join('، ')}',
                      if (!product.active) 'مؤرشف',
                    ].join(' · '),
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit(product);
                      case 'accounting':
                        onAccounting(product);
                      case 'history':
                        onHistory(product);
                      case 'archive':
                        onArchive(product);
                      case 'reactivate':
                        onReactivate(product);
                    }
                  },
                  itemBuilder: (context) => [
                    if (product.active)
                      const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                    const PopupMenuItem(
                      value: 'accounting',
                      child: Text('المرجع المحاسبي'),
                    ),
                    const PopupMenuItem(
                      value: 'history',
                      child: Text('سجل التغييرات'),
                    ),
                    if (product.active)
                      const PopupMenuItem(
                        value: 'archive',
                        child: Text('أرشفة'),
                      )
                    else
                      const PopupMenuItem(
                        value: 'reactivate',
                        child: Text('إعادة تنشيط'),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

List<ProductCatalogModel> filterCatalogProducts(
  Iterable<ProductCatalogModel> products,
  String searchText,
) {
  final normalizedSearch = normalizeCatalogText(searchText);
  if (normalizedSearch.isEmpty) return products.toList(growable: false);
  return products
      .where((product) {
        return product.normalizedName.contains(normalizedSearch) ||
            normalizeCatalogText(
              product.legacyCode ?? '',
            ).contains(normalizedSearch);
      })
      .toList(growable: false);
}

class _ProductDraft {
  final String groupId;
  final String name;
  final String? legacyCode;
  final List<CatalogUnit> units;
  final String primaryUnitId;

  const _ProductDraft({
    required this.groupId,
    required this.name,
    required this.legacyCode,
    required this.units,
    required this.primaryUnitId,
  });
}

class _CatalogMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _CatalogMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppTheme.textHint),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
