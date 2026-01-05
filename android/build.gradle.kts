allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            // JitPack - some native artifacts are published here
            url = uri("https://jitpack.io")
        }
        maven {
            // FFmpegKit GitHub Packages (public artifacts)
            url = uri("https://maven.pkg.github.com/tanersener/ffmpeg-kit")
            // GitHub Packages often requires authentication. Gradle will read credentials
            // from project properties (set in android/gradle.properties) or environment
            // variables `GITHUB_ACTOR` and `GITHUB_TOKEN`.
            credentials {
                username = (providers.gradleProperty("gpr.user").orNull ?: System.getenv("GITHUB_ACTOR")) as String?
                password = (providers.gradleProperty("gpr.key").orNull ?: System.getenv("GITHUB_TOKEN")) as String?
            }
        }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
