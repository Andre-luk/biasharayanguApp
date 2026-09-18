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
    // 🏷️ IDENTIFIANT OFFICIEL de l'application (APKPure, mises à jour…).
    //    ⚠️ NE JAMAIS le changer après la première publication : Android
    //    considérerait chaque version comme une NOUVELLE application.
    namespace = "cd.biasharayangu.app"
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
        applicationId = "cd.biasharayangu.app"
        minSdk = minSdkVersionUsed
        targetSdk = compileSdkVersionUsed
        // 📦 PUBLICATION (APKPure) — versionCode et versionName suivent le
        // pubspec.yaml (`version: 1.1.7+9` → versionName « 1.1.7 »,
        // versionCode 9). ⚠️ Le versionCode DOIT augmenter à chaque
        // publication (+10, +11…) sinon les mises à jour ne s'installent
        // pas par-dessus l'ancienne version (exigence Android).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        // Java 11 : cible du modèle Flutter 3.47 (8 étant marqué « obsolète »
        // par les outils Android récents).
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
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