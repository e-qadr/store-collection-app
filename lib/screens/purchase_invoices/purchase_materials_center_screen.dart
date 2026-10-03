import 'package:flutter/material.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/purchase_invoices/product_branch_accounting_screen.dart';
import 'package:store_collection_app/screens/purchase_invoices/product_review_queue_screen.dart';
import 'package:store_collection_app/theme/app_theme.dart';

/// One operational entry point for the two consecutive material steps:
/// review a received material, then make the newly created catalog material
/// available in every branch ledger.
class PurchaseMaterialsCenterScreen extends StatelessWidget {
  final UserRole role;
  final String? branchId;
  final String branchName;

  const PurchaseMaterialsCenterScreen({
    super.key,
    required this.role,
    required this.branchName,
    this.branchId,
  });

  bool get _hasBranch => branchId?.trim().isNotEmpty == true;
  bool get _isAccountant => role == UserRole.accountant;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      appBar: AppBar(title: const Text('إدارة مواد المشتريات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
        children: [
          _hero(),
          const SizedBox(height: 22),
          const Text(
            'دورة المادة الجديدة',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            'تبدأ بمراجعة المادة الواردة، ثم تُربط محاسبيًا في فروع العلامة.',
            style: TextStyle(color: AppTheme.textHint, height: 1.4),
          ),
          const SizedBox(height: 14),
          _flow(),
          const SizedBox(height: 18),
          _actionCard(
            context,
            step: '1',
            icon: Icons.fact_check_rounded,
            color: AppTheme.warningColor,
            title: 'مراجعة المواد الواردة',
            subtitle:
                'اربط المادة بمادة كتالوج موجودة أو أنشئها كمادة جديدة عند الحاجة.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ProductReviewQueueScreen(role: role, branchId: branchId),
              ),
            ),
          ),
          _actionCard(
            context,
            step: '2',
            icon: Icons.account_tree_rounded,
            color: AppTheme.oliveGreen,
            title: _isAccountant
                ? 'ربط مواد فرعي محاسبيًا'
                : 'متابعة ربط المواد بالفروع',
            subtitle: _isAccountant
                ? 'أدخل مرجع حساب كل مادة جديدة في $branchName.'
                : 'تابع اكتمال ربط المواد الجديدة في كل فرع من فروع العلامة.',
            enabled: _hasBranch,
            disabledHint: 'اختر فرعًا أولًا لتحديد سجل الربط المحاسبي.',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProductBranchAccountingScreen(
                  role: role,
                  branchId: branchId!,
                  branchName: branchName,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppTheme.oliveSurface.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.primaryOlive),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'مواد الكتالوج الموجودة مسبقًا لا تحتاج إعادة ربط. تظهر هنا المواد الجديدة التي أُنشئت من مراجعة فواتير الشراء فقط.',
                    style: TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: AppTheme.collectorGradient),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(Icons.inventory_2_rounded, color: Colors.white),
        ),
        const SizedBox(width: 13),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'مكان واحد لدورة المادة',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'مراجعة المادة ثم تجهيزها محاسبيًا للفروع.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _flow() => Row(
    children: [
      _flowStep('مراجعة', Icons.fact_check_outlined),
      const Expanded(child: Divider(indent: 8, endIndent: 8)),
      _flowStep('كتالوج', Icons.inventory_2_outlined),
      const Expanded(child: Divider(indent: 8, endIndent: 8)),
      _flowStep('ربط الفروع', Icons.account_tree_outlined),
    ],
  );

  Widget _flowStep(String title, IconData icon) => Column(
    children: [
      Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppTheme.oliveSurface,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: AppTheme.primaryOlive),
      ),
      const SizedBox(height: 5),
      Text(
        title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ],
  );

  Widget _actionCard(
    BuildContext context, {
    required String step,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
    String? disabledHint,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: enabled
          ? onTap
          : () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(disabledHint ?? 'هذا الإجراء غير متاح الآن.'),
              ),
            ),
      child: Opacity(
        opacity: enabled ? 1 : 0.62,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  step,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTheme.textHint,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: AppTheme.textHint),
            ],
          ),
        ),
      ),
    ),
  );
}
