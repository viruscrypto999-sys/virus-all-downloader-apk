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
    compileSdk = 35
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.virus.virus_all_downloader"
        minSdk = 24
        targetSdk = 35
        versionCode = 108
        versionName = "2.9.0"
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
