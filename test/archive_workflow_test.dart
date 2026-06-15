import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/utils/archive_workflow.dart';

void main() {
  group('مسار اعتماد الأرشفة', () {
    test('لا يعتبر الطلب مكتملاً بدون الموافقات الثلاث', () {
      final data = <String, dynamic>{
        'archive_approvals': {
          'collector': {'user_id': 'collector-1'},
          'manager': {'user_id': 'manager-1'},
        },
      };

      expect(archiveApprovalCount(data), 2);
      expect(areArchiveApprovalsComplete(data), isFalse);
    });

    test('يعتبر الطلب مكتملاً بعد موافقة جميع الأدوار المطلوبة', () {
      final data = <String, dynamic>{
        'archive_approvals': {
          'collector': {'user_id': 'collector-1'},
          'manager': {'user_id': 'manager-1'},
          'accountant': {'user_id': 'accountant-1'},
        },
      };

      expect(archiveApprovalCount(data), 3);
      expect(areArchiveApprovalsComplete(data), isTrue);
      expect(hasArchiveApproval(data, 'manager'), isTrue);
      expect(hasArchiveApproval(data, 'admin'), isFalse);
    });
  });
}
