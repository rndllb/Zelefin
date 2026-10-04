import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

/**
 * Reads `app/google-services.json` (Firebase console → Project settings → Your apps) into
 * the string resources FirebaseInitProvider looks for, the same ones the google-services
 * Gradle plugin would generate. Without the file the app builds with push turned off.
 */
fun firebaseValues(packageName: String): Map<String, String>? {
    val file = file("google-services.json")
    if (!file.exists()) return null
    @Suppress("UNCHECKED_CAST")
    val root = JsonSlurper().parse(file) as Map<String, Any?>
    val project = root["project_info"] as? Map<String, Any?> ?: return null
    @Suppress("UNCHECKED_CAST")
    val clients = root["client"] as? List<Map<String, Any?>> ?: return null
    val client = clients.firstOrNull { entry ->
        val info = entry["client_info"] as? Map<*, *>
        (info?.get("android_client_info") as? Map<*, *>)?.get("package_name") == packageName
    } ?: return null
    val appId = (client["client_info"] as? Map<*, *>)?.get("mobilesdk_app_id") as? String ?: return null
    val apiKey = ((client["api_key"] as? List<*>)?.firstOrNull() as? Map<*, *>)?.get("current_key") as? String
        ?: return null
    return buildMap {
        put("google_app_id", appId)
        put("google_api_key", apiKey)
        put("gcm_defaultSenderId", project["project_number"].toString())
        put("project_id", project["project_id"].toString())
        (project["storage_bucket"] as? String)?.let { put("google_storage_bucket", it) }
    }
}

android {
    namespace = "app.zelefin.client"
    compileSdk = 35

    defaultConfig {
        applicationId = "app.zelefin.client"
        minSdk = 26
        targetSdk = 35
        versionCode = 10
        versionName = "0.1.0"

        val firebase = firebaseValues(applicationId!!)
        firebase?.forEach { (name, value) -> resValue("string", name, value) }
        buildConfigField("boolean", "PUSH_CONFIGURED", (firebase != null).toString())
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(project(":core"))
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("io.coil-kt:coil-svg:2.7.0")
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-ui:1.5.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.5.1")
    implementation("androidx.media3:media3-datasource-okhttp:1.5.1")
    implementation("dev.chrisbanes.haze:haze:1.5.4")
    implementation("dev.chrisbanes.haze:haze-materials:1.5.4")
    implementation("com.google.firebase:firebase-messaging:25.1.3")
    implementation("org.jellyfin.sdk:jellyfin-core:1.8.12")
    // Jellyfin's logger calls org.slf4j.LoggerFactory. Without the API on Android
    // the first sign-in request crashes with NoClassDefFoundError: Lorg/slf4j/LoggerFactory.
    implementation("org.slf4j:slf4j-api:2.0.17")
    implementation("org.slf4j:slf4j-nop:2.0.17")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
