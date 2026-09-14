import java.util.Properties
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}
val signingFile = rootProject.file("key.properties")
val signingProperties = Properties().apply {
    if (signingFile.exists()) signingFile.inputStream().use { load(it) }
}
android {
    namespace = "ai.ekkolearn.ekko_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "ai.ekkolearn.ekko_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (signingFile.exists()) {
            create("release") {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }
    buildTypes {
        release {
            // Missing credentials means unsigned release, never silent debug signing.
            signingConfig = if (signingFile.exists()) signingConfigs.getByName("release") else null
        }
    }
}
kotlin {
    compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 }
}
flutter { source = "../.." }
