# Android production signing

The Android release build never falls back to the debug key. Debug builds and
the normal VS Code Run configuration do not require release-signing files.

## Create the local keystore

Run this outside Git from the repository root. Replace the alias only in your
local command and enter strong, unique passwords when `keytool` prompts:

```powershell
New-Item -ItemType Directory -Force android\keystore
keytool -genkeypair -v `
  -keystore android\keystore\upload-keystore.jks `
  -keyalg RSA -keysize 4096 -validity 10000 `
  -alias store_collection_upload
```

Do not pass passwords on the command line because they can be retained in shell
history or process listings. Back up the keystore and passwords in the approved
secret store. Losing an upload key can prevent future application updates.

## Configure the ignored properties

```powershell
Copy-Item android\key.properties.example android\key.properties
```

Edit only the ignored `android/key.properties` and set:

```text
storeFile=keystore/upload-keystore.jks
storePassword=<local secret>
keyAlias=store_collection_upload
keyPassword=<local secret>
```

The path is relative to the `android` directory. Verify exclusion before use:

```powershell
git check-ignore -v android/key.properties android/keystore/upload-keystore.jks
```

## Build and verify

After the other release gates pass, build with the approved Dart defines:

```powershell
flutter build appbundle --release --dart-define-from-file=.env.release.json
```

If `key.properties`, a required property, or the keystore is absent, Gradle
stops with a release-signing error. Never copy the keystore or properties into
a deployment archive, build log, chat, or committed file.
