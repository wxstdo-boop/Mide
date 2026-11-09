// Puts the AGP classes on this script's compile classpath (the version itself is declared in
// settings.gradle.kts). Needed for the subprojects block at the bottom of this file.
plugins {
    id("com.android.application") apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some Flutter plugins hardcode a low compileSdk in their own build.gradle
// (wireguard_flutter_pro pins android-31). With AGP 9 that makes their
// checkReleaseAarMetadata task fail: their AndroidX dependencies require the consuming
// module to compile against a newer SDK. Raise compileSdk for every plugin module
// (all subprojects except :app) to the same value :app uses.
subprojects {
    if (name != "app") {
        val raiseCompileSdk: () -> Unit = {
            (extensions.findByName("android") as? com.android.build.api.dsl.LibraryExtension)
                ?.compileSdk = 36
        }
        // :app and some plugin projects can already be evaluated at this point
        // (see the evaluationDependsOn(":app") block above).
        if (state.executed) raiseCompileSdk() else afterEvaluate { raiseCompileSdk() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}