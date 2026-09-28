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

    // Some plugins (e.g. permission_handler) target an SDK preview (android-37)
    // that may not be installed. Force every Android module to the stable
    // compileSdk that we know is present.
    project.plugins.withId("com.android.library") {
        project.extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            if (compileSdk == null || compileSdk!! > 36) {
                compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
