import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';
import 'package:store_collection_app/utils/firestore_refresh.dart';

class CompanyBranchSelector extends StatefulWidget {
  final String title;
  final String intro;
  final Color color;
  final IconData branchIcon;
  final void Function(BuildContext context, QueryDocumentSnapshot branch)
  onBranchSelected;

  const CompanyBranchSelector({
    super.key,
    required this.title,
    required this.intro,
    required this.color,
    required this.branchIcon,
    required this.onBranchSelected,
  });

  @override
  State<CompanyBranchSelector> createState() => _CompanyBranchSelectorState();
}

class _CompanyBranchSelectorState extends State<CompanyBranchSelector> {
  String? _selectedBrandId;
  String? _selectedBrandName;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          backgroundColor: widget.color,
          actions: [
            const NotificationBell(),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'تسجيل الخروج',
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
            ),
          ],
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('brands').snapshots(),
          builder: (context, brandsSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('branches')
                  .snapshots(),
              builder: (context, branchesSnapshot) {
                if (brandsSnapshot.connectionState == ConnectionState.waiting ||
                    branchesSnapshot.connectionState ==
                        ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: widget.color),
                  );
                }
                if (brandsSnapshot.hasError || branchesSnapshot.hasError) {
                  return const Center(child: Text('تعذر تحميل بيانات الفروع'));
                }

                final brands = brandsSnapshot.data?.docs.toList() ?? [];
                final branches = branchesSnapshot.data?.docs.toList() ?? [];
                final options = _brandOptions(brands, branches);
                final selectedExists = options.any(
                  (option) => option.id == _selectedBrandId,
                );
                if (!selectedExists) {
                  _selectedBrandId = null;
                  _selectedBrandName = null;
                }

                final selectedBranches =
                    _selectedBrandId == null
                          ? <QueryDocumentSnapshot>[]
                          : branches.where((branch) {
                              final data =
                                  branch.data() as Map<String, dynamic>;
                              if (_selectedBrandId!.startsWith('legacy:')) {
                                return data['company_name'] ==
                                    _selectedBrandName;
                              }
                              return data['brand_id'] == _selectedBrandId ||
                                  (data['brand_id'] == null &&
                                      data['company_name'] ==
                                          _selectedBrandName);
                            }).toList()
                      ..sort((a, b) {
                        final aName =
                            (a.data() as Map<String, dynamic>)['name'] ?? '';
                        final bName =
                            (b.data() as Map<String, dynamic>)['name'] ?? '';
                        return aName.toString().compareTo(bName.toString());
                      });

                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      decoration: BoxDecoration(
                        color: widget.color,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(24),
                        ),
                      ),
                      child: Text(
                        widget.intro,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: AppTheme.cardShadow(),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(_selectedBrandId),
                          initialValue: _selectedBrandId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'العلامة التجارية',
                            prefixIcon: Icon(
                              Icons.business_rounded,
                              color: widget.color,
                            ),
                            fillColor: AppTheme.surfaceColor,
                          ),
                          hint: const Text('اختر العلامة لعرض فروعها'),
                          items: options
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option.id,
                                  child: Text(
                                    '${option.name} (${option.branchCount} فرع)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: options.isEmpty
                              ? null
                              : (value) {
                                  final option = options.firstWhere(
                                    (item) => item.id == value,
                                  );
                                  setState(() {
                                    _selectedBrandId = value;
                                    _selectedBrandName = option.name;
                                  });
                                },
                        ),
                      ),
                    ),
                    Expanded(child: _buildBranches(options, selectedBranches)),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<_BrandOption> _brandOptions(
    List<QueryDocumentSnapshot> brands,
    List<QueryDocumentSnapshot> branches,
  ) {
    final options = brands.map((brand) {
      final data = brand.data() as Map<String, dynamic>;
      final name = data['name'] as String? ?? 'بدون اسم';
      final count = branches.where((branch) {
        final branchData = branch.data() as Map<String, dynamic>;
        return branchData['brand_id'] == brand.id ||
            (branchData['brand_id'] == null &&
                branchData['company_name'] == name);
      }).length;
      return _BrandOption(id: brand.id, name: name, branchCount: count);
    }).toList();

    final knownNames = options.map((option) => option.name).toSet();
    final legacyNames = branches
        .where(
          (branch) =>
              (branch.data() as Map<String, dynamic>)['brand_id'] == null,
        )
        .map(
          (branch) =>
              ((branch.data() as Map<String, dynamic>)['company_name'] ??
                      'بدون علامة')
                  .toString(),
        )
        .where((name) => !knownNames.contains(name))
        .toSet();
    for (final name in legacyNames) {
      options.add(
        _BrandOption(
          id: 'legacy:$name',
          name: name,
          branchCount: branches.where((branch) {
            final data = branch.data() as Map<String, dynamic>;
            return data['brand_id'] == null && data['company_name'] == name;
          }).length,
        ),
      );
    }
    options.sort((a, b) => a.name.compareTo(b.name));
    return options;
  }

  Widget _buildBranches(
    List<_BrandOption> options,
    List<QueryDocumentSnapshot> branches,
  ) {
    if (options.isEmpty) {
      return const _SelectionMessage(
        icon: Icons.branding_watermark_outlined,
        title: 'لا توجد علامات تجارية',
        subtitle: 'اطلب من مسؤول النظام إضافة العلامات وربط الفروع بها.',
      );
    }
    if (_selectedBrandId == null) {
      return const _SelectionMessage(
        icon: Icons.touch_app_rounded,
        title: 'اختر العلامة التجارية',
        subtitle: 'ستظهر فروع العلامة المختارة هنا.',
      );
    }
    if (branches.isEmpty) {
      return const _SelectionMessage(
        icon: Icons.storefront_outlined,
        title: 'لا توجد فروع لهذه العلامة',
        subtitle: 'يمكن لمسؤول النظام ربط الفروع بها من إدارة الفروع.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => refreshFirestoreQueries([
        FirebaseFirestore.instance.collection('brands'),
        FirebaseFirestore.instance.collection('branches'),
      ]),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: branches.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final branch = branches[index];
          final data = branch.data() as Map<String, dynamic>;
          return Container(
            decoration: AppTheme.cardShadow(),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.all(14),
              leading: CircleAvatar(
                backgroundColor: widget.color.withValues(alpha: 0.1),
                child: Icon(widget.branchIcon, color: widget.color),
              ),
              title: Text(
                data['name'] ?? 'فرع غير مسمى',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('رمز الفرع: ${data['branch_code'] ?? 'غير محدد'}'),
              trailing: Icon(
                Icons.arrow_forward_ios_rounded,
                color: widget.color,
                size: 16,
              ),
              onTap: () => widget.onBranchSelected(context, branch),
            ),
          );
        },
      ),
    );
  }
}

class _BrandOption {
  final String id;
  final String name;
  final int branchCount;

  const _BrandOption({
    required this.id,
    required this.name,
    required this.branchCount,
  });
}

class _SelectionMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SelectionMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppTheme.textHint),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
