import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/models/enums.dart';
import 'package:store_collection_app/screens/transactions/accountant_collection_review_screen.dart';
import 'package:store_collection_app/utils/accountant_collection_review.dart';

void main() {
  test(
    'accountant dashboard keeps Collection actions and removes unrelated cards',
    () {
      final source = File(
        'lib/screens/dashboards/accountant_dashboard.dart',
      ).readAsStringSync();

      expect(source, contains('سجل السندات والاعتماد'));
      expect(source, contains('مراجعة وحجز سند تحصيل'));
      expect(source, contains('AccountantCollectionReviewScreen'));
      expect(source, isNot(contains("title: 'فواتير التحويل بين الفروع'")));
      expect(source, isNot(contains("title: 'دليل المواد والمنتجات'")));
    },
  );

  test('review comparison identifies matches, increases, and decreases', () {
    const matching = AccountantCollectionReviewComparison(
      branchReportedAmount: 100,
      reviewedAmount: 100,
    );
    expect(matching.isMatch, isTrue);
    expect(matching.hasDifference, isFalse);

    const increase = AccountantCollectionReviewComparison(
      branchReportedAmount: 100,
      reviewedAmount: 125,
    );
    expect(increase.hasDifference, isTrue);
    expect(increase.differenceAmount, 25);
    expect(increase.differenceTypeLabel, 'زيادة');

    const decrease = AccountantCollectionReviewComparison(
      branchReportedAmount: 100,
      reviewedAmount: 80,
    );
    expect(decrease.hasDifference, isTrue);
    expect(decrease.differenceAmount, 20);
    expect(decrease.differenceTypeLabel, 'نقص');
  });

  test(
    'the existing collector direct-create screen remains a separate action',
    () {
      final source = File(
        'lib/screens/transactions/new_transaction_screen.dart',
      ).readAsStringSync();
      expect(source, contains('DatabaseService().addTransaction(transaction)'));
      expect(source, contains('تسجيل واعتماد السند'));
    },
  );

  test(
    'the full-page reservation route contains no physical-collection action',
    () {
      final source = File(
        'lib/screens/transactions/accountant_collection_review_screen.dart',
      ).readAsStringSync();
      expect(source, contains("'مراجعة وحجز سند تحصيل'"));
      expect(source, contains("'حجز الرقم الرسمي'"));
      expect(source, contains('reserveReviewedCollectionVoucher'));
      expect(source, isNot(contains('collectReservedCollectionVoucher')));
      expect(source, isNot(contains('showModalBottomSheet')));
    },
  );

  test('only the actual accountant role can open the reservation route', () {
    expect(
      AccountantCollectionReviewScreen.canOpenFor(UserRole.accountant),
      isTrue,
    );
    expect(
      AccountantCollectionReviewScreen.canOpenFor(UserRole.collector),
      isFalse,
    );
    expect(
      AccountantCollectionReviewScreen.canOpenFor(UserRole.manager),
      isFalse,
    );
    expect(
      AccountantCollectionReviewScreen.canOpenFor(UserRole.admin),
      isFalse,
    );
  });
}
