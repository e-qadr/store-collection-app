import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/firestore_refresh.dart';

class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> {
  final TextEditingController _branchNameController = TextEditingController();
  final TextEditingController _branchCodeController = TextEditingController();
  String? _selectedBrandId;
  String? _selectedBrandName;

  Future<void> _saveBranch({
    String? branchId,
    String managerId = '',
    String oldBranchCode = '',
  }) async {
    final name = _branchNameController.text.trim();
    final branchCode = _branchCodeController.text.trim().toUpperCase();

    if (name.isEmpty ||
        _selectedBrandId == null ||
        _selectedBrandName == null ||
        branchCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء اختيار العلامة وإدخال اسم الفرع ورمزه'),
        ),
      );
      return;
    }
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(branchCode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رمز الفرع يجب أن يحتوي على حروف إنجليزية وأرقام فقط'),
        ),
      );
      return;
    }

    final firestore = FirebaseFirestore.instance;
    final branchRef = branchId == null
        ? firestore.collection('branches').doc()
        : firestore.collection('branches').doc(branchId);
    final newCodeRef = firestore.collection('branch_codes').doc(branchCode);

    try {
      final duplicateBranches = await firestore
          .collection('branches')
          .where('branch_code', isEqualTo: branchCode)
          .get();
      if (duplicateBranches.docs.any((doc) => doc.id != branchRef.id)) {
        throw Exception('رمز الفرع مستخدم لفرع آخر');
      }

      await firestore.runTransaction((transaction) async {
        final newCodeDoc = await transaction.get(newCodeRef);
        if (newCodeDoc.exists &&
            newCodeDoc.data()?['branch_id'] != branchRef.id) {
          throw Exception('رمز الفرع مستخدم لفرع آخر');
        }

        transaction.set(branchRef, {
          'id': branchRef.id,
          'name': name,
          'brand_id': _selectedBrandId,
          'company_name': _selectedBrandName,
          'branch_code': branchCode,
          'branch_manager_id': managerId,
        }, SetOptions(merge: true));
        transaction.set(newCodeRef, {
          'branch_id': branchRef.id,
          'branch_name': name,
        });
        if (oldBranchCode.isNotEmpty && oldBranchCode != branchCode) {
          transaction.delete(
            firestore.collection('branch_codes').doc(oldBranchCode),
          );
        }
      });

      _branchNameController.clear();
      _branchCodeController.clear();
      _selectedBrandId = null;
      _selectedBrandName = null;
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              branchId == null
                  ? 'تمت إضافة الفرع بنجاح'
                  : 'تم تحديث بيانات الفرع بنجاح',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // حذف فرع
  Future<void> _deleteBranch(String branchId, String branchCode) async {
    final screenContext = context;

    // تأكيد الحذف
    await showDialog(
      context: screenContext,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text(
              'تأكيد الحذف',
              style: TextStyle(color: Colors.red, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'هل أنت متأكد من حذف هذا الفرع؟',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final firestore = FirebaseFirestore.instance;
              final batch = firestore.batch();
              batch.delete(firestore.collection('branches').doc(branchId));
              if (branchCode.isNotEmpty) {
                batch.delete(
                  firestore.collection('branch_codes').doc(branchCode),
                );
              }
              await batch.commit();
              if (screenContext.mounted) {
                ScaffoldMessenger.of(screenContext).showSnackBar(
                  const SnackBar(
                    content: Text('تم حذف الفرع'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            icon: const Icon(Icons.delete_rounded, size: 18),
            label: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  // نافذة تعيين مدير للفرع
  Future<void> _showAssignManagerDialog(
    String branchId,
    String currentManagerId,
  ) async {
    String? selectedManagerId = currentManagerId.isEmpty
        ? null
        : currentManagerId;
    final screenContext = context;

    await showDialog(
      context: screenContext,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(
                    Icons.manage_accounts_rounded,
                    color: AppTheme.adminColor,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'تعيين مدير للفرع',
                    style: TextStyle(color: AppTheme.adminColor, fontSize: 18),
                  ),
                ],
              ),
              content: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('role', isEqualTo: 'manager')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 100,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.adminColor,
                        ),
                      ),
                    );
                  }

                  final managers = snapshot.data!.docs;
                  if (managers.isEmpty) {
                    return const Text(
                      'لا يوجد مدراء مسجلين في النظام. أضف مديراً أولاً.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    );
                  }

                  // تأكد من أن الـ selectedManagerId لا يزال موجوداً في القائمة إذا لم يكن null
                  if (selectedManagerId != null &&
                      !managers.any((m) => m.id == selectedManagerId)) {
                    selectedManagerId = null;
                  }

                  return InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'اختر المدير',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedManagerId,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('بدون مدير (إزالة)'),
                          ),
                          ...managers.map((manager) {
                            final data = manager.data() as Map<String, dynamic>;
                            return DropdownMenuItem(
                              value: manager.id,
                              child: Text(data['name'] ?? 'بدون اسم'),
                            );
                          }),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => selectedManagerId = value),
                      ),
                    ),
                  );
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.adminColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    WriteBatch batch = FirebaseFirestore.instance.batch();
                    DocumentReference branchRef = FirebaseFirestore.instance
                        .collection('branches')
                        .doc(branchId);

                    if (selectedManagerId == null) {
                      batch.update(branchRef, {'branch_manager_id': ''});
                      if (currentManagerId.isNotEmpty) {
                        DocumentReference oldManagerRef = FirebaseFirestore
                            .instance
                            .collection('users')
                            .doc(currentManagerId);
                        batch.update(oldManagerRef, {
                          'branchId': FieldValue.delete(),
                        });
                      }
                    } else {
                      batch.update(branchRef, {
                        'branch_manager_id': selectedManagerId,
                      });
                      DocumentReference newManagerRef = FirebaseFirestore
                          .instance
                          .collection('users')
                          .doc(selectedManagerId);
                      batch.update(newManagerRef, {'branchId': branchId});
                    }

                    await batch.commit();

                    if (screenContext.mounted) {
                      Navigator.pop(screenContext);
                      ScaffoldMessenger.of(screenContext).showSnackBar(
                        const SnackBar(
                          content: Text('تم تحديث إدارة الفرع'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('حفظ التعيين'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // نافذة إضافة فرع
  void _showAddBranchDialog() {
    _branchNameController.clear();
    _branchCodeController.clear();
    _selectedBrandId = null;
    _selectedBrandName = null;
    _showBranchDialog();
  }

  void _showEditBranchDialog(String branchId, Map<String, dynamic> data) {
    _branchNameController.text = data['name'] ?? '';
    _branchCodeController.text = data['branch_code'] ?? '';
    _selectedBrandId = data['brand_id'];
    _selectedBrandName = data['company_name'];
    _showBranchDialog(
      branchId: branchId,
      managerId: data['branch_manager_id'] ?? '',
      oldBranchCode: data['branch_code'] ?? '',
    );
  }

  void _showBranchDialog({
    String? branchId,
    String managerId = '',
    String oldBranchCode = '',
  }) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.store_rounded, color: AppTheme.adminColor),
              SizedBox(width: 8),
              Text('بيانات الفرع'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('brands')
                      .orderBy('name')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final brands = snapshot.data?.docs ?? [];
                    final selectedExists = brands.any(
                      (brand) => brand.id == _selectedBrandId,
                    );
                    return DropdownButtonFormField<String>(
                      initialValue: selectedExists ? _selectedBrandId : null,
                      decoration: const InputDecoration(
                        labelText: 'العلامة التجارية',
                        prefixIcon: Icon(Icons.business_rounded),
                      ),
                      hint: Text(
                        snapshot.connectionState == ConnectionState.waiting
                            ? 'جاري تحميل العلامات...'
                            : brands.isEmpty
                            ? 'أضف علامة تجارية أولاً'
                            : 'اختر العلامة التجارية',
                      ),
                      items: brands.map((brand) {
                        final data = brand.data() as Map<String, dynamic>;
                        return DropdownMenuItem(
                          value: brand.id,
                          child: Text(data['name'] ?? 'بدون اسم'),
                        );
                      }).toList(),
                      onChanged: brands.isEmpty
                          ? null
                          : (value) {
                              final selected = brands.firstWhere(
                                (brand) => brand.id == value,
                              );
                              final data =
                                  selected.data() as Map<String, dynamic>;
                              setDialogState(() {
                                _selectedBrandId = value;
                                _selectedBrandName = data['name'];
                              });
                            },
                    );
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _branchNameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الفرع',
                    hintText: 'مثل: فرع سيئون',
                    prefixIcon: Icon(Icons.storefront_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _branchCodeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'رمز الفرع الفريد',
                    hintText: 'مثل: AM',
                    helperText: 'سيُستخدم في أرقام السندات مثل AM005',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => _saveBranch(
                branchId: branchId,
                managerId: managerId,
                oldBranchCode: oldBranchCode,
              ),
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('حفظ بيانات الفرع'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: const Text(
            'إدارة الفروع',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: AppTheme.adminColor,
          elevation: 0,
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddBranchDialog,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text(
            'فرع جديد',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppTheme.adminColor,
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              decoration: const BoxDecoration(
                color: AppTheme.adminColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              child: const Text(
                'اختر العلامة التجارية، ثم أضف اسم الفرع ورمزه الفريد وعيّن مديره.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('branches')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.adminColor,
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 64,
                            color: AppTheme.textHint.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا توجد فروع مسجلة حتى الآن',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final branches = snapshot.data!.docs;

                  return RefreshIndicator(
                    onRefresh: () => refreshFirestoreQueries([
                      FirebaseFirestore.instance.collection('branches'),
                    ]),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: branches.length,
                      itemBuilder: (context, index) {
                        final doc = branches[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final managerId = data['branch_manager_id'] ?? '';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: AppTheme.cardShadow(),
                          child: Material(
                            color: AppTheme.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () =>
                                  _showAssignManagerDialog(doc.id, managerId),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: AppTheme.adminColor.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.store_rounded,
                                        color: AppTheme.adminColor,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            data['name'] ?? 'فرع غير مسمى',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${data['company_name'] ?? 'بدون شركة'} • الرمز: ${data['branch_code'] ?? 'غير محدد'}',
                                            style: const TextStyle(
                                              color: AppTheme.textSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          managerId.isEmpty
                                              ? const Text(
                                                  'لم يتم تعيين مدير للفرع',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                )
                                              : FutureBuilder<DocumentSnapshot>(
                                                  future: FirebaseFirestore
                                                      .instance
                                                      .collection('users')
                                                      .doc(managerId)
                                                      .get(),
                                                  builder: (context, userSnapshot) {
                                                    if (!userSnapshot.hasData) {
                                                      return const Text(
                                                        'جاري جلب المدير...',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              AppTheme.textHint,
                                                        ),
                                                      );
                                                    }
                                                    if (!userSnapshot
                                                        .data!
                                                        .exists) {
                                                      return const Text(
                                                        'المدير محذوف من النظام',
                                                        style: TextStyle(
                                                          color: Colors.red,
                                                          fontSize: 12,
                                                        ),
                                                      );
                                                    }
                                                    final managerName =
                                                        (userSnapshot.data!
                                                                .data()
                                                            as Map<
                                                              String,
                                                              dynamic
                                                            >?)?['name'] ??
                                                        'مجهول';
                                                    return Text(
                                                      'المدير: $managerName',
                                                      style: const TextStyle(
                                                        color: Colors.green,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    );
                                                  },
                                                ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit_rounded,
                                            color: Colors.orange,
                                          ),
                                          tooltip: 'تعديل بيانات الفرع',
                                          onPressed: () =>
                                              _showEditBranchDialog(
                                                doc.id,
                                                data,
                                              ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.manage_accounts_rounded,
                                            color: AppTheme.adminColor,
                                          ),
                                          tooltip: 'تعيين مدير',
                                          onPressed: () =>
                                              _showAssignManagerDialog(
                                                doc.id,
                                                managerId,
                                              ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.red.shade400,
                                          ),
                                          onPressed: () => _deleteBranch(
                                            doc.id,
                                            data['branch_code'] ?? '',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
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
