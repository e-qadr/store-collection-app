import 'package:store_collection_app/models/enums.dart';

abstract final class MaterialManagementAccess {
  static bool canAccess(UserRole? role, {bool hasKnownRole = true}) {
    if (!hasKnownRole) return false;
    return role == UserRole.collector || role == UserRole.accountant;
  }
}
