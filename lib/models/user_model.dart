import 'package:store_collection_app/models/enums.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String? branchId;
  final bool isActive;
  final bool mustChangePassword;
  final String passwordState;
  final DateTime? temporaryCredentialExpiresAt;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.branchId,
    this.isActive = true,
    this.mustChangePassword = false,
    this.passwordState = 'active',
    this.temporaryCredentialExpiresAt,
  });

  // تحويل البيانات القادمة من فايربيس إلى كائن دارت
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.collector,
      ),
      branchId: json['branchId'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      mustChangePassword: json['mustChangePassword'] as bool? ?? false,
      passwordState: json['passwordState'] as String? ?? 'active',
      temporaryCredentialExpiresAt: _dateTimeOf(
        json['temporaryCredentialExpiresAt'],
      ),
    );
  }

  // تحويل الكائن إلى Map لرفعه إلى فايربيس
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role.name,
      'branchId': branchId,
      'isActive': isActive,
      'mustChangePassword': mustChangePassword,
      'passwordState': passwordState,
      if (temporaryCredentialExpiresAt != null)
        'temporaryCredentialExpiresAt': temporaryCredentialExpiresAt,
    };
  }

  bool get temporaryCredentialExpired =>
      temporaryCredentialExpiresAt != null &&
      !temporaryCredentialExpiresAt!.isAfter(DateTime.now());

  static DateTime? _dateTimeOf(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return value.toDate() as DateTime;
    } catch (_) {
      return null;
    }
  }
}
