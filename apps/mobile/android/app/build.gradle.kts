plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) { apply(plugin = "com.google.gms.google-services"); apply(plugin = "com.google.firebase.crashlytics") }

android {
    namespace = "kz.joba.services_marketplace"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "kz.joba.services_marketplace"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val storeFilePath = System.getenv("JOBA_UPLOAD_KEYSTORE")
    signingConfigs {
        if (!storeFilePath.isNullOrBlank()) {
            create("storeRelease") {
                storeFile = file(storeFilePath)
                storePassword = System.getenv("JOBA_UPLOAD_STORE_PASSWORD")
                keyAlias = System.getenv("JOBA_UPLOAD_KEY_ALIAS") ?: "upload"
                keyPassword = System.getenv("JOBA_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            if (!storeFilePath.isNullOrBlank()) {
                signingConfig = signingConfigs.getByName("storeRelease")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies { implementation("androidx.biometric:biometric:1.1.0") }
