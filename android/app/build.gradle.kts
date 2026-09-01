import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    // Kotlin support comes from AGP's built-in Kotlin (android.builtInKotlin=true in
    // gradle.properties) — the standalone kotlin-android plugin is no longer applied.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials. Absent on a fresh clone and in CI — see the fallback in
// buildTypes.release below. Shape is documented in android/key.properties.example.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "io.github.glandais.autoride"
    // Pinned above `flutter.compileSdkVersion` (36): permission_handler_android is
    // compiled against API 37 and its AAR metadata refuses a lower compileSdk.
    // compileSdk is backward compatible; minSdk/targetSdk are unaffected.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses java.time APIs via desugaring).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.glandais.autoride"
        // Pinned rather than `flutter.minSdkVersion` (which resolves to 24): API 26 is the
        // support floor documented in CLAUDE.md and README.md, and pinning keeps a Flutter
        // SDK bump from silently moving it.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Both come from `version: X.Y.Z+N` in pubspec.yaml — never set them by hand.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug keys so `flutter run --release` works on a fresh clone
            // without secrets. publish_beta.sh refuses to build when key.properties is
            // missing, so a debug-signed bundle can never reach a store upload.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // R8/minification is deliberately OFF (T038 D6). Its failures are runtime-only —
            // a stripped class surfaces as a field crash, not a build error — so enabling it
            // requires a physical-device smoke test of trip detection, the foreground
            // notification, permission prompts and the map screen. Deferred until that test
            // can be run; see tasks/T038-android-release.md Step 5 for the rules to add.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

// jvmTarget must be set via the compilerOptions DSL (the old
// `kotlinOptions { jvmTarget = ... }` block was removed in Kotlin 2.4).
kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Backport of java.time / java.util APIs required by flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
