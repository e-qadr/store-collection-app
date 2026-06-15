import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/theme/app_theme.dart';
import 'package:store_collection_app/widgets/dashboard_widgets.dart';

void main() {
  testWidgets('تعرض بطاقة الإجراء شارة الاعتمادات بدون تجاوز العرض', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: ActionCard(
                  title: 'طلبات الاعتماد والتعديل',
                  subtitle: 'مراجعة السندات وطلبات الأرشفة',
                  icon: Icons.check_circle_outline_rounded,
                  color: AppTheme.managerColor,
                  badgeText: '12',
                  badgeColor: AppTheme.errorColor,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
