import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/utils/catalog_actor_access.dart';
import 'package:store_collection_app/utils/catalog_operation_error.dart';

void main() {
  group('catalogOperationErrorText', () {
    test(
      'keeps Firestore resource exhaustion distinct from invalid material data',
      () {
        expect(
          catalogOperationErrorText(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'resource-exhausted',
            ),
          ),
          contains('لم يتم حفظ المادة'),
        );
      },
    );

    test('keeps a known profile restriction actionable', () {
      expect(
        catalogOperationErrorText(
          const CatalogActorAccessException(
            'يجب تغيير كلمة المرور أولاً قبل إنشاء المواد أو تعديلها.',
          ),
        ),
        contains('تغيير كلمة المرور'),
      );
    });

    test(
      'maps permission, availability, conflict, and malformed input safely',
      () {
        expect(
          catalogOperationErrorText(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
            ),
          ),
          contains('رفضت قاعدة البيانات'),
        );
        expect(
          catalogOperationErrorText(
            FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          ),
          contains('غير متاحة'),
        );
        expect(
          catalogOperationErrorText(
            FirebaseException(plugin: 'cloud_firestore', code: 'aborted'),
          ),
          contains('تعارض'),
        );
        expect(
          catalogOperationErrorText(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'invalid-argument',
            ),
          ),
          contains('غير صالحة'),
        );
        expect(
          catalogOperationErrorText(
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'failed-precondition',
            ),
          ),
          contains('بيانات المادة الحالية'),
        );
      },
    );

    test('does not expose unknown Firebase messages', () {
      expect(
        catalogOperationErrorText(
          FirebaseException(
            plugin: 'cloud_firestore',
            code: 'internal',
            message: 'sensitive backend diagnostic',
          ),
        ),
        isNull,
      );
    });
  });
}
