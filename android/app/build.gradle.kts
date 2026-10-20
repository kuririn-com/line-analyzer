import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val dartDefines = (project.findProperty("dart-defines") as? String)
    .orEmpty().split(',').filter { it.isNotEmpty() }.associate {
        val decoded = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
        decoded.substringBefore('=') to decoded.substringAfter('=', "")
    }
val androidAppId = dartDefines["ANDROID_ADMOB_APP_ID"].orEmpty()
val androidBannerId = dartDefines["ANDROID_ADMOB_BANNER_ID"].orEmpty()
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.kuririn.futaritalk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.kuririn.futaritalk"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = androidAppId.ifEmpty {
            "ca-app-pub-3940256099942544~3347511713"
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
        debug {
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
        }
        getByName("profile") {
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
        }
    }
}

// Fail before packaging rather than accidentally publishing sample IDs/debug keys.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release") }) {
        require(androidAppId.matches(Regex("ca-app-pub-[0-9]{16}~[0-9]{10}")) &&
            !androidAppId.startsWith("ca-app-pub-3940256099942544") &&
            androidAppId != "ca-app-pub-9003840415284448~5486911727") {
            "Set ANDROID_ADMOB_APP_ID to your Android AdMob app ID (not iOS/sample)."
        }
        require(androidBannerId.matches(Regex("ca-app-pub-[0-9]{16}/[0-9]{10}")) &&
            !androidBannerId.startsWith("ca-app-pub-3940256099942544") &&
            androidBannerId != "ca-app-pub-9003840415284448/3327652245" &&
            androidBannerId.substringBefore('/') == androidAppId.substringBefore('~')) {
            "Set ANDROID_ADMOB_BANNER_ID to your Android banner ID (not iOS/sample)."
        }
        require(listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
            !keystoreProperties.getProperty(it).isNullOrBlank()
        }) { "Configure android/key.properties with your approved upload key before release." }
    }
}

flutter {
    source = "../.."
}
