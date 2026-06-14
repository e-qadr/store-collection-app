import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:store_collection_app/screens/admin/branch_management_screen.dart';
import 'package:store_collection_app/theme/app_theme.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String _selectedRole = 'collector';
  String? _selectedBranchId;

  final List<String> _roles = ['collector', 'manager', 'accountant'];

  // 1. الإضافة (Create)
  Future<void> _createNewUser() async {
    if (_emailController.text.isEmpty ||
        _passwordController.text.isEmpty ||
        _nameController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('الرجاء تعبئة جميع الحقول')));
      return;
    }

    if (_selectedRole == 'manager' && _selectedBranchId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('الرجاء اختيار فرع للمدير')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      FirebaseApp tempApp = await Firebase.initializeApp(
        name: 'TemporaryRegisterApp',
        options: Firebase.app().options,
      );

      UserCredential userCredential =
          await FirebaseAuth.instanceFor(
            app: tempApp,
          ).createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      if (userCredential.user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
              'uid': userCredential.user!.uid,
              'name': _nameController.text.trim(),
              'email': _emailController.text.trim(),
              'role': _selectedRole,
              'branchId': _selectedRole == 'manager' ? _selectedBranchId : null,
              'createdAt': FieldValue.serverTimestamp(),
              'isActive': true,
            });
      }

      await tempApp.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنشاء الحساب بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
        _nameController.clear();
        _emailController.clear();
        _passwordController.clear();
        setState(() {
          _selectedBranchId = null;
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'خطأ أثناء الإنشاء'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 2. تحديث الدور
  Future<void> _updateUserRole(String uid, String newRole) async {
    Map<String, dynamic> updates = {'role': newRole};

    if (newRole != 'manager') {
      updates['branchId'] = FieldValue.delete();
    }

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update(updates);
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث الصلاحية بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
  }

  // 3. الإيقاف والتفعيل
  Future<void> _toggleUserStatus(String uid, bool currentStatus) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'isActive': !currentStatus,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!currentStatus ? 'تم تفعيل الحساب' : 'تم إيقاف الحساب'),
          backgroundColor: !currentStatus ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  // 4. نافذة تعديل الفرع (نقل الموظف)
  Future<void> _showAssignBranchDialog(
    String uid,
    String currentBranchId,
  ) async {
    String? newBranchId = currentBranchId.isEmpty ? null : currentBranchId;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Row(
                children: [
                  Icon(Icons.swap_horiz_rounded, color: AppTheme.adminColor),
                  SizedBox(width: 8),
                  Text(
                    'تعيين / نقل لفرع آخر',
                    style: TextStyle(color: AppTheme.adminColor, fontSize: 18),
                  ),
                ],
              ),
              content: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('branches')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return const SizedBox(
                      height: 100,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.adminColor,
                        ),
                      ),
                    );

                  final branches = snapshot.data!.docs;

                  if (newBranchId != null &&
                      !branches.any((b) => b.id == newBranchId)) {
                    newBranchId = null;
                  }

                  return InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'اختر الفرع',
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
                        value: newBranchId,
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('بدون فرع (إزالة)'),
                          ),
                          ...branches.map((branch) {
                            return DropdownMenuItem(
                              value: branch.id,
                              child: Text(branch['name']),
                            );
                          }),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => newBranchId = value),
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
                    if (newBranchId == null) {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({'branchId': FieldValue.delete()});
                    } else {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .update({'branchId': newBranchId});
                    }
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم تحديث الفرع بنجاح'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.save_rounded, size: 18),
                  label: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
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
            'إدارة المستخدمين',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: AppTheme.adminColor,
          elevation: 0,
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppTheme.adminColor.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ExpansionTile(
                title: const Text(
                  'إضافة مستخدم جديد',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.adminColor,
                  ),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.adminColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_add_rounded,
                    color: AppTheme.adminColor,
                  ),
                ),
                shape: const Border(),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'اسم الموظف',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            prefixIcon: Icon(Icons.person_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            prefixIcon: Icon(Icons.email_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'كلمة المرور',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            prefixIcon: Icon(Icons.lock_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'الصلاحية (الدور)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(12),
                              ),
                            ),
                            prefixIcon: Icon(
                              Icons.admin_panel_settings_rounded,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedRole,
                              isExpanded: true,
                              items: _roles
                                  .map(
                                    (role) => DropdownMenuItem(
                                      value: role,
                                      child: Text(
                                        role == 'manager'
                                            ? 'مدير فرع'
                                            : role == 'accountant'
                                            ? 'محاسب'
                                            : 'محصل',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() {
                                _selectedRole = value!;
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (_selectedRole == 'manager')
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('branches')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData)
                                return const LinearProgressIndicator(
                                  color: AppTheme.adminColor,
                                );

                              if (_selectedBranchId != null &&
                                  !snapshot.data!.docs.any(
                                    (b) => b.id == _selectedBranchId,
                                  )) {
                                _selectedBranchId = null;
                              }

                              return Row(
                                children: [
                                  Expanded(
                                    child: InputDecorator(
                                      decoration: const InputDecoration(
                                        labelText: 'تعيين فرع للمدير',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.all(
                                            Radius.circular(12),
                                          ),
                                        ),
                                        prefixIcon: Icon(Icons.store_rounded),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: _selectedBranchId,
                                          isExpanded: true,
                                          items: snapshot.data!.docs
                                              .map(
                                                (branch) => DropdownMenuItem(
                                                  value: branch.id,
                                                  child: Text(branch['name']),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) => setState(() {
                                            _selectedBranchId = value;
                                          }),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: AppTheme.adminColor.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.add_business_rounded,
                                        color: AppTheme.adminColor,
                                      ),
                                      tooltip: 'إنشاء فرع جديد',
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const BranchManagementScreen(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),

                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.adminColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isLoading ? null : _createNewUser,
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.person_add_rounded),
                          label: const Text(
                            'إنشاء الحساب',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.adminColor,
                      ),
                    );
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.group_off_rounded,
                            size: 64,
                            color: AppTheme.textHint.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا يوجد مستخدمين مسجلين',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final users = snapshot.data!.docs;

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final doc = users[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final isActive = data['isActive'] ?? true;
                      final role = data['role'] ?? 'غير محدد';
                      final branchId = data['branchId'] ?? '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.cardColor
                              : Colors.red.shade50.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isActive
                                ? Colors.grey.withValues(alpha: 0.2)
                                : Colors.red.withValues(alpha: 0.3),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {},
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppTheme.adminColor.withValues(
                                              alpha: 0.1,
                                            )
                                          : Colors.red.withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.person_rounded,
                                      color: isActive
                                          ? AppTheme.adminColor
                                          : Colors.red,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data['name'] ?? 'بدون اسم',
                                          style: TextStyle(
                                            decoration: isActive
                                                ? TextDecoration.none
                                                : TextDecoration.lineThrough,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: isActive
                                                ? AppTheme.textPrimary
                                                : Colors.red.shade900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          data['email'] ?? '',
                                          style: const TextStyle(
                                            color: AppTheme.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                role == 'manager'
                                                    ? 'مدير فرع'
                                                    : role == 'accountant'
                                                    ? 'محاسب'
                                                    : 'محصل',
                                                style: const TextStyle(
                                                  color: Colors.blue,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (role == 'manager' &&
                                                branchId.isNotEmpty) ...[
                                              const SizedBox(width: 8),
                                              FutureBuilder<DocumentSnapshot>(
                                                future: FirebaseFirestore
                                                    .instance
                                                    .collection('branches')
                                                    .doc(branchId)
                                                    .get(),
                                                builder: (context, branchSnapshot) {
                                                  if (!branchSnapshot.hasData)
                                                    return const SizedBox.shrink();
                                                  final branchName =
                                                      (branchSnapshot.data
                                                              ?.data()
                                                          as Map<
                                                            String,
                                                            dynamic
                                                          >?)?['name'] ??
                                                      'فرع محذوف';
                                                  return Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.teal
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      branchName,
                                                      style: const TextStyle(
                                                        color: Colors.teal,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.more_vert_rounded,
                                      color: AppTheme.textHint,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    onSelected: (value) {
                                      if (value == 'toggle') {
                                        _toggleUserStatus(doc.id, isActive);
                                      } else if (value == 'edit_branch') {
                                        _showAssignBranchDialog(
                                          doc.id,
                                          branchId,
                                        );
                                      } else {
                                        _updateUserRole(doc.id, value);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      if (role != 'manager')
                                        const PopupMenuItem(
                                          value: 'manager',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.admin_panel_settings,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('ترقية لمدير فرع'),
                                            ],
                                          ),
                                        ),
                                      if (role != 'collector')
                                        const PopupMenuItem(
                                          value: 'collector',
                                          child: Row(
                                            children: [
                                              Icon(Icons.motorcycle, size: 18),
                                              SizedBox(width: 8),
                                              Text('تغيير لمحصل'),
                                            ],
                                          ),
                                        ),
                                      if (role != 'accountant')
                                        const PopupMenuItem(
                                          value: 'accountant',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.account_balance_wallet,
                                                size: 18,
                                              ),
                                              SizedBox(width: 8),
                                              Text('تغيير لمحاسب'),
                                            ],
                                          ),
                                        ),
                                      const PopupMenuDivider(),
                                      if (role == 'manager')
                                        const PopupMenuItem(
                                          value: 'edit_branch',
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.swap_horiz,
                                                size: 18,
                                                color: Colors.blue,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'نقل/تعيين فرع',
                                                style: TextStyle(
                                                  color: Colors.blue,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      PopupMenuItem(
                                        value: 'toggle',
                                        child: Row(
                                          children: [
                                            Icon(
                                              isActive
                                                  ? Icons.block
                                                  : Icons.check_circle_outline,
                                              size: 18,
                                              color: isActive
                                                  ? Colors.red
                                                  : Colors.green,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              isActive
                                                  ? 'إيقاف الحساب'
                                                  : 'تفعيل الحساب',
                                              style: TextStyle(
                                                color: isActive
                                                    ? Colors.red
                                                    : Colors.green,
                                              ),
                                            ),
                                          ],
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
