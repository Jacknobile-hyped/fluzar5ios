plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.viralyst.online"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.viralyst.online"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        // For ffmpeg-kit-flutter
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
    // Required for ffmpeg-kit-flutter
    packaging {
        jniLibs {
            pickFirsts += listOf(
                "**/libc++_shared.so"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // AppCompat per flutter_stripe
    implementation("androidx.appcompat:appcompat:1.6.1")
    
    // Implementazione dell'SDK TikTok
    implementation("com.tiktok.open.sdk:tiktok-open-sdk-core:latest.release")
    implementation("com.tiktok.open.sdk:tiktok-open-sdk-auth:latest.release")   // per utilizzare l'API di autenticazione
    implementation("com.tiktok.open.sdk:tiktok-open-sdk-share:latest.release")  // per utilizzare l'API di condivisione
    
    // Google Mobile Ads SDK
    implementation("com.google.android.gms:play-services-ads:23.0.0")
}
