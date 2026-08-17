import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val releaseSigningPropertiesFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties()
if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}

val releaseSigningRequiredKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)

fun validateReleaseSigning() {
    if (!releaseSigningPropertiesFile.isFile) {
        throw GradleException(
            "Android release signing is not configured. Copy " +
                "android/key.properties.example to android/key.properties and " +
                "provide an ignored production keystore.",
        )
    }
    val missing = releaseSigningRequiredKeys.filter {
        releaseSigningProperties.getProperty(it)?.trim().isNullOrEmpty()
    }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "Android release signing is incomplete. Missing key.properties values: " +
                missing.joinToString(", "),
        )
    }
    val configuredStore = rootProject.file(
        releaseSigningProperties.getProperty("storeFile").trim(),
    )
    if (!configuredStore.isFile) {
        throw GradleException(
            "Android release keystore does not exist at the configured storeFile path.",
        )
    }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { task -> task.name.contains("release", ignoreCase = true) }) {
        validateReleaseSigning()
    }
}

android {
    namespace = "com.storecollection.store_collection_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.storecollection.store_collection_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningPropertiesFile.isFile) {
                storeFile = rootProject.file(
                    releaseSigningProperties.getProperty("storeFile", ""),
                )
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
