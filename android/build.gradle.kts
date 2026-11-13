plugins {
    id("com.android.library")
}

group = "uz.plugin.audio_player"
version = "1.1.0"

android {
    namespace = "uz.plugin.audio_player"
    compileSdk = 37

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    lint {
        disable += listOf("AndroidGradlePluginVersion", "InvalidPackage", "GradleDependency", "NewerVersionAvailable")
    }
}

dependencies {
    val exoplayerVersion = "1.11.1"
    implementation("androidx.media3:media3-exoplayer:$exoplayerVersion")
    implementation("androidx.media3:media3-exoplayer-dash:$exoplayerVersion")
    implementation("androidx.media3:media3-exoplayer-hls:$exoplayerVersion")

    testImplementation("junit:junit:4.13.2")
}
