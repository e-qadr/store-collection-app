import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/models/product_catalog_model.dart';
import 'package:store_collection_app/services/product_catalog_service.dart';
import 'package:store_collection_app/services/purchase_invoice_api_service.dart';
import 'package:store_collection_app/theme/app_theme.dart';

/// A single catalog material belongs to a brand. Its accounting reference,
/// however, belongs to one branch ledger. This screen makes that distinction
/// visible instead of duplicating materials for every branch.
class ProductBranchAccountingScreen extends StatefulWidget {
  final UserRole role;
  final String branchId;
  final String branchName;

  const ProductBranchAccountingScreen({
    super.key,
    required this.role,
    required this.branchId,
    required this.branchName,
  });

  @override
  State<ProductBranchAccountingScreen> createState() =>
      _ProductBranchAccountingScreenState();
}

class _ProductBranchAccountingScreenState
    extends State<ProductBranchAccountingScreen> {
  final _catalog = ProductCatalogService();
  final _api = PurchaseInvoiceApiService();
  final Set<String> _saving = {};
  bool _pendingOnly = true;

  bool get _isAccountant => widget.role == UserRole.accountant;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(title: const Text('ربط المواد محاسبيًا')),
      body: widget.branchId.trim().isEmpty
          ? const _AccountingMessage(
              icon: Icons.storefront_outlined,
              text: 'اختر فرعًا أولًا لعرض مواد العلامة التجارية.',
            )
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .doc(widget.branchId)
                  .snapshots(),
              builder: (context, branchSnapshot) {
                if (branchSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final branch = branchSnapshot.data?.data();
                final brandId = branch?['brand_id']?.toString().trim() ?? '';
                if (branch == null || brandId.isEmpty) {
                  return const _AccountingMessage(
                    icon: Icons.error_outline_rounded,
                    text: 'تعذر تحديد العلامة التجارية لهذا الفرع.',
                  );
                }
                return _brandWorkspace(brandId);
              },
            ),
    ),
  );

  Widget _brandWorkspace(
    String brandId,
  ) => StreamBuilder<List<ProductCatalogModel>>(
    stream: _catalog.watchProducts(brandId: brandId, activeOnly: true),
    builder: (context, productSnapshot) {
      if (productSnapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (productSnapshot.hasError) {
        return const _AccountingMessage(
          icon: Icons.cloud_off_rounded,
          text: 'تعذر تحميل مواد الكتالوج.',
        );
      }
      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('branches')
            .where('brand_id', isEqualTo: brandId)
            .snapshots(),
        builder: (context, branchesSnapshot) {
          if (branchesSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (branchesSnapshot.hasError) {
            return const _AccountingMessage(
              icon: Icons.cloud_off_rounded,
              text: 'تعذر تحميل فروع العلامة التجارية.',
            );
          }
          final branches =
              (branchesSnapshot.data?.docs ?? const [])
                  .map(_BranchEntry.fromSnapshot)
                  .where((branch) => branch.isOperational)
                  .toList(growable: false)
                ..sort((left, right) => left.name.compareTo(right.name));
          return StreamBuilder<List<ProductAccountingProfile>>(
            stream: _catalog.watchBranchAccountingProfiles(brandId: brandId),
            builder: (context, profileSnapshot) {
              if (profileSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (profileSnapshot.hasError) {
                return const _AccountingMessage(
                  icon: Icons.cloud_off_rounded,
                  text: 'تعذر تحميل حالات الربط المحاسبي.',
                );
              }
              return _content(
                brandId: brandId,
                products: productSnapshot.data ?? const [],
                branches: branches,
                profiles: profileSnapshot.data ?? const [],
              );
            },
          );
        },
      );
    },
  );

  Widget _content({
    required String brandId,
    required List<ProductCatalogModel> products,
    required List<_BranchEntry> branches,
    required List<ProductAccountingProfile> profiles,
  }) {
    final profileByKey = {
      for (final profile in profiles)
        ProductAccountingProfile.documentIdFor(
          productId: profile.productId,
          branchId: profile.branchId,
        ): profile,
    };
    final focusedBranches = branches
        .where((branch) => branch.id == widget.branchId)
        .toList(growable: false);
    final focusBranch = focusedBranches.isEmpty ? null : focusedBranches.first;
    final visible = products
        .where((product) {
          if (!_pendingOnly) return true;
          if (_isAccountant) {
            return focusBranch != null &&
                !_isSynced(
                  _profileFor(profileByKey, product.id, focusBranch.id),
                );
          }
          return branches.any(
            (branch) =>
                !_isSynced(_profileFor(profileByKey, product.id, branch.id)),
          );
        })
        .toList(growable: false);
    final pendingForBranch = focusBranch == null
        ? 0
        : products
              .where(
                (product) => !_isSynced(
                  _profileFor(profileByKey, product.id, focusBranch.id),
                ),
              )
              .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _hero(branches.length, pendingForBranch),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                _isAccountant
                    ? 'مواد ${widget.branchName}'
                    : 'متابعة فروع العلامة التجارية',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            FilterChip(
              label: Text(_pendingOnly ? 'تحتاج ربطًا' : 'كل المواد'),
              selected: _pendingOnly,
              onSelected: (value) => setState(() => _pendingOnly = value),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          _emptyState()
        else
          ...visible.map(
            (product) => _productCard(
              product: product,
              brandId: brandId,
              branches: branches,
              profileByKey: profileByKey,
            ),
          ),
      ],
    );
  }

  Widget _hero(int branchCount, int pendingForBranch) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: _isAccountant
            ? AppTheme.accountantGradient.take(2).toList()
            : AppTheme.collectorGradient.take(2).toList(),
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            _isAccountant
                ? Icons.account_balance_rounded
                : Icons.visibility_rounded,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isAccountant
                    ? 'اربط مواد فرعك بالنظام المحاسبي'
                    : 'متابعة ربط المواد في الفروع',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isAccountant
                    ? '$pendingForBranch مواد بانتظار مرجعك المحاسبي.'
                    : 'المادة تُنشأ مرة واحدة وتظهر في $branchCount فروع للعلامة.',
                style: TextStyle(color: Colors.white.withValues(alpha: .86)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _productCard({
    required ProductCatalogModel product,
    required String brandId,
    required List<_BranchEntry> branches,
    required Map<String, ProductAccountingProfile> profileByKey,
  }) {
    final synchronizedCount = branches
        .where(
          (branch) =>
              _isSynced(_profileFor(profileByKey, product.id, branch.id)),
        )
        .length;
    final focusedProfile = _profileFor(
      profileByKey,
      product.id,
      widget.branchId,
    );
    final canSyncHere = _isAccountant && !_isSynced(focusedProfile);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppTheme.oliveSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.inventory_2_rounded,
                    color: AppTheme.primaryOlive,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  '$synchronizedCount/${branches.length}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              'الكتالوج موحّد للعلامة. علامة الصح تعني أن محاسب الفرع أدخل مرجع المادة.',
              style: const TextStyle(color: AppTheme.textHint, fontSize: 12),
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: branches
                  .map(
                    (branch) => _branchChip(
                      branch,
                      _profileFor(profileByKey, product.id, branch.id),
                    ),
                  )
                  .toList(growable: false),
            ),
            if (canSyncHere) ...[
              const Divider(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving.contains(product.id)
                      ? null
                      : () => _syncBranch(product: product, brandId: brandId),
                  icon: _saving.contains(product.id)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded),
                  label: Text('ربط ${widget.branchName} محاسبيًا'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _branchChip(_BranchEntry branch, ProductAccountingProfile? profile) {
    final synced = _isSynced(profile);
    final focused = branch.id == widget.branchId;
    final color = synced ? AppTheme.successColor : AppTheme.warningColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: focused ? .15 : .08),
        borderRadius: BorderRadius.circular(10),
        border: focused
            ? Border.all(color: color.withValues(alpha: .42))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            synced ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            branch.name,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: focused ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Card(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        children: [
          const Icon(
            Icons.task_alt_rounded,
            color: AppTheme.successColor,
            size: 48,
          ),
          const SizedBox(height: 10),
          Text(
            _pendingOnly
                ? 'لا توجد مواد تحتاج ربطًا الآن'
                : 'لا توجد مواد في الكتالوج',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    ),
  );

  Future<void> _syncBranch({
    required ProductCatalogModel product,
    required String brandId,
  }) async {
    final reference = TextEditingController();
    final notes = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('ربط ${product.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'سيسجّل هذا المرجع لفرع ${widget.branchName} فقط.',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reference,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'مرجع المادة في النظام المحاسبي *',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حفظ الربط'),
          ),
        ],
      ),
    );
    final cleanReference = reference.text.trim();
    final cleanNotes = notes.text.trim();
    reference.dispose();
    notes.dispose();
    if (accepted != true || cleanReference.isEmpty) {
      if (accepted == true && mounted) {
        _message('المرجع المحاسبي مطلوب.');
      }
      return;
    }
    setState(() => _saving.add(product.id));
    try {
      await _api.syncProductForBranchAccounting(
        productId: product.id,
        branchId: widget.branchId,
        accountingReference: cleanReference,
        notes: cleanNotes,
        idempotencyKey: PurchaseInvoiceApiService.generateIdempotencyKey(),
      );
      if (mounted) _message('تم ربط المادة محاسبيًا لهذا الفرع.');
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => _saving.remove(product.id));
    }
  }

  ProductAccountingProfile? _profileFor(
    Map<String, ProductAccountingProfile> profiles,
    String productId,
    String branchId,
  ) =>
      profiles[ProductAccountingProfile.documentIdFor(
        productId: productId,
        branchId: branchId,
      )];

  bool _isSynced(ProductAccountingProfile? profile) =>
      profile?.syncState == 'synced' &&
      (profile?.accountingReference?.trim().isNotEmpty ?? false);

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _BranchEntry {
  final String id;
  final String name;
  final bool isOperational;

  const _BranchEntry({
    required this.id,
    required this.name,
    required this.isOperational,
  });

  factory _BranchEntry.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) => _BranchEntry(
    id: doc.id,
    name: doc.data()?['name']?.toString().trim().isNotEmpty == true
        ? doc.data()!['name'].toString().trim()
        : doc.id,
    isOperational: doc.data()?['branch_type']?.toString() != 'main',
  );
}

class _AccountingMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _AccountingMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
