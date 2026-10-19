import 'package:flutter_test/flutter_test.dart';
import 'package:store_collection_app/utils/catalog_actor_access.dart';

void main() {
  group('catalogActorFromProfile', () {
    test('accepts an active general manager or accountant', () {
      final collector = catalogActorFromProfile(
        uid: 'collector-1',
        profile: const {
          'role': 'collector',
          'isActive': true,
          'mustChangePassword': false,
          'name': 'المدير العام',
        },
      );
      final accountant = catalogActorFromProfile(
        uid: 'accountant-1',
        profile: const {
          'role': 'accountant',
          'isActive': true,
          'mustChangePassword': false,
        },
      );

      expect(collector.canManageCatalog, isTrue);
      expect(accountant.canManageCatalog, isTrue);
      expect(accountant.name, 'المحاسب');
    });

    test('rejects a profile that Firestore rules would reject', () {
      for (final profile in [
        const <String, dynamic>{
          'role': 'collector',
          'isActive': false,
          'mustChangePassword': false,
        },
        const <String, dynamic>{
          'role': 'accountant',
          'isActive': true,
          'mustChangePassword': true,
        },
        const <String, dynamic>{
          'role': 'manager',
          'isActive': true,
          'mustChangePassword': false,
        },
      ]) {
        expect(
          () => catalogActorFromProfile(uid: 'user-1', profile: profile),
          throwsA(isA<CatalogActorAccessException>()),
        );
      }
    });
  });
}
