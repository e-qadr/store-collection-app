import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/cash_expense_request_model.dart';
import 'package:store_collection_app/models/consumable_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/branch_scope.dart';

enum GroupedBranchOverviewKind { expenses, consumption }

const groupedBranchPreviewLimit = 3;
const expenseGroupedBranchPreviewLimit = 3;

bool usesGroupedBranchOverview(UserRole role, String? branchId) {
  return (role == UserRole.collector || role == UserRole.accountant) &&
      (branchId == null || branchId.trim().isEmpty);
}

class GroupedBranchOverviewBranch {
  final String id;
  final String name;

  const GroupedBranchOverviewBranch({required this.id, required this.name});
}

class GroupedBranchOverviewRecord {
  final String id;
  final Map<String, dynamic> data;

  const GroupedBranchOverviewRecord({required this.id, required this.data});
}

typedef GroupedBranchRecordsStream =
    Stream<List<GroupedBranchOverviewRecord>> Function(
      GroupedBranchOverviewKind kind,
      String branchId,
    );

class GroupedBranchOverview extends StatelessWidget {
  final UserRole role;
  final GroupedBranchOverviewKind kind;
  final void Function(BuildContext context, String branchId, String branchName)
  onViewAll;
  final FirebaseFirestore? firestore;
  final Stream<List<GroupedBranchOverviewBranch>>? branchStream;
  final GroupedBranchRecordsStream? recordsStream;

  const GroupedBranchOverview({
    super.key,
    required this.role,
    required this.kind,
    required this.onViewAll,
    this.firestore,
    this.branchStream,
    this.recordsStream,
  });

  Stream<List<GroupedBranchOverviewBranch>> _branches() {
    final database = firestore ?? FirebaseFirestore.instance;
    return database
        .collection('branches')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .where((doc) => isActiveOperationalBranch(doc.data()))
              .map(
                (doc) => GroupedBranchOverviewBranch(
                  id: doc.id,
                  name: doc.data()['name']?.toString() ?? 'فرع غير مسمى',
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<List<GroupedBranchOverviewRecord>> _recordsFor(
    GroupedBranchOverviewKind kind,
    String branchId,
  ) {
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
    final database = firestore ?? FirebaseFirestore.instance;
    return database
        .collection(collection)
        .where(branchField, isEqualTo: branchId)
        .orderBy(createdField, descending: true)
        .limit(
          isExpense
              ? expenseGroupedBranchPreviewLimit
              : groupedBranchPreviewLimit,
        )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) =>
                    GroupedBranchOverviewRecord(id: doc.id, data: doc.data()),
              )
              .toList(growable: false),
        );
  }

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
        body: StreamBuilder<List<GroupedBranchOverviewBranch>>(
          stream: branchStream ?? _branches(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('تعذر تحميل الفروع.'));
            }
            final branches = [...?snapshot.data]
              ..sort((a, b) => a.name.compareTo(b.name));
            if (branches.isEmpty) {
              return const Center(child: Text('لا توجد فروع متاحة.'));
            }
            return ListView.separated(
              key: Key('grouped-${kind.name}-branches'),
              padding: const EdgeInsets.all(16),
              itemCount: branches.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final branch = branches[index];
                return _BranchSection(
                  branchId: branch.id,
                  branchName: branch.name,
                  kind: kind,
                  recordsStream: (recordsStream ?? _recordsFor)(
                    kind,
                    branch.id,
                  ),
                  onViewAll: () => onViewAll(context, branch.id, branch.name),
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
  final Stream<List<GroupedBranchOverviewRecord>> recordsStream;
  final VoidCallback onViewAll;

  const _BranchSection({
    required this.branchId,
    required this.branchName,
    required this.kind,
    required this.recordsStream,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final isExpense = kind == GroupedBranchOverviewKind.expenses;
    if (isExpense) return _expenseSection();
    return _standardSection();
  }

  Widget _standardSection() {
    final isExpense = kind == GroupedBranchOverviewKind.expenses;
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
              'آخر 3 طلبات',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const Divider(height: 20),
            StreamBuilder<List<GroupedBranchOverviewRecord>>(
              stream: recordsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Text('تعذر تحميل سجلات الفرع.');
                }
                final records = snapshot.data ?? const [];
                if (records.isEmpty) {
                  return const Text('لا توجد سجلات لهذا الفرع بعد.');
                }
                return Column(
                  children: records
                      .map(
                        (record) => isExpense
                            ? _expenseRow(
                                CashExpenseRead(
                                  id: record.id,
                                  data: record.data,
                                ),
                              )
                            : _consumptionRow(
                                ConsumableRequestRead(
                                  id: record.id,
                                  data: record.data,
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

  Widget _expenseSection() {
    return Container(
      key: Key('grouped-${kind.name}-branch-$branchId'),
      decoration: AppTheme.cardShadow(radius: 18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.collectorColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: AppTheme.collectorColor,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        branchName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'أحدث سندات الصرف',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'آخر 3',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: AppTheme.dividerColor),
            const SizedBox(height: 6),
            StreamBuilder<List<GroupedBranchOverviewRecord>>(
              stream: recordsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text('تعذر تحميل سندات هذا الفرع.'),
                  );
                }
                final records = snapshot.data ?? const [];
                if (records.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text(
                        'لا توجد سندات صرف لهذا الفرع بعد.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  );
                }
                return Column(
                  children: records
                      .map(
                        (record) => _expensePreviewRow(
                          CashExpenseRead(id: record.id, data: record.data),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                key: Key('grouped-${kind.name}-view-all-$branchId'),
                onPressed: onViewAll,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('عرض جميع سندات الفرع'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.collectorColor,
                  side: BorderSide(
                    color: AppTheme.collectorColor.withValues(alpha: 0.32),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expensePreviewRow(CashExpenseRead request) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: request.status.color.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: request.status.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.title.isEmpty ? 'سند صرف نقدي' : request.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${request.requestNumber} • ${_date(request.createdAt)}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              request.status.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: request.status.color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
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
