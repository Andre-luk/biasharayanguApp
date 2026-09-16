// android/app/build.gradle.kts
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Chargement des informations de signature depuis key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun findIntProperty(name: String, default: Int): Int {
    val fromProject = project.findProperty(name)?.toString()?.toIntOrNull()
    val fromRoot = rootProject.findProperty(name)?.toString()?.toIntOrNull()
    return fromProject ?: fromRoot ?: default
}

val defaultCompileSdk = 36
val defaultMinSdk = 24
val compileSdkVersionUsed = findIntProperty("compileSdkVersion", defaultCompileSdk)
val minSdkVersionUsed = findIntProperty("minSdkVersion", defaultMinSdk)

android {
    namespace = "com.example.biashara_yangu"
    compileSdk = compileSdkVersionUsed

    // Configuration de la signature :
    //   • si `android/key.properties` existe, il désigne le keystore officiel
    //     (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`) ;
    //   • sinon (CI GitHub sans secrets), les valeurs restent vides et le
    //     buildType « release » retombe sur la signature DEBUG — l'APK reste
    //     installable et la compilation ne casse jamais.
    //   Voir docs/publication_app.md (§ signature) pour la mise en place.
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.biashara_yangu"
        minSdk = minSdkVersionUsed
        targetSdk = compileSdkVersionUsed
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    buildTypes {
        getByName("debug") {
            isMinifyEnabled = false
            isShrinkResources = false
            signingConfig = signingConfigs.getByName("debug")
        }

        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            // Signé avec le keystore officiel s'il est fourni, sinon avec la
            // clé debug (CI de test) — jamais d'échec de build.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.10.1")
}