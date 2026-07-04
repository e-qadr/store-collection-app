import 'package:flutter/material.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/cash_expenses/cash_expenses_dashboard.dart';
import 'package:store_collection_app/screens/consumables/consumable_requests_dashboard.dart';
import 'package:store_collection_app/screens/dashboards/accountant_dashboard.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/inter_branch_invoices_dashboard.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/company_branch_selector.dart';

class AccountantBranchesScreen extends StatelessWidget {
  final bool openInterBranchInvoices;
  final bool openConsumableRequests;
  final bool openCashExpenses;

  const AccountantBranchesScreen({
    super.key,
    this.openInterBranchInvoices = false,
    this.openConsumableRequests = false,
    this.openCashExpenses = false,
  });

  @override
  Widget build(BuildContext context) {
    return CompanyBranchSelector(
      title: 'اختر الشركة',
      intro: openInterBranchInvoices
          ? 'اختر الشركة أو العلامة التجارية أولاً، ثم اختر الفرع لعرض فواتيره الصادرة.'
          : openConsumableRequests
          ? 'اختر الشركة أو العلامة التجارية أولاً، ثم اختر الفرع لاعتماد طلبات المستهلكات.'
          : openCashExpenses
          ? 'اختر الشركة أو العلامة التجارية أولاً، ثم اختر الفرع لاعتماد المصروفات النقدية.'
          : 'اختر الشركة أو العلامة التجارية أولاً، ثم اختر الفرع للمراجعة المالية.',
      color: AppTheme.accountantColor,
      branchIcon: Icons.account_balance_rounded,
      onBranchSelected: (context, branch) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) {
            final branchName = branch['name']?.toString() ?? 'فرع غير مسمى';
            if (openInterBranchInvoices) {
              return InterBranchInvoicesDashboard(
                role: UserRole.accountant,
                branchId: branch.id,
                branchName: branchName,
              );
            }
            if (openConsumableRequests) {
              return ConsumableRequestsDashboard(
                role: UserRole.accountant,
                branchId: branch.id,
                branchName: branchName,
              );
            }
            if (openCashExpenses) {
              return CashExpensesDashboard(
                role: UserRole.accountant,
                branchId: branch.id,
                branchName: branchName,
              );
            }
            return AccountantDashboard(
              branchId: branch.id,
              branchName: branchName,
            );
          },
        ),
      ),
    );
  }
}
