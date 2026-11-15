// 方方詞卡 for Windows: the Android app's own code (../android/app/src/main), run as a Windows program with Compose
// for Desktop. Built by install-windows.bat (it uses the Android project's Gradle: ..\android\gradlew.bat -p ..\windows).
pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}
dependencyResolutionManagement {
    repositories {
        mavenCentral()
        google()
    }
}
rootProject.name = "FangfangCards"
