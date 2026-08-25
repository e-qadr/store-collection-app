import 'package:flutter/material.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/account/account_settings_screen.dart';
import 'package:store_collection_app/screens/cash_expenses/cash_expenses_dashboard.dart';
import 'package:store_collection_app/screens/dashboards/accountant_branches_screen.dart';
import 'package:store_collection_app/screens/dashboards/accountant_dashboard.dart';
import 'package:store_collection_app/screens/dashboards/admin_dashboard.dart';
import 'package:store_collection_app/screens/dashboards/collector_branches_screen.dart';
import 'package:store_collection_app/screens/dashboards/collector_dashboard.dart';
import 'package:store_collection_app/screens/dashboards/manager_dashboard.dart';
import 'package:store_collection_app/screens/consumables/consumable_requests_dashboard.dart';
import 'package:store_collection_app/screens/inter_branch_invoices/inter_branch_invoices_dashboard.dart';
import 'package:store_collection_app/screens/products/product_catalog_management_screen.dart';
import 'package:store_collection_app/screens/purchase_invoices/purchase_invoices_dashboard.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/logout_confirmation.dart';
import 'package:store_collection_app/widgets/dashboard_widgets.dart';
import 'package:store_collection_app/widgets/notification_bell.dart';

class SystemSelectionScreen extends StatelessWidget {
  final UserRole role;
  final String? branchId;
  final String branchName;

  const SystemSelectionScreen({
    super.key,
    required this.role,
    required this.branchName,
    this.branchId,
  });

