import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_collection_app/theme/app_theme.dart';

enum BranchRequestCategory { shortage, need, maintenance, general, other }

extension BranchRequestCategoryX on BranchRequestCategory {
  String get value => name;

  String get label => switch (this) {
    BranchRequestCategory.shortage => 'نقص',
    BranchRequestCategory.need => 'احتياج',
    BranchRequestCategory.maintenance => 'صيانة',
    BranchRequestCategory.general => 'طلب عام',
    BranchRequestCategory.other => 'أخرى',
  };
}

enum BranchRequestPriority { normal, important, urgent }

extension BranchRequestPriorityX on BranchRequestPriority {
  String get value => name;

  String get label => switch (this) {
    BranchRequestPriority.normal => 'عادي',
    BranchRequestPriority.important => 'مهم',
    BranchRequestPriority.urgent => 'عاجل',
  };

  Color get color => switch (this) {
    BranchRequestPriority.normal => AppTheme.primaryOlive,
    BranchRequestPriority.important => AppTheme.warningColor,
    BranchRequestPriority.urgent => AppTheme.errorColor,
  };
}

enum BranchRequestStatus { newRequest, inProgress, completed }

extension BranchRequestStatusX on BranchRequestStatus {
  String get value => switch (this) {
    BranchRequestStatus.newRequest => 'new',
    BranchRequestStatus.inProgress => 'in_progress',
    BranchRequestStatus.completed => 'completed',
  };

  String get label => switch (this) {
    BranchRequestStatus.newRequest => 'جديد',
    BranchRequestStatus.inProgress => 'قيد التنفيذ',
    BranchRequestStatus.completed => 'مكتمل',
  };

  Color get color => switch (this) {
    BranchRequestStatus.newRequest => AppTheme.pendingColor,
    BranchRequestStatus.inProgress => AppTheme.warningColor,
    BranchRequestStatus.completed => AppTheme.successColor,
  };

  bool get isPending => this != BranchRequestStatus.completed;
}

BranchRequestCategory branchRequestCategoryFromString(String? value) =>
    BranchRequestCategory.values.firstWhere(
      (category) => category.value == value,
      orElse: () => BranchRequestCategory.general,
    );

BranchRequestPriority branchRequestPriorityFromString(String? value) =>
    BranchRequestPriority.values.firstWhere(
      (priority) => priority.value == value,
      orElse: () => BranchRequestPriority.normal,
    );

BranchRequestStatus branchRequestStatusFromString(String? value) =>
    BranchRequestStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => BranchRequestStatus.newRequest,
    );

class BranchRequestFields {
  BranchRequestFields._();

  static const collection = 'branch_requests';
  static const id = 'id';
  static const branchId = 'branch_id';
  static const branchName = 'branch_name';
  static const title = 'title';
  static const description = 'description';
  static const category = 'category';
  static const priority = 'priority';
  static const status = 'status';
  static const createdBy = 'created_by';
  static const createdByName = 'created_by_name';
  static const createdAt = 'created_at';
  static const startedBy = 'started_by';
  static const startedByName = 'started_by_name';
  static const startedAt = 'started_at';
  static const completedBy = 'completed_by';
  static const completedByName = 'completed_by_name';
  static const completedAt = 'completed_at';
  static const completionNote = 'completion_note';
  static const lastUpdated = 'last_updated';
  static const history = 'history';
}

class BranchRequestRead {
  final String id;
  final Map<String, dynamic> data;

  const BranchRequestRead({required this.id, required this.data});

  String get branchId => _text(BranchRequestFields.branchId);
  String get branchName => _text(BranchRequestFields.branchName);
  String get title => _text(BranchRequestFields.title);
  String get description => _text(BranchRequestFields.description);
  String get createdByName => _text(BranchRequestFields.createdByName);
  String get completionNote => _text(BranchRequestFields.completionNote);
  BranchRequestCategory get category =>
      branchRequestCategoryFromString(_text(BranchRequestFields.category));
  BranchRequestPriority get priority =>
      branchRequestPriorityFromString(_text(BranchRequestFields.priority));
  BranchRequestStatus get status =>
      branchRequestStatusFromString(_text(BranchRequestFields.status));
  DateTime? get createdAt => _date(data[BranchRequestFields.createdAt]);
  DateTime? get startedAt => _date(data[BranchRequestFields.startedAt]);
  DateTime? get completedAt => _date(data[BranchRequestFields.completedAt]);

  List<Map<String, dynamic>> get history {
    final raw = data[BranchRequestFields.history];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  String _text(String field) => data[field]?.toString().trim() ?? '';

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

class BranchRequestWorkflow {
  BranchRequestWorkflow._();

  static bool canTransition(BranchRequestStatus from, BranchRequestStatus to) =>
      (from == BranchRequestStatus.newRequest &&
          to == BranchRequestStatus.inProgress) ||
      (from == BranchRequestStatus.inProgress &&
          to == BranchRequestStatus.completed);
}
