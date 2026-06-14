import 'package:flutter/material.dart';
import 'package:store_collection_app/screens/dashboards/collector_dashboard.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/company_branch_selector.dart';

class CollectorBranchesScreen extends StatelessWidget {
  const CollectorBranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CompanyBranchSelector(
      title: 'اختر الشركة',
      intro:
          'اختر الشركة أو العلامة التجارية أولاً، ثم اختر الفرع المطلوب للتحصيل.',
      color: AppTheme.collectorColor,
      branchIcon: Icons.storefront_rounded,
      onBranchSelected: (context, branch) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CollectorDashboard(
            branchId: branch.id,
            branchName: branch['name'],
          ),
        ),
      ),
    );
  }
}
