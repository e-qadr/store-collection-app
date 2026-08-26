import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/theme/app_theme.dart';

/// The one material editor used by both Material Management and purchase
/// creation. Persistence, uniqueness and audit validation remain in
/// [ProductCatalogService]; this component only collects the validated draft.
class CatalogProductDraft {
  final String groupId;
  final String name;
  final String? legacyCode;
  final List<CatalogUnit> units;
  final String primaryUnitId;

  const CatalogProductDraft({
    required this.groupId,
    required this.name,
    required this.legacyCode,
    required this.units,
    required this.primaryUnitId,
  });
}

Future<CatalogProductDraft?> showCatalogProductEditor(
  BuildContext context, {
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
  final codeController = TextEditingController(text: product?.legacyCode ?? '');
  final originalUnits = product == null
      ? const <CatalogUnit>[]
      : [
          if (product.unitById(product.primaryUnitId) != null)
            product.unitById(product.primaryUnitId)!,
          ...product.units.where((unit) => unit.id != product.primaryUnitId),
        ];
  final unitDrafts = originalUnits
      .map(_CatalogUnitDraft.fromExisting)
      .toList(growable: true);
  if (unitDrafts.isEmpty) unitDrafts.add(_CatalogUnitDraft.newPrimary());
  String? groupId = activeGroups.any((group) => group.id == product?.groupId)
      ? product!.groupId
      : activeGroups.isEmpty
      ? null
      : activeGroups.first.id;
  String? validationError;

  final result = await showDialog<CatalogProductDraft>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(product == null ? 'إضافة مادة' : 'تعديل المادة'),
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
                      .toList(growable: false),
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
                ...unitDrafts.indexed.expand((entry) {
                  final index = entry.$1;
                  final draft = entry.$2;
                  return [
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: draft.controller,
                            decoration: InputDecoration(
                              labelText: index == 0
                                  ? 'الوحدة الأساسية *'
                                  : 'الوحدة ${index + 1}',
                              helperText: index == 0
                                  ? 'تُحفظ الكتابة الأصلية كما أُدخلت.'
                                  : null,
                            ),
                          ),
                        ),
                        if (index > 0)
                          IconButton(
                            tooltip: 'إزالة الوحدة',
                            onPressed: () => setDialogState(() {
                              unitDrafts.removeAt(index).dispose();
                            }),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                      ],
                    ),
                  ];
                }),
                if (unitDrafts.length < maxCatalogUnits) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => setDialogState(() {
                        unitDrafts.add(
                          _CatalogUnitDraft.newAdditional(
                            _nextCatalogUnitId(unitDrafts),
                          ),
                        );
                      }),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('إضافة وحدة'),
                    ),
                  ),
                ],
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
                    'الوحدات مستقلة؛ لا يجري أي تحويل تلقائي بينها، ولا تُحفظ الأسعار في هذا النموذج.',
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
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: () {
              final name = nameController.text.trim();
              final primary = unitDrafts.first.controller.text.trim();
              if (groupId == null || name.isEmpty || primary.isEmpty) {
                setDialogState(() {
                  validationError =
                      'المجموعة واسم المادة والوحدة الأساسية حقول مطلوبة.';
                });
                return;
              }
              final units = unitDrafts
                  .where(
                    (draft) =>
                        draft == unitDrafts.first ||
                        draft.controller.text.trim().isNotEmpty,
                  )
                  .map(
                    (draft) => CatalogUnit(
                      id: draft.id,
                      displayValue:
                          draft.existing?.rawValue ==
                              draft.controller.text.trim()
                          ? draft.existing!.displayValue
                          : draft.controller.text.trim(),
                      rawValue: draft.controller.text.trim(),
                      normalizedValue:
                          draft.existing?.rawValue ==
                              draft.controller.text.trim()
                          ? draft.existing!.normalizedValue
                          : null,
                    ),
                  )
                  .toList(growable: false);
              Navigator.pop(
                dialogContext,
                CatalogProductDraft(
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
  for (final draft in unitDrafts) {
    draft.dispose();
  }
  return result;
}

class _CatalogUnitDraft {
  final String id;
  final CatalogUnit? existing;
  final TextEditingController controller;

  _CatalogUnitDraft({
    required this.id,
    required this.existing,
    required String rawValue,
  }) : controller = TextEditingController(text: rawValue);

  factory _CatalogUnitDraft.fromExisting(CatalogUnit unit) =>
      _CatalogUnitDraft(id: unit.id, existing: unit, rawValue: unit.rawValue);
  factory _CatalogUnitDraft.newPrimary() =>
      _CatalogUnitDraft(id: 'primary', existing: null, rawValue: '');
  factory _CatalogUnitDraft.newAdditional(String id) =>
      _CatalogUnitDraft(id: id, existing: null, rawValue: '');

  void dispose() => controller.dispose();
}

String _nextCatalogUnitId(Iterable<_CatalogUnitDraft> units) {
  final existing = units.map((unit) => unit.id).toSet();
  for (var index = 2; ; index++) {
    final candidate = 'unit_$index';
    if (!existing.contains(candidate)) return candidate;
  }
}
