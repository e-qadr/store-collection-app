import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/firestore_refresh.dart';

class BrandManagementScreen extends StatefulWidget {
  const BrandManagementScreen({super.key});

  @override
  State<BrandManagementScreen> createState() => _BrandManagementScreenState();
}

class _BrandManagementScreenState extends State<BrandManagementScreen> {
  final _nameController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveBrand({String? brandId}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _message('الرجاء إدخال اسم العلامة التجارية', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final duplicates = await firestore
          .collection('brands')
          .where('name', isEqualTo: name)
          .get();
      if (duplicates.docs.any((doc) => doc.id != brandId)) {
        throw Exception('هذه العلامة التجارية مسجلة مسبقاً');
      }

      final ref = brandId == null
          ? firestore.collection('brands').doc()
          : firestore.collection('brands').doc(brandId);
      await ref.set({
        'id': ref.id,
        'name': name,
        if (brandId == null) 'active': true,
        if (brandId == null) 'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
        _message(
          brandId == null
              ? 'تمت إضافة العلامة التجارية'
              : 'تم تحديث العلامة التجارية',
        );
      }
    } catch (error) {
      _message(error.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archiveBrand({
    required String brandId,
    required String brandName,
    required bool isActive,
  }) async {
    if (!isActive) {
      await FirebaseFirestore.instance
          .collection('brands')
          .doc(brandId)
          .update({
            'active': true,
            'reactivated_at': FieldValue.serverTimestamp(),
            'reactivated_by': FirebaseAuth.instance.currentUser?.uid ?? '',
            'updated_at': FieldValue.serverTimestamp(),
          });
      _message('تمت إعادة تفعيل العلامة التجارية');
      return;
    }

    final branches = await FirebaseFirestore.instance
        .collection('branches')
        .where('brand_id', isEqualTo: brandId)
        .limit(1)
        .get();
    final legacyBranches = await FirebaseFirestore.instance
        .collection('branches')
        .where('company_name', isEqualTo: brandName)
        .limit(1)
        .get();
    if (branches.docs.isNotEmpty || legacyBranches.docs.isNotEmpty) {
      _message(
        'لا يمكن حذف $brandName لأنها مرتبطة بفروع. غيّر علامة الفروع أولاً.',
        isError: true,
      );
      return;
    }

    if (!mounted) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('أرشفة العلامة التجارية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ستبقى $brandName محفوظة في السجل ولن تظهر في الاختيارات الجديدة.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'سبب الأرشفة',
                hintText: 'سبب واضح ومطلوب',
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
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () {
              if (reason.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سبب الأرشفة مطلوب.')),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('أرشفة'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection('brands').doc(brandId).update({
      'active': false,
      'archived_at': FieldValue.serverTimestamp(),
      'archived_by': FirebaseAuth.instance.currentUser?.uid ?? '',
      'archive_reason': reason.text.trim(),
      'updated_at': FieldValue.serverTimestamp(),
    });
    _message('تمت أرشفة العلامة التجارية');
  }

  void _showBrandDialog({String? brandId, String name = ''}) {
    _nameController.text = name;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.branding_watermark_rounded),
            const SizedBox(width: 10),
            Text(brandId == null ? 'علامة تجارية جديدة' : 'تعديل العلامة'),
          ],
        ),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'اسم العلامة التجارية',
            hintText: 'مثل: المتجر الأول',
            prefixIcon: Icon(Icons.business_rounded),
          ),
          onSubmitted: (_) {
            if (!_saving) _saveBrand(brandId: brandId);
          },
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : () => _saveBrand(brandId: brandId),
            icon: const Icon(Icons.save_rounded),
            label: Text(_saving ? 'جاري الحفظ...' : 'حفظ'),
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة العلامات التجارية'),
          backgroundColor: AppTheme.adminColor,
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppTheme.adminColor,
          foregroundColor: Colors.white,
          onPressed: () => _showBrandDialog(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('علامة جديدة'),
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              decoration: const BoxDecoration(
                color: AppTheme.adminColor,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(24),
                ),
              ),
              child: const Text(
                'أضف العلامات التجارية أولاً، ثم اربط كل فرع بعلامته من شاشة إدارة الفروع.',
                style: TextStyle(color: Colors.white, height: 1.5),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('brands')
                    .orderBy('name')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Center(
                      child: Text('تعذر تحميل العلامات التجارية'),
                    );
                  }
                  final brands = snapshot.data?.docs ?? [];
                  if (brands.isEmpty) {
                    return const _EmptyBrands();
                  }
                  return RefreshIndicator(
                    onRefresh: () => refreshFirestoreQueries([
                      FirebaseFirestore.instance.collection('brands'),
                    ]),
                    child: ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                      itemCount: brands.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final brand = brands[index];
                        final data = brand.data() as Map<String, dynamic>;
                        final name = data['name'] as String? ?? 'بدون اسم';
                        final isActive =
                            data['active'] != false &&
                            data['isActive'] != false &&
                            data['is_active'] != false;
                        return Container(
                          decoration: AppTheme.cardShadow(),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(14),
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFF3E5F5),
                              child: Icon(
                                Icons.business_rounded,
                                color: AppTheme.adminColor,
                              ),
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              isActive
                                  ? 'يمكن ربط عدة فروع بهذه العلامة التجارية'
                                  : 'مؤرشفة — لا تظهر في الاختيارات الجديدة',
                            ),
                            trailing: Wrap(
                              children: [
                                IconButton(
                                  tooltip: isActive ? 'تعديل' : 'عرض محفوظ',
                                  onPressed: isActive
                                      ? () => _showBrandDialog(
                                          brandId: brand.id,
                                          name: name,
                                        )
                                      : null,
                                  icon: const Icon(Icons.edit_rounded),
                                ),
                                IconButton(
                                  tooltip: isActive ? 'أرشفة' : 'إعادة تفعيل',
                                  onPressed: () => _archiveBrand(
                                    brandId: brand.id,
                                    brandName: name,
                                    isActive: isActive,
                                  ),
                                  icon: Icon(
                                    isActive
                                        ? Icons.archive_outlined
                                        : Icons.unarchive_outlined,
                                    color: isActive
                                        ? AppTheme.errorColor
                                        : AppTheme.successColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBrands extends StatelessWidget {
  const _EmptyBrands();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.branding_watermark_outlined,
              size: 64,
              color: AppTheme.textHint,
            ),
            SizedBox(height: 16),
            Text(
              'لا توجد علامات تجارية حتى الآن',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'استخدم زر «علامة جديدة» لإضافة أول علامة.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
