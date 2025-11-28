import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

repositories {
    flatDir {
        dirs("libs")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") // For flutter_local_notifications // Workaround for: https://github.com/MaikuB/flutter_local_notifications/issues/2286
    implementation("androidx.core:core-ktx:1.17.0") // For Android Auto

    // 阿里云一键登录 SDK (官方)
    implementation(files("libs/auth_number_product-2.14.14-log-online-standard-cuum-release.aar"))
    implementation(files("libs/logger-2.2.2-release.aar"))
    implementation(files("libs/main-2.2.3-release.aar"))
}


// Workaround for https://pub.dev/packages/unifiedpush#the-build-fails-because-of-duplicate-classes
configurations.all {
    // Use the latest version published: https://central.sonatype.com/artifact/com.google.crypto.tink/tink-android
    val tink = "com.google.crypto.tink:tink-android:1.17.0"
    // You can also use the library declaration catalog
    // val tink = libs.google.tink
    resolutionStrategy {
        force(tink)
        dependencySubstitution {
            substitute(module("com.google.crypto.tink:tink")).using(module(tink))
        }
    }
}


android {
    namespace = "com.creativekoalas.automate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    require(keystorePropertiesFile.exists()) { "Missing key.properties" }
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))

    defaultConfig {
        applicationId = "com.creativekoalas.automate"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val alias = keystoreProperties["keyAlias"]?.toString()
            val pass  = keystoreProperties["keyPassword"]?.toString()
            val file  = keystoreProperties["storeFile"]?.toString()
            val store = keystoreProperties["storePassword"]?.toString()

            require(!alias.isNullOrBlank()) { "Missing keyAlias in key.properties" }
            require(!pass.isNullOrBlank()) { "Missing keyPassword in key.properties" }
            require(!file.isNullOrBlank()) { "Missing storeFile in key.properties" }
            require(!store.isNullOrBlank()) { "Missing storePassword in key.properties" }

            keyAlias = alias
            keyPassword = pass
            storeFile = file(file)
            storePassword = store
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
        }
        debug {
            // 一键登录 SDK 需要签名与阿里云控制台配置一致
            // debug 也使用 release 签名，避免 600017 错误
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}
