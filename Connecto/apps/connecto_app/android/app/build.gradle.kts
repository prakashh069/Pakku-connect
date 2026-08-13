import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val isReleaseBuild = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) || it.contains("bundle", ignoreCase = true) }
if (isReleaseBuild && !keystorePropertiesFile.exists()) {
    throw GradleException("Production keystore properties missing (key.properties). Release builds must be properly signed and cannot use debug fallback.")
}

android {
    namespace = "com.connecto.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.connecto.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                val storeFileVal = keystoreProperties.getProperty("storeFile") ?: throw GradleException("storeFile missing in key.properties")
                storeFile = rootProject.file(storeFileVal)
                storePassword = keystoreProperties.getProperty("storePassword") ?: throw GradleException("storePassword missing in key.properties")
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: throw GradleException("keyAlias missing in key.properties")
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: throw GradleException("keyPassword missing in key.properties")
            }
        }
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    buildFeatures {
        buildConfig = true
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

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}
