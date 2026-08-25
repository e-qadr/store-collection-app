import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/cash_expense_request_model.dart';
import 'package:store_collection_app/models/consumable_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/theme/app_theme.dart';

enum GroupedBranchOverviewKind { expenses, consumption }

const groupedBranchPreviewLimit = 5;

bool usesGroupedBranchOverview(UserRole role, String? branchId) {
  return (role == UserRole.collector || role == UserRole.accountant) &&
      (branchId == null || branchId.trim().isEmpty);
}

class GroupedBranchOverview extends StatelessWidget {
  final UserRole role;
  final GroupedBranchOverviewKind kind;
  final void Function(BuildContext context, String branchId, String branchName)
  onViewAll;

  const GroupedBranchOverview({
    super.key,
    required this.role,
    required this.kind,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    assert(role == UserRole.collector || role == UserRole.accountant);
    final title = kind == GroupedBranchOverviewKind.expenses
        ? 'سندات الصرف'
        : 'طلبات استهلاك منتج';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        appBar: AppBar(title: Text(title)),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('branches').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل الفروع.'));
            }
            final branches = [...?snapshot.data?.docs]
              ..sort(
                (a, b) => (a.data()['name'] ?? '').toString().compareTo(
                  (b.data()['name'] ?? '').toString(),
                ),
              );
            return ListView.separated(
              key: Key('grouped-${kind.name}-branches'),
              padding: const EdgeInsets.all(16),
              itemCount: branches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final branch = branches[index];
                final name =
                    branch.data()['name']?.toString() ?? 'فرع غير مسمى';
                return _BranchSection(
                  branchId: branch.id,
                  branchName: name,
                  kind: kind,
                  onViewAll: () => onViewAll(context, branch.id, name),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _BranchSection extends StatelessWidget {
  final String branchId;
  final String branchName;
  final GroupedBranchOverviewKind kind;
  final VoidCallback onViewAll;

  const _BranchSection({
    required this.branchId,
    required this.branchName,
    required this.kind,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = kind == GroupedBranchOverviewKind.expenses;
    final collection = isExpense
        ? CashExpenseFields.collection
        : ConsumableRequestFields.collection;
    final branchField = isExpense
        ? CashExpenseFields.branchId
        : ConsumableRequestFields.branchId;
    final createdField = isExpense
        ? CashExpenseFields.createdAt
        : ConsumableRequestFields.createdAt;
    final query = FirebaseFirestore.instance
        .collection(collection)
        .where(branchField, isEqualTo: branchId)
        .orderBy(createdField, descending: true)
        .limit(groupedBranchPreviewLimit);
    return Card(
      key: Key('grouped-${kind.name}-branch-$branchId'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    branchName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'آخر 5 سجلات',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const Divider(height: 20),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Text('تعذر تحميل سجلات الفرع.');
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) return const Text('لا توجد سجلات.');
                return Column(
                  children: docs
                      .map(
                        (doc) => isExpense
                            ? _expenseRow(
                                CashExpenseRead(id: doc.id, data: doc.data()),
                              )
                            : _consumptionRow(
                                ConsumableRequestRead(
                                  id: doc.id,
                                  data: doc.data(),
                                ),
                              ),
                      )
                      .toList(growable: false),
                );
              },
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: Key('grouped-${kind.name}-view-all-$branchId'),
                onPressed: onViewAll,
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(
                  isExpense ? 'عرض جميع سندات الفرع' : 'عرض جميع طلبات الفرع',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expenseRow(CashExpenseRead request) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(request.requestNumber),
    subtitle: Text('${_date(request.createdAt)} • ${request.status.label}'),
    trailing: SizedBox(
      width: 96,
      child: Text(
        request.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
      ),
    ),
  );

  Widget _consumptionRow(ConsumableRequestRead request) {
    final item = request.items.isEmpty ? null : request.items.first;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(item?.name ?? request.requestNumber),
      subtitle: Text('${_date(request.createdAt)} • ${request.status.label}'),
      trailing: item == null
          ? null
          : Text('${item.requestedQuantity} ${item.unit}'),
    );
  }

  String _date(DateTime? date) =>
      date == null ? '-' : DateFormat('yyyy/MM/dd').format(date);
}
