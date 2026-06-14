import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

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
  String? _selectedCompany;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(
          title: Text(
            _selectedCompany == null ? widget.title : 'فروع $_selectedCompany',
          ),
          backgroundColor: widget.color,
          elevation: 0,
          leading: _selectedCompany == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'العودة إلى الشركات',
                  onPressed: () => setState(() => _selectedCompany = null),
                ),
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
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: Text(
                _selectedCompany == null
                    ? widget.intro
                    : 'اختر الفرع المطلوب من فروع شركة $_selectedCompany.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('branches')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: CircularProgressIndicator(color: widget.color),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text('لا توجد فروع مسجلة حتى الآن'),
                    );
                  }

                  final branches = snapshot.data!.docs;
                  if (_selectedCompany == null) {
                    final companies =
                        branches
                            .map(
                              (branch) =>
                                  ((branch.data()
                                              as Map<
                                                String,
                                                dynamic
                                              >)['company_name'] ??
                                          'بدون شركة')
                                      as String,
                            )
                            .toSet()
                            .toList()
                          ..sort();
                    return ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: companies.length,
                      itemBuilder: (context, index) {
                        final company = companies[index];
                        final count = branches.where((branch) {
                          final data = branch.data() as Map<String, dynamic>;
                          return (data['company_name'] ?? 'بدون شركة') ==
                              company;
                        }).length;
                        return _selectionCard(
                          icon: Icons.business_rounded,
                          title: company,
                          subtitle: '$count ${count == 1 ? 'فرع' : 'فروع'}',
                          onTap: () =>
                              setState(() => _selectedCompany = company),
                        );
                      },
                    );
                  }

                  final companyBranches = branches.where((branch) {
                    final data = branch.data() as Map<String, dynamic>;
                    return (data['company_name'] ?? 'بدون شركة') ==
                        _selectedCompany;
                  }).toList();
                  return ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: companyBranches.length,
                    itemBuilder: (context, index) {
                      final branch = companyBranches[index];
                      final data = branch.data() as Map<String, dynamic>;
                      return _selectionCard(
                        icon: widget.branchIcon,
                        title: data['name'] ?? 'فرع غير مسمى',
                        subtitle:
                            'رمز الفرع: ${data['branch_code'] ?? 'غير محدد'}',
                        onTap: () => widget.onBranchSelected(context, branch),
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

  Widget _selectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: AppTheme.cardShadow(),
      child: Material(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.all(14),
          leading: CircleAvatar(
            backgroundColor: widget.color.withValues(alpha: 0.1),
            child: Icon(icon, color: widget.color),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            color: widget.color,
            size: 16,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