  @override
  Widget build(BuildContext context) {
    final color = _roleColor(role);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              backgroundColor: color,
              actions: [
                const NotificationBell(),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'إعدادات الحساب',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AccountSettingsScreen(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded),
                  tooltip: 'تسجيل الخروج',
                  onPressed: () => confirmAndSignOut(context),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                centerTitle: true,
                title: const Text(
                  'اختيار النظام',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                background: RoleAppBarBackground(
                  gradientColors: _roleGradient(role),
                  title: branchName,
                  subtitle: _roleLabel(role),
                  icon: _roleIcon(role),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionHeader(
                      title: 'الأنظمة المتاحة',
                      icon: Icons.apps_rounded,
                      color: AppTheme.managerColor,
                    ),
                    const SizedBox(height: 14),
                    ActionCard(
                      title: 'تحصيل دخل الفروع',
                      subtitle:
                          'النظام الحالي لإدارة سندات التحصيل والاعتمادات',
                      icon: Icons.point_of_sale_rounded,
                      color: AppTheme.collectorColor,
                      onTap: () => _openCollectionSystem(context),
                    ),
                    if (role == UserRole.collector ||
                        role == UserRole.accountant) ...[
                      const SizedBox(height: 12),
                      ActionCard(
                        title: 'إدارة المواد',
                        subtitle:
                            'إدارة المواد والوحدات والأرشفة وقائمة المواد التي تحتاج مراجعة',
                        icon: Icons.inventory_2_rounded,
                        color: AppTheme.accountantColor,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ProductCatalogManagementScreen(role: role),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ActionCard(
                      title: 'فواتير التحويل بين الفروع',
                      subtitle:
                          'إنشاء مباشر من الفرع المورد، ثم الاستلام والتسعير والترحيل',
                      icon: Icons.swap_horiz_rounded,
                      color: const Color(0xFF0277BD),
                      onTap: () => _openInterBranchInvoicesSystem(context),
                    ),
                    if (_hasPurchaseRole) ...[
                      const SizedBox(height: 12),
                      ActionCard(
                        title: 'فواتير المشتريات',
                        subtitle:
                            'إنشاء فاتورة شراء، تأكيد الاستلام، ثم المراجعة والترحيل المحاسبي',
                        icon: Icons.shopping_cart_checkout_rounded,
                        color: const Color(0xFF00695C),
                        onTap: () => _openPurchaseInvoicesSystem(context),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ActionCard(
                      title: 'طلب استهلاك منتج للعرض',
                      subtitle:
                          'طلب المستهلكات ثم مراجعة المدير العام والاعتماد المحاسبي',
                      icon: Icons.inventory_2_rounded,
                      color: AppTheme.warningColor,
                      onTap: () => _openConsumableRequestsSystem(context),
                    ),
                    const SizedBox(height: 12),
                    ActionCard(
                      title: 'سندات الصرف والمنصرفات النقدية',
                      subtitle:
                          'طلب صرف ثم اعتماد المدير العام وإرفاق الفاتورة واعتماد المحاسب',
                      icon: Icons.payments_rounded,
                      color: AppTheme.errorColor,
                      onTap: () => _openCashExpensesSystem(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCollectionSystem(BuildContext context) {
    final id = branchId ?? '';
    if (id.isEmpty) {
      final selectionScreen = switch (role) {
        UserRole.collector => const CollectorBranchesScreen(),
        UserRole.accountant => const AccountantBranchesScreen(),
        UserRole.manager => null,
        UserRole.admin => const AdminDashboard(),
      };
      if (selectionScreen != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => selectionScreen),
        );
      }
      return;
    }

    final screen = switch (role) {
      UserRole.collector => CollectorDashboard(
        branchId: id,
        branchName: branchName,
      ),
      UserRole.manager => ManagerDashboard(
        branchId: id,
        branchName: branchName,
      ),
      UserRole.accountant => AccountantDashboard(
        branchId: id,
        branchName: branchName,
      ),
      UserRole.admin => const AdminDashboard(),
    };
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  void _openInterBranchInvoicesSystem(BuildContext context) {
    if (role == UserRole.collector ||
        role == UserRole.accountant ||
        role == UserRole.admin) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InterBranchInvoicesDashboard(
            role: role,
            branchName: 'جميع الفروع',
          ),
        ),
      );
      return;
    }

    final id = branchId ?? '';
    if (id.isEmpty) {
      final selectionScreen = switch (role) {
        UserRole.collector => null,
        UserRole.accountant => null,
        UserRole.manager => null,
        UserRole.admin => null,
      };
      if (selectionScreen != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => selectionScreen),
        );
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InterBranchInvoicesDashboard(
          role: role,
          branchId: id,
          branchName: branchName,
        ),
      ),
    );
  }

  void _openPurchaseInvoicesSystem(BuildContext context) {
    if (!_hasPurchaseRole) return;
    final id = branchId?.trim() ?? '';
    if (role == UserRole.manager && id.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseInvoicesDashboard(
          role: role,
          branchId: id.isEmpty ? null : id,
          branchName: role == UserRole.manager ? branchName : 'جميع الفروع',
        ),
      ),
    );
  }

  bool get _hasPurchaseRole => const {
    UserRole.manager,
    UserRole.collector,
    UserRole.accountant,
  }.contains(role);

  void _openConsumableRequestsSystem(BuildContext context) {
    if (role == UserRole.admin) return;

    final id = branchId ?? '';
    if (id.isEmpty) {
      final selectionScreen = switch (role) {
        UserRole.collector => const CollectorBranchesScreen(
          openConsumableRequests: true,
        ),
        UserRole.accountant => const AccountantBranchesScreen(
          openConsumableRequests: true,
        ),
        UserRole.manager => null,
        UserRole.admin => null,
      };
      if (selectionScreen != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => selectionScreen),
        );
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConsumableRequestsDashboard(
          role: role,
          branchId: id,
          branchName: branchName,
        ),
      ),
    );
  }

  void _openCashExpensesSystem(BuildContext context) {
    if (role == UserRole.admin) return;

    final id = branchId ?? '';
    if (id.isEmpty) {
      final selectionScreen = switch (role) {
        UserRole.collector => const CollectorBranchesScreen(
          openCashExpenses: true,
        ),
        UserRole.accountant => const AccountantBranchesScreen(
          openCashExpenses: true,
        ),
        UserRole.manager => null,
        UserRole.admin => null,
      };
      if (selectionScreen != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => selectionScreen),
        );
      }
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashExpensesDashboard(
          role: role,
          branchId: id,
          branchName: branchName,
        ),
      ),
    );
  }

  Color _roleColor(UserRole role) {
    switch (role) {
      case UserRole.collector:
        return AppTheme.collectorColor;
      case UserRole.manager:
        return AppTheme.managerColor;
      case UserRole.accountant:
        return AppTheme.accountantColor;
      case UserRole.admin:
        return AppTheme.adminColor;
    }
  }

  List<Color> _roleGradient(UserRole role) {
    switch (role) {
      case UserRole.collector:
        return AppTheme.collectorGradient;
      case UserRole.manager:
        return AppTheme.managerGradient;
      case UserRole.accountant:
        return AppTheme.accountantGradient;
      case UserRole.admin:
        return AppTheme.adminGradient;
    }
  }

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.collector:
        return 'المدير العام';
      case UserRole.manager:
        return 'مدير الفرع';
      case UserRole.accountant:
        return 'المحاسب';
      case UserRole.admin:
        return 'المدير العام';
    }
  }

  IconData _roleIcon(UserRole role) {
    switch (role) {
      case UserRole.collector:
        return Icons.admin_panel_settings_rounded;
      case UserRole.manager:
        return Icons.business_center_rounded;
      case UserRole.accountant:
        return Icons.calculate_rounded;
      case UserRole.admin:
        return Icons.admin_panel_settings_rounded;
    }
  }
}
