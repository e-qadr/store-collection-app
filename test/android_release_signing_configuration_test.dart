import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release uses guarded production signing and never debug', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('create("release")'));
    expect(gradle, contains('validateReleaseSigning()'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, contains('releaseSigningPropertiesFile.isFile'));
    expect(gradle, contains('configuredStore.isFile'));
  });

  test('release signing secrets are ignored and example has placeholders', () {
    final rootIgnore = File('.gitignore').readAsStringSync();
    final androidIgnore = File('android/.gitignore').readAsStringSync();
    final example = File('android/key.properties.example').readAsStringSync();

    expect(rootIgnore, contains('android/key.properties'));
    expect(rootIgnore, contains('**/*.jks'));
    expect(androidIgnore, contains('key.properties'));
    expect(androidIgnore, contains('**/*.keystore'));
    expect(example, contains('REPLACE_WITH_LOCAL_STORE_PASSWORD'));
    expect(example, contains('REPLACE_WITH_LOCAL_KEY_PASSWORD'));
    expect(example, isNot(contains('storePassword=changeit')));
  });
}
