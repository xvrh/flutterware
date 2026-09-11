plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutterware_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutterware_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Fixtures for the launcher-icon viewer, not for anyone shipping this
    // sample. See ../../README.md for what each one is meant to expose; the
    // short version is that a product flavor and an icon set are not the same
    // thing, and this block is where they come apart.
    //
    // A bare `flutter run` here needs a --flavor: the pubspec deliberately
    // declares no `default-flavor` (the flutter tool applies that field on
    // every platform and breaks macOS/iOS launches — see pubspec.yaml).
    // Cockpit launches pair `free` per entry point in tool/flutterware.dart.
    flavorDimensions += "tier"
    productFlavors {
        // No res folder of its own: it builds with main's icons, and so has no
        // chip in the viewer at all. A flavor being absent from that row is
        // information, not an omission.
        create("free") { dimension = "tier" }

        // Configured in flutter_launcher_icons-beta.yaml and never generated.
        create("beta") { dimension = "tier" }

        // src/kiosk/res carries one density and nothing else, so most of what
        // it ships comes from main.
        create("kiosk") { dimension = "tier" }

        // Its icons are the AppIcon-partner catalog on iOS and, on Android,
        // main's — nothing is forked.
        create("partner") { dimension = "tier" }

        // Two flavors, one icon set. There is no product flavor called `pro`,
        // which is exactly why the viewer's chips are labelled icon sets: the
        // name comes from the directory below, not from this list.
        create("proMonthly") { dimension = "tier" }
        create("proYearly") { dimension = "tier" }
    }

    sourceSets {
        getByName("proMonthly").res.srcDir("src/pro/res")
        getByName("proYearly").res.srcDir("src/pro/res")
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
