import 'package:flutter/material.dart';
import 'package:store_collection_app/screens/dashboards/accountant_dashboard.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/company_branch_selector.dart';

class AccountantBranchesScreen extends StatelessWidget {
  const AccountantBranchesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CompanyBranchSelector(
      title: 'اختر الشركة',
      intro:
          'اختر الشركة أو العلامة التجارية أولاً، ثم اختر الفرع للمراجعة المالية.',
      color: AppTheme.accountantColor,
      branchIcon: Icons.account_balance_rounded,
      onBranchSelected: (context, branch) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AccountantDashboard(
            branchId: branch.id,
            branchName: branch['name'],
          ),
        ),
      ),
    );
  }
}
