// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing values come from environment variables first, falling back
// to android/local.properties (untracked). Neither source is committed.
// Required: PTIMER_UPLOAD_STORE_FILE, PTIMER_UPLOAD_STORE_PASSWORD,
// PTIMER_UPLOAD_KEY_ALIAS, PTIMER_UPLOAD_KEY_PASSWORD.
val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        FileInputStream(localPropertiesFile).use { load(it) }
    }
}

fun releaseSigningProperty(name: String): String? =
    System.getenv(name) ?: localProperties.getProperty(name)

val releaseStoreFile = releaseSigningProperty("PTIMER_UPLOAD_STORE_FILE")
val releaseStorePassword = releaseSigningProperty("PTIMER_UPLOAD_STORE_PASSWORD")
val releaseKeyAlias = releaseSigningProperty("PTIMER_UPLOAD_KEY_ALIAS")
val releaseKeyPassword = releaseSigningProperty("PTIMER_UPLOAD_KEY_PASSWORD")
val hasReleaseSigningConfig = !releaseStoreFile.isNullOrBlank() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank() &&
    !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "com.sangwook.ptimer"
    compileSdk = 37
    compileSdkMinor = 1

    defaultConfig {
        applicationId = "com.sangwook.ptimer"
        minSdk = 26
        targetSdk = 37
        versionCode = 5
        versionName = "0.8.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    if (hasReleaseSigningConfig) {
        signingConfigs {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeType = "PKCS12"
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            manifestPlaceholders["appLabel"] = "PTimer Debug"
        }
        release {
            manifestPlaceholders["appLabel"] = "@string/app_name"
            if (hasReleaseSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // Generates a LocaleConfig from the res/values-*/ locales present (en, ko)
    // so Android 13+ per-app language settings can list them (PTIMER-210).
    androidResources {
        generateLocaleConfig = true
    }

    testOptions {
        // Let android.util.Log calls no-op in JVM unit tests (used by the
        // persistence stores' quarantine signal) instead of throwing.
        unitTests.isReturnDefaultValues = true
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":core"))

    val composeBom = platform("androidx.compose:compose-bom:2026.06.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("androidx.datastore:datastore-preferences:1.1.1")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")

    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.6.1")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
