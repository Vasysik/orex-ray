import java.net.URI
import java.security.MessageDigest
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(name: String): String? {
    val fromFile = keystoreProperties.getProperty(name)?.trim()
    if (!fromFile.isNullOrEmpty()) return fromFile
    val envName = "OREX_ANDROID_" + name
        .replace(Regex("([a-z])([A-Z])"), "\$1_\$2")
        .uppercase()
    return System.getenv(envName)?.trim()?.takeIf { it.isNotEmpty() }
}

fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().buffered().use { input ->
        val buffer = ByteArray(8192)
        while (true) {
            val read = input.read(buffer)
            if (read <= 0) break
            digest.update(buffer, 0, read)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}

val libV2rayVersion = "v26.6.27"
val libV2raySha256 = "7846eb7f663d1d8ae931034faa7a56cccc82d618c2d029198e6e91a77fd8de1e"
val libV2rayUrl = "https://github.com/2dust/AndroidLibXrayLite/releases/download/$libV2rayVersion/libv2ray.aar"
val libV2rayAar = file("libs/libv2ray.aar")

fun ensureLibV2ray() {
    if (libV2rayAar.exists() && sha256(libV2rayAar) == libV2raySha256) return

    libV2rayAar.parentFile.mkdirs()
    val partial = File(libV2rayAar.parentFile, "libv2ray.aar.part")
    partial.delete()

    logger.lifecycle("OrexRay: downloading Android Xray core $libV2rayVersion (about 56 MB)...")
    try {
        val connection = URI(libV2rayUrl).toURL().openConnection().apply {
            connectTimeout = 30_000
            readTimeout = 180_000
            useCaches = false
        }
        connection.getInputStream().buffered().use { input ->
            partial.outputStream().buffered().use { output -> input.copyTo(output) }
        }
    } catch (error: Exception) {
        partial.delete()
        throw GradleException(
            "OrexRay could not download Android Xray core from GitHub. " +
                "Check the internet connection and retry the build.",
            error,
        )
    }

    val actualSha256 = sha256(partial)
    if (actualSha256 != libV2raySha256) {
        partial.delete()
        throw GradleException(
            "Android Xray core checksum mismatch. Expected $libV2raySha256, got $actualSha256.",
        )
    }

    if (libV2rayAar.exists() && !libV2rayAar.delete()) {
        partial.delete()
        throw GradleException("Could not replace ${libV2rayAar.absolutePath}")
    }
    if (!partial.renameTo(libV2rayAar)) {
        partial.copyTo(libV2rayAar, overwrite = true)
        partial.delete()
    }
    logger.lifecycle("OrexRay: Android Xray core is ready.")
}

// Resolve the pinned AAR during Gradle configuration so every Android task sees
// the library before dependency resolution. The SHA-256 pin prevents a silent
// replacement of the release asset.
ensureLibV2ray()

val releaseStoreFile = signingValue("storeFile")
val releaseKeyAlias = signingValue("keyAlias")
val releaseKeyPassword = signingValue("keyPassword")
val releaseStorePassword = signingValue("storePassword")
val hasReleaseSigning = listOf(
    releaseStoreFile,
    releaseKeyAlias,
    releaseKeyPassword,
    releaseStorePassword,
).all { !it.isNullOrEmpty() }
if (hasReleaseSigning && !rootProject.file(releaseStoreFile!!).isFile) {
    throw GradleException(
        "Android release keystore was not found: " +
            rootProject.file(releaseStoreFile).absolutePath,
    )
}

val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    group = "verification"
    description = "Checks that Android release signing is configured."
    doLast {
        if (!hasReleaseSigning) {
            throw GradleException(
                "Android release signing is not configured. Create android/key.properties " +
                    "or set OREX_ANDROID_STORE_FILE, OREX_ANDROID_STORE_PASSWORD, " +
                    "OREX_ANDROID_KEY_ALIAS and OREX_ANDROID_KEY_PASSWORD.",
            )
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(validateReleaseSigning)
}

android {
    namespace = "ru.orex.ray"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "ru.orex.ray"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // Debug and release must be installable side by side. This also
            // prevents a locally signed debug build from blocking installation
            // of the real release package ru.orex.ray.
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(files(libV2rayAar))
}

flutter {
    source = "../.."
}
