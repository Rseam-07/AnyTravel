import java.util.Properties
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val localSecrets = Properties().apply {
    val source = rootProject.file("secrets.properties")
    if (source.isFile) source.inputStream().use(::load)
}

val serviceDefaults = JsonSlurper().parse(rootProject.file("../Config/ServiceDefaults.json")) as Map<*, *>

fun buildConfigString(name: String, fallback: String = ""): String {
    val value = (localSecrets.getProperty(name) ?: System.getenv(name) ?: fallback)
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
    return "\"$value\""
}

android {
    namespace = "cn.anytravel.app"
    compileSdk {
        version = release(37) {
            minorApiLevel = 0
        }
    }

    defaultConfig {
        applicationId = "cn.anytravel.app"
        minSdk {
            version = release(31)
        }
        targetSdk {
            version = release(37)
        }
        versionCode = 18
        versionName = "0.8.3"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables.useSupportLibrary = true
        buildConfigField("String", "MAP_STYLE_URL", "\"https://tiles.openfreemap.org/styles/liberty\"")
        buildConfigField("String", "MAP_LIGHT_STYLE_URL", "\"https://tiles.openfreemap.org/styles/positron\"")
        buildConfigField("String", "MAP_DARK_STYLE_URL", "\"https://tiles.openfreemap.org/styles/dark\"")
        buildConfigField("String", "SERVICE_BASE_URL", buildConfigString("ANYTRAVEL_SERVICE_URL", serviceDefaults["serviceBaseURL"] as? String ?: ""))
    }

    buildTypes {
        debug {
            buildConfigField("String", "ROLLINGGO_API_KEY", buildConfigString("ROLLINGGO_API_KEY"))
            buildConfigField("String", "AMAP_API_KEY", buildConfigString("AMAP_API_KEY"))
            buildConfigField("String", "ZAI_API_KEY", buildConfigString("ZAI_API_KEY"))
        }
        release {
            isMinifyEnabled = false
            buildConfigField("String", "ROLLINGGO_API_KEY", "\"\"")
            buildConfigField("String", "AMAP_API_KEY", "\"\"")
            buildConfigField("String", "ZAI_API_KEY", "\"\"")
            // Public preview builds stay installable without distributing a
            // private signing key. They run with release compiler settings;
            // the GitHub release still labels this debug-key signature clearly.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

    packaging {
        resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}")
    }

    lint {
        lintConfig = file("lint.xml")
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
            isUniversalApk = true
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.08.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.19.0")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.11.0")

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.material3:material3")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")

    // OpenGL avoids the Vulkan SurfaceView rotation issue observed on some Android 12 devices.
    implementation("org.maplibre.gl:android-sdk-opengl:13.6.0")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.7.0")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
