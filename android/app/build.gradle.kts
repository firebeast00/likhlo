plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.likhlo"

    // 👇 1. CHANGED TO 34
    compileSdk = 36

    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    defaultConfig {
        applicationId = "com.example.likhlo"

        // 👇 2. SET MIN SDK TO 21 AND TARGET TO 34
        minSdk = flutter.minSdkVersion
        targetSdk = 34

        // 👇 3. ENABLE MULTIDEX (Kotlin Syntax)
        multiDexEnabled = true

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // 👇 4. MULTIDEX DEPENDENCY (Kotlin Syntax)
    implementation("androidx.multidex:multidex:2.0.1")
}
