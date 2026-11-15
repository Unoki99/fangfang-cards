import org.jetbrains.compose.desktop.application.dsl.TargetFormat

// 方方詞卡 for Windows (Compose for Desktop). The screens, the dictionaries' code and the practice are the Android
// app's own files (../android/app/src/main/java), shared, not copied; only what's Android's own has a Windows version
// here (src/main/kotlin): the window, sound, the radio's player, the backup folder, the converters' runner (Node.js),
// and small stand-ins for the few Android classes the shared screens use (src/main/kotlin/shim: the clipboard, file
// pickers, the settings file, fonts).
plugins {
    kotlin("jvm") version "2.0.21"
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
    id("org.jetbrains.compose") version "1.7.3"
}

val shared = "../android/app/src/main"

sourceSets {
    main {
        kotlin {
            srcDir("$shared/java")
            // (Android's own: each has its Windows version in src/main/kotlin, with the same name, or isn't needed on
            // Windows; only the Android folder's copies are left out)
            val androidOnly = setOf("MainActivity.kt", "LookupActivity.kt", "LockWord.kt", "Radio.kt", "Backup.kt",
                "BrowserLink.kt", "WidgetBridge.kt", "JsRunner.kt", "ZhSpeech.kt")
            exclude { e ->
                val path = e.file.path.replace('\\', '/')
                path.contains("/android/app/src/main/java/") && (e.name in androidOnly || path.contains("/fangfang/widget/"))
            }
        }
        resources {
            // the English of the app's text, the converters (install/*.js) and the fonts; not the dictionaries (they're
            // made on this computer by install-windows.bat and read from %LOCALAPPDATA%\FangfangCards\data)
            srcDir("$shared/assets")
            srcDir("$shared/res/font")
            include("ui_en.json", "install/**", "*.ttf", "icon.png")
        }
    }
}

dependencies {
    implementation(compose.desktop.currentOs)
    implementation(compose.material3)
    implementation(compose.materialIconsExtended)
    // (the main thread for the shared code's coroutines: Swing's, the same version as the core library; see below)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-swing:1.9.0")
    // (Android has these built in)
    implementation("org.json:json:20240303")
    // (.xz: 華語's 《重編國語辭典修訂本》 comes packed that way)
    implementation("org.tukaani:xz:1.10")
    // mp3 (the recordings, 鬥拍字, radio streams) through Java Sound
    implementation("com.googlecode.soundlibs:mp3spi:1.9.5.4")
}

// (made with the Java install-windows.bat found, 17–23; the program runs on Java 17 or newer)
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
// every kotlinx-coroutines library at one version: a newer core (brought by Compose) with an older Swing part made
// "Module with the Main dispatcher is missing" when the program started
configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "org.jetbrains.kotlinx" && requested.name.startsWith("kotlinx-coroutines")) useVersion("1.9.0")
    }
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

compose.desktop {
    application {
        mainClass = "com.unoki99.fangfang.desktop.MainKt"
        jvmArgs += listOf("-Xss16m", "-Dfile.encoding=UTF-8", "-Dsun.stdout.encoding=UTF-8")
        nativeDistributions {
            targetFormats(TargetFormat.Msi)
            packageName = "FangfangCards"
            packageVersion = "1.0.0"
            description = "方方詞卡"
            vendor = "Unoki99"
            // (every part of Java: HTTPS, locales, sound)
            includeAllModules = true
            windows {
                iconFile.set(project.file("icon.ico"))
                menuGroup = "方方詞卡"
                shortcut = true
                perUserInstall = true
                upgradeUuid = "5b0b8f3e-8a4f-4c39-9a3e-3f2a9c1d7e41"
            }
        }
    }
}
