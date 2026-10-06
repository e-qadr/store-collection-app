import 'package:flutter/material.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/catalog_normalization.dart';

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

typedef CatalogGroupCreator = Future<ProductGroupModel?> Function(String name);

Future<CatalogProductDraft?> showCatalogProductEditor(
  BuildContext context, {
  ProductCatalogModel? product,
  required List<ProductGroupModel> groups,
  String initialName = '',
  String initialPrimaryUnit = '',
  List<CatalogUnit> initialUnits = const [],
  CatalogGroupCreator? onCreateGroup,
}) async {
  final activeGroups = groups.where((group) => group.active).toList();
  if (product != null &&
      !activeGroups.any((group) => group.id == product.groupId)) {
    final current = groups.where((group) => group.id == product.groupId);
    if (current.isNotEmpty) activeGroups.add(current.first);
  }
  final nameController = TextEditingController(
    text: product?.name ?? initialName,
  );
  final codeController = TextEditingController(text: product?.legacyCode ?? '');
  final originalUnits = product == null
      ? initialUnits
      : [
          if (product.unitById(product.primaryUnitId) != null)
            product.unitById(product.primaryUnitId)!,
          ...product.units.where((unit) => unit.id != product.primaryUnitId),
        ];
  final unitDrafts = originalUnits
      .map(_CatalogUnitDraft.fromExisting)
      .toList(growable: true);
  if (unitDrafts.isEmpty) {
    unitDrafts.add(_CatalogUnitDraft.newPrimary(initialPrimaryUnit));
  }
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
        title: Text(
          product == null ? 'إنشاء مادة جديدة في الكتالوج' : 'تعديل المادة',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _CatalogGroupField(
                  group: _groupForId(activeGroups, groupId),
                  onPressed: () async {
                    final selected = await _showCatalogGroupPicker(
                      context,
                      groups: activeGroups,
                      selectedGroupId: groupId,
                      onCreateGroup: onCreateGroup,
                    );
                    if (selected == null) return;
                    setDialogState(() {
                      if (!activeGroups.any(
                        (group) => group.id == selected.id,
                      )) {
                        activeGroups.add(selected);
                      }
                      groupId = selected.id;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المادة أو المنتج *',
                    helperText: 'استخدم الاسم الذي سيظهر لجميع الفروع.',
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: index == 0
                            ? AppTheme.oliveSurface
                            : AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.textHint),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: draft.controller,
                                  decoration: InputDecoration(
                                    labelText: index == 0
                                        ? 'الوحدة الأساسية *'
                                        : 'اسم الوحدة ${index + 1} *',
                                    helperText: index == 0
                                        ? 'تمثل وحدة واحدة دائماً.'
                                        : 'مثل: كرتون أو باكيت أو صندوق.',
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
                          if (index > 0) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: draft.factorController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'تعادل كم وحدة أساسية؟ *',
                                helperText:
                                    'مثال: كرتون فيه 12 ${unitDrafts.first.controller.text.trim().isEmpty ? 'وحدة' : unitDrafts.first.controller.text.trim()}، اكتب 12.',
                                prefixIcon: const Icon(
                                  Icons.swap_horiz_rounded,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
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
                      label: const Text('إضافة وحدة أخرى'),
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
                    'الوحدة الأساسية هي المرجع. مثال: كرتون يحتوي 12 حبة، أضف «كرتون» واكتب 12. لا تُحفظ الأسعار هنا.',
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
              final invalidFactor = unitDrafts.skip(1).any((draft) {
                final factor = double.tryParse(
                  draft.factorController.text.trim(),
                );
                return draft.controller.text.trim().isNotEmpty &&
                    (factor == null || !factor.isFinite || factor <= 0);
              });
              if (invalidFactor) {
                setDialogState(() {
                  validationError = 'أدخل معامل تحويل موجباً لكل وحدة إضافية.';
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
                      baseUnitFactor: draft == unitDrafts.first
                          ? 1
                          : double.parse(draft.factorController.text.trim()),
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
  final TextEditingController factorController;

  _CatalogUnitDraft({
    required this.id,
    required this.existing,
    required String rawValue,
    required double baseUnitFactor,
  }) : controller = TextEditingController(text: rawValue),
       factorController = TextEditingController(
         text: baseUnitFactor == baseUnitFactor.roundToDouble()
             ? baseUnitFactor.toInt().toString()
             : baseUnitFactor.toString(),
       );

  factory _CatalogUnitDraft.fromExisting(CatalogUnit unit) => _CatalogUnitDraft(
    id: unit.id,
    existing: unit,
    rawValue: unit.rawValue,
    baseUnitFactor: unit.baseUnitFactor,
  );
  factory _CatalogUnitDraft.newPrimary([String rawValue = '']) =>
      _CatalogUnitDraft(
        id: 'primary',
        existing: null,
        rawValue: rawValue,
        baseUnitFactor: 1,
      );
  factory _CatalogUnitDraft.newAdditional(String id) => _CatalogUnitDraft(
    id: id,
    existing: null,
    rawValue: '',
    baseUnitFactor: 1,
  );

  void dispose() {
    controller.dispose();
    factorController.dispose();
  }
}

String _nextCatalogUnitId(Iterable<_CatalogUnitDraft> units) {
  final existing = units.map((unit) => unit.id).toSet();
  for (var index = 2; ; index++) {
    final candidate = 'unit_$index';
    if (!existing.contains(candidate)) return candidate;
  }
}

ProductGroupModel? _groupForId(Iterable<ProductGroupModel> groups, String? id) {
  for (final group in groups) {
    if (group.id == id) return group;
  }
  return null;
}

class _CatalogGroupField extends StatelessWidget {
  final ProductGroupModel? group;
  final VoidCallback onPressed;

  const _CatalogGroupField({required this.group, required this.onPressed});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: const InputDecoration(
        labelText: 'المجموعة *',
        helperText: 'اضغط للبحث أو لإنشاء مجموعة.',
        suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
      ),
      child: Text(
        group?.name ?? 'اختر المجموعة',
        style: TextStyle(
          color: group == null ? AppTheme.textHint : AppTheme.textPrimary,
        ),
      ),
    ),
  );
}

Future<ProductGroupModel?> _showCatalogGroupPicker(
  BuildContext context, {
  required List<ProductGroupModel> groups,
  required String? selectedGroupId,
  CatalogGroupCreator? onCreateGroup,
}) async {
  final search = TextEditingController();
  String query = '';
  bool creating = false;
  final result = await showModalBottomSheet<ProductGroupModel>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          final normalized = normalizeCatalogText(query);
          final matches = groups
              .where((group) {
                final name = group.normalizedName.isEmpty
                    ? normalizeCatalogText(group.name)
                    : group.normalizedName;
                return normalized.isEmpty || name.contains(normalized);
              })
              .toList(growable: false);
          matches.sort((left, right) {
            int rank(ProductGroupModel group) {
              final name = group.normalizedName.isEmpty
                  ? normalizeCatalogText(group.name)
                  : group.normalizedName;
              if (name == normalized) return 0;
              if (name.startsWith(normalized)) return 1;
              return 2;
            }

            final rankComparison = rank(left).compareTo(rank(right));
            return rankComparison != 0
                ? rankComparison
                : left.name.compareTo(right.name);
          });
          final hasExactMatch = matches.any(
            (group) => normalizeCatalogText(group.name) == normalized,
          );
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .7,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.textHint,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'اختيار مجموعة',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: search,
                      autofocus: true,
                      onChanged: (value) => setSheetState(() => query = value),
                      decoration: const InputDecoration(
                        labelText: 'ابحث باسم المجموعة',
                        hintText: 'بحث مطابق، ثم بادئ، ثم يحتوي',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  if (onCreateGroup != null &&
                      query.trim().isNotEmpty &&
                      !hasExactMatch)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: FilledButton.tonalIcon(
                        onPressed: creating
                            ? null
                            : () async {
                                setSheetState(() => creating = true);
                                try {
                                  final group = await onCreateGroup(
                                    query.trim(),
                                  );
                                  if (context.mounted && group != null) {
                                    Navigator.pop(context, group);
                                  }
                                } catch (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'تعذر إنشاء المجموعة. تحقق من الاسم وحاول مرة أخرى.',
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (context.mounted) {
                                    setSheetState(() => creating = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: Text('إنشاء مجموعة «${query.trim()}»'),
                      ),
                    ),
                  Expanded(
                    child: matches.isEmpty
                        ? const Center(child: Text('لا توجد مجموعة مطابقة.'))
                        : ListView.separated(
                            itemCount: matches.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final group = matches[index];
                              final selected = group.id == selectedGroupId;
                              return ListTile(
                                leading: Icon(
                                  selected
                                      ? Icons.check_circle_rounded
                                      : Icons.folder_outlined,
                                  color: selected
                                      ? AppTheme.primaryOlive
                                      : AppTheme.darkOlive,
                                ),
                                title: Text(group.name),
                                subtitle: group.legacyCode == null
                                    ? null
                                    : Text(group.legacyCode!),
                                onTap: () => Navigator.pop(context, group),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  search.dispose();
  return result;
}
