import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
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
          contains('صلاحية'),
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
