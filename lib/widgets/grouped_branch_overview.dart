import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:store_collection_app/models/cash_expense_request_model.dart';
import 'package:store_collection_app/models/consumable_request_model.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/utils/branch_scope.dart';

enum GroupedBranchOverviewKind { expenses, consumption }

const groupedBranchPreviewLimit = 5;

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
              .where((doc) => !isTransferOnlyMainBranch(doc.data()))
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
        .limit(groupedBranchPreviewLimit)
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
