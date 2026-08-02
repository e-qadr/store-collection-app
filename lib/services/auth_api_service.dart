import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AuthApiException implements Exception {
  final String code;
  final String message;

  const AuthApiException(this.code, this.message);

  @override
  String toString() => message;
}

class CredentialDelivery {
  final bool emailSent;
  final String? temporaryPassword;
  final DateTime? expiresAt;

  const CredentialDelivery._({
    required this.emailSent,
    this.temporaryPassword,
    this.expiresAt,
  });

  factory CredentialDelivery.fromJson(Map<String, dynamic> json) {
    final delivery = json['delivery'] as String?;
    return CredentialDelivery._(
      emailSent: delivery == 'email',
      temporaryPassword: delivery == 'temporary_password'
          ? json['temporaryPassword'] as String?
          : null,
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
    );
  }
}

class AuthApiService {
  static const String configuredBaseUrl = String.fromEnvironment(
    'AUTH_API_BASE_URL',
  );

  final String _baseUrl;
  final http.Client _client;
  final Future<String?> Function() _tokenProvider;

  AuthApiService({
    String? baseUrl,
    http.Client? client,
    Future<String?> Function()? tokenProvider,
  }) : _baseUrl = (baseUrl ?? configuredBaseUrl).replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _tokenProvider =
           tokenProvider ??
           (() {
             final user = FirebaseAuth.instance.currentUser;
             return user == null
                 ? Future<String?>.value()
                 : user.getIdToken(true);
           });

  bool get isConfigured => _baseUrl.isNotEmpty;

  Future<CredentialDelivery> createUser({
    required String name,
    required String email,
    required String role,
    String? branchId,
  }) async {
    final json = await _authorizedRequest(
      'POST',
      '/v1/admin/users',
      body: {
        'name': name,
        'email': email,
        'role': role,
        if (branchId != null) 'branchId': branchId,
      },
    );
    return CredentialDelivery.fromJson(json);
  }

  Future<CredentialDelivery> adminResetPassword(String uid) async {
    final json = await _authorizedRequest(
      'POST',
      '/v1/admin/users/${Uri.encodeComponent(uid)}/reset-password',
    );
    return CredentialDelivery.fromJson(json);
  }

  Future<void> updateUser(
    String uid, {
    String? role,
    String? branchId,
    bool clearBranch = false,
    bool? isActive,
  }) async {
    await _authorizedRequest(
      'PATCH',
      '/v1/admin/users/${Uri.encodeComponent(uid)}',
      body: {
        if (role != null) 'role': role,
        if (branchId != null || clearBranch) 'branchId': branchId,
        if (isActive != null) 'isActive': isActive,
      },
    );
  }

  Future<void> assignBranchManager({
    required String branchId,
    String? managerUid,
  }) async {
    await _authorizedRequest(
      'POST',
      '/v1/admin/branches/${Uri.encodeComponent(branchId)}/manager',
      body: {'managerUid': managerUid},
    );
  }

  Future<void> changePassword(String newPassword) async {
    await _authorizedRequest(
      'POST',
      '/v1/auth/change-password',
      body: {'newPassword': newPassword},
    );
  }

  Future<String> claimTemporaryCredential() async {
    final json = await _authorizedRequest(
      'POST',
      '/v1/auth/claim-temporary-credential',
    );
    final customToken = json['customToken'] as String?;
    if (customToken == null || customToken.isEmpty) {
      throw const AuthApiException(
        'invalid-response',
        'تعذر بدء جلسة إعداد كلمة المرور بأمان.',
      );
    }
    return customToken;
  }

  Future<void> completeEmailSetup() async {
    await _authorizedRequest('POST', '/v1/auth/complete-email-setup');
  }

  Future<void> sendForgotPasswordEmail(String email) async {
    _ensureConfigured();
    try {
      await _client
          .post(
            Uri.parse('$_baseUrl/v1/auth/forgot-password'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const AuthApiException(
        'network-error',
        'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مرة أخرى.',
      );
    }
  }

  Future<Map<String, dynamic>> _authorizedRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    _ensureConfigured();
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const AuthApiException(
        'unauthenticated',
        'انتهت جلسة الدخول. سجل الدخول مجدداً.',
      );
    }
    http.Response response;
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final headers = {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      };
      final encodedBody = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 20));
        case 'PATCH':
          response = await _client
              .patch(uri, headers: headers, body: encodedBody)
              .timeout(const Duration(seconds: 20));
        default:
          throw StateError('Unsupported method: $method');
      }
    } on AuthApiException {
      rethrow;
    } catch (_) {
      throw const AuthApiException(
        'network-error',
        'تعذر الاتصال بالخادم. تحقق من الشبكة وحاول مرة أخرى.',
      );
    }
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'] as Map<String, dynamic>?;
      throw AuthApiException(
        error?['code'] as String? ?? 'request-failed',
        error?['message'] as String? ?? 'تعذر إتمام العملية.',
      );
    }
    return decoded;
  }

  Map<String, dynamic> _decode(String source) {
    if (source.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(source) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  void _ensureConfigured() {
    if (!isConfigured) {
      throw const AuthApiException(
        'configuration-error',
        'خدمة إدارة الحسابات غير مهيأة في هذا الإصدار من التطبيق.',
      );
    }
  }
}
