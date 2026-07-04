import 'package:store_collection_app/models/enums.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String? branchId;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.branchId,
  });

  // تحويل البيانات القادمة من فايربيس إلى كائن دارت
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'],
      name: json['name'],
      email: json['email'],
      role: UserRole.values.firstWhere((e) => e.name == json['role']),
      branchId: json['branchId'],
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
    };
  }
}
