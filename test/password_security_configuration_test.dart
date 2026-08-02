import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String server;
  late String rules;
  late String authService;
  late String authGate;

  setUpAll(() {
    server = File(
      'hostinger-push-server/password-management.js',
    ).readAsStringSync();
    rules = File('firestore.rules').readAsStringSync();
    authService = File('lib/services/auth_service.dart').readAsStringSync();
    authGate = File('lib/screens/auth/auth_gate.dart').readAsStringSync();
  });

  test('إنشاء المستخدم يتم في Firebase Admin مع حالة تغيير إلزامية', () {
    expect(server, contains('auth.createUser'));
    expect(server, contains('mustChangePassword: true'));
    expect(server, contains('temporaryCredentialExpiresAt'));
    expect(server, contains('admin_create_user'));
  });

  test('دعوة البريد تستخدم مسار Firebase الرسمي ولها بديل آمن', () {
    expect(server, contains('accounts:sendOobCode'));
    expect(server, contains('requestType: "PASSWORD_RESET"'));
    expect(server, contains('secureTemporaryPassword'));
    expect(server, isNot(contains('console.log(temporaryPassword)')));
  });

  test('المطالبة تدور كلمة المرور المؤقتة قبل جلسة الإعداد', () {
    expect(server, contains('/auth/claim-temporary-credential'));
    expect(server, contains('passwordState: "temporary_claiming"'));
    expect(server, contains('auth.createCustomToken'));
    expect(server, contains('password_setup: true'));
  });

  test('إعداد البريد يكتمل دون طلب كلمة مرور ثانية', () {
    expect(server, contains('passwordState: "email_setup_sent"'));
    expect(server, contains('/auth/complete-email-setup'));
    expect(server, contains('complete_email_password_setup'));
  });

  test('إعادة تعيين المسؤول تلغي الجلسات وتسجل تدقيقاً', () {
    expect(server, contains('/admin/users/:uid/reset-password'));
    expect(server, contains('auth.revokeRefreshTokens(targetUid)'));
    expect(server, contains('admin_reset_password'));
    expect(server, contains('password_audit_events'));
  });

  test('كل مسارات الإدارة تمر عبر التحقق من المسؤول', () {
    expect(server, contains('router.post("/admin/users", requireAdmin'));
    expect(
      server,
      contains('router.post("/admin/users/:uid/reset-password", requireAdmin'),
    );
    expect(server, contains('router.patch("/admin/users/:uid", requireAdmin'));
    expect(server, contains('auth.verifyIdToken(token, true)'));
  });

  test('الاستعادة محايدة ومحددة المعدل', () {
    expect(server, contains('/auth/forgot-password'));
    expect(server, contains('GENERIC_RESET_MESSAGE'));
    expect(server, contains('resetIpLimiter'));
    expect(server, contains('resetEmailLimiter'));
  });

  test('قواعد Firestore تمنع تجاوز حالة تغيير كلمة المرور من العميل', () {
    expect(
      rules,
      contains("profile().get('mustChangePassword', false) == false"),
    );
    expect(rules, contains('allow create, delete: if false'));
    expect(rules, contains('password_audit_events'));
    expect(rules, contains('allow read, write: if false'));
    expect(rules, isNot(contains("'mustChangePassword',\n          'role'")));
  });

  test('تغيير كلمة المرور داخل الحساب يعيد التحقق أولاً', () {
    expect(authService, contains('reauthenticateWithCredential'));
    expect(authService, contains('EmailAuthProvider.credential'));
    expect(authService, contains('_authApiService.changePassword'));
  });

  test('بوابة الدخول تمنع بقية التطبيق حتى اكتمال التغيير', () {
    expect(authGate, contains('if (user.mustChangePassword)'));
    expect(authGate, contains('MandatoryPasswordChangeScreen'));
    expect(authGate, contains('credentialExpired'));
  });
}
