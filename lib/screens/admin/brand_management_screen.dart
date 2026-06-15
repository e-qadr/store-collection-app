import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';

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

  Future<void> _deleteBrand(String brandId, String brandName) async {
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف العلامة التجارية'),
        content: Text('هل تريد حذف $brandName؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection('brands').doc(brandId).delete();
    _message('تم حذف العلامة التجارية');
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
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                    itemCount: brands.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final brand = brands[index];
                      final data = brand.data() as Map<String, dynamic>;
                      final name = data['name'] as String? ?? 'بدون اسم';
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
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            'يمكن ربط عدة فروع بهذه العلامة التجارية',
                          ),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'تعديل',
                                onPressed: () => _showBrandDialog(
                                  brandId: brand.id,
                                  name: name,
                                ),
                                icon: const Icon(Icons.edit_rounded),
                              ),
                              IconButton(
                                tooltip: 'حذف',
                                onPressed: () => _deleteBrand(brand.id, name),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppTheme.errorColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
