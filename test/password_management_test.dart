import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:store_collection_app/models/user_model.dart';
import 'package:store_collection_app/services/auth_api_service.dart';
import 'package:store_collection_app/utils/password_policy.dart';
import 'package:store_collection_app/widgets/password_strength_indicator.dart';

void main() {
  group('سياسة كلمة المرور', () {
    test('ترفض كلمة المرور الضعيفة وتقبل كلمة قوية', () {
      expect(PasswordPolicy.isValid('short'), isFalse);
      expect(PasswordPolicy.isValid('StrongPassword1!'), isTrue);
      expect(
        PasswordPolicy.strength('LongAndStrongPassword1!'),
        PasswordStrength.strong,
      );
    });

    test('تكتشف عدم تطابق التأكيد من خلال القيم المستقلة', () {
      const password = 'StrongPassword1!';
      const confirmation = 'StrongPassword2!';
      expect(password == confirmation, isFalse);
    });
  });

  test('المستخدم القديم يأخذ حالة ترحيل آمنة افتراضياً', () {
    final user = UserModel.fromJson({
      'uid': 'legacy-user',
      'name': 'مستخدم قديم',
      'email': 'legacy@example.com',
      'role': 'collector',
    });
    expect(user.isActive, isTrue);
    expect(user.mustChangePassword, isFalse);
    expect(user.passwordState, 'active');
    expect(user.temporaryCredentialExpiresAt, isNull);
  });

  test('يفسر إنشاء المستخدم عبر البريد الرسمي', () async {
    final service = AuthApiService(
      baseUrl: 'https://auth.example.com',
      tokenProvider: () async => 'id-token',
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer id-token');
        expect(request.body, contains('employee@example.com'));
        return http.Response('{"delivery":"email"}', 201);
      }),
    );
    final delivery = await service.createUser(
      name: 'موظف',
      email: 'employee@example.com',
      role: 'collector',
    );
    expect(delivery.emailSent, isTrue);
    expect(delivery.temporaryPassword, isNull);
  });

  test('يفسر كلمة المرور المؤقتة كاستجابة تظهر مرة واحدة', () async {
    final service = AuthApiService(
      baseUrl: 'https://auth.example.com',
      tokenProvider: () async => 'id-token',
      client: MockClient(
        (_) async => http.Response(
          '{"delivery":"temporary_password",'
          '"temporaryPassword":"TemporaryPass1!",'
          '"expiresAt":"2026-08-03T00:00:00.000Z"}',
          200,
        ),
      ),
    );
    final delivery = await service.adminResetPassword('user-1');
    expect(delivery.emailSent, isFalse);
    expect(delivery.temporaryPassword, 'TemporaryPass1!');
    expect(delivery.expiresAt, isNotNull);
  });

  test('يستلم جلسة مخصصة بعد المطالبة ببيانات الدخول المؤقتة', () async {
    final service = AuthApiService(
      baseUrl: 'https://auth.example.com',
      tokenProvider: () async => 'temporary-session-token',
      client: MockClient((request) async {
        expect(request.url.path, '/v1/auth/claim-temporary-credential');
        return http.Response('{"customToken":"one-time-custom-token"}', 200);
      }),
    );
    expect(await service.claimTemporaryCredential(), 'one-time-custom-token');
  });

  testWidgets('مؤشر القوة يعرض حالة عربية داخل اتجاه RTL', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PasswordStrengthIndicator(
              password: 'LongAndStrongPassword1!',
            ),
          ),
        ),
      ),
    );
    expect(find.text('قوة كلمة المرور'), findsOneWidget);
    expect(find.text('قوية'), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(find.byType(Directionality).last)
          .textDirection,
      TextDirection.rtl,
    );
  });
}
