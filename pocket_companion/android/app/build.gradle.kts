plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.pocket_companion"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.pocket_companion"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // DJI 加固 jar 的字节码无法通过 R8 full mode 的 IR 重写
            // （VerifyError: 构造器未调用超类构造器），必须关闭混淆收缩。
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // DJI Mobile SDK V4 的原生库不做 strip，避免老 SDK 与新 NDK strip 规则冲突
    packaging {
        jniLibs {
            doNotStrip += listOf(
                "**/libdjivideo.so",
                "**/libSDKRelativeJNI.so",
                "**/libFlyForbid.so",
                "**/libduml_vision_bokeh.so",
                "**/libyuv2.so",
                "**/libGroudStation.so",
                "**/libFRCorkscrew.so",
                "**/libUpgradeVerify.so",
                "**/libFR.so",
                "**/libdjifs_jni.so",
                "**/libsfjni.so",
                "**/libDJICommonJNI.so",
                "**/libDJICSDKCommon.so",
                "**/libDJIUpgradeCore.so",
                "**/libDJIUpgradeJNI.so",
                "**/libDJIWaypointV2Core.so",
                "**/libDJIMOP.so",
                "**/libDJISDKLOGJNI.so",
                "**/libDjiAffinity.so",
            )
        }
        resources {
            excludes += setOf(
                "META-INF/rxjava.properties",
                "META-INF/DEPENDENCIES",
                "META-INF/INDEX.LIST",
                "META-INF/io.netty.versions.properties",
            )
            // dji-sdk AAR 与 dji-sdk-provided jar 各带一份该资源，内容相同
            pickFirsts += "dji/thirdparty/okhttp3/internal/publicsuffix/publicsuffixes.gz"
        }
    }
}

dependencies {
    // 沉浸式状态栏（WindowInsetsControllerCompat 需要 core 1.5+）
    implementation("androidx.core:core-ktx:1.13.1")
    // DJI Mobile SDK V4（Osmo Mobile 3 手持云台支持；V5 不支持 OM 系列）
    implementation("com.dji:dji-sdk:4.18") {
        exclude(group = "com.dji", module = "library-anti-distortion")
    }
    // provided 仅参与编译（桩类字节码故意损坏，打包会 VerifyError）；
    // 运行时真实类由 CompanionApplication 里 Helper.install 解密注入，
    // 必须以 implementation 打进 APK（真机崩溃验证过，详见 docs/gimbal_follow_progress.md）。
    compileOnly("com.dji:dji-sdk-provided:4.18")
    // DJI AAR 内布局引用了 constraintlayout 属性，但 POM 未声明该依赖
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
}

flutter {
    source = "../.."
}
