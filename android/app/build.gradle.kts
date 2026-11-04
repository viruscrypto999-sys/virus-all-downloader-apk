plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // CORRECTED from Argon's draft: the real applicationId/namespace is
    // com.virus.virus_all_downloader (MainActivity lives in that package).
    // Argon's com.virus.alldownloader would have broken the build and
    // created a second app instead of upgrading v2.8.
    namespace = "com.virus.virus_all_downloader"
    // SDKs from the Flutter SDK (v2.8's proven setup): hardcoding 35 broke
    // :app:checkReleaseAarMetadata, a dependency's AAR needs a higher
    // compileSdk than 35, so let Flutter's defaults track the SDK.
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.virus.virus_all_downloader"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 109
        versionName = "2.10.0"
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
