plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.likhlo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        // ✅ CORRECT KOTLIN SYNTAX FOR DESUGARING
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.likhlo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            // ✅ CORRECT KOTLIN SYNTAX FOR SIGNING CONFIG
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // ✅ CORRECT KOTLIN SYNTAX FOR DEPENDENCIES
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}