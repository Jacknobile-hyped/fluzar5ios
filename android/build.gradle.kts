allprojects {
    repositories {
        google()
        mavenCentral()
        // Repository per TikTok OpenSDK
        maven { url = uri("https://artifact.bytedance.com/repository/AwemeOpenSDK") }
        // Repository per ffmpeg-kit-flutter
        maven { url = uri("https://jitpack.io") }
        // Legacy repository - deprecated, using mavenCentral instead
        // jcenter()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Imposta il namespace mancante per il plugin flutter_app_badger (AGP 8+ richiede namespace)
subprojects {
    plugins.withId("com.android.library") {
        if (project.name == "flutter_app_badger") {
            extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                namespace = "fr.g123k.flutterappbadge.flutterappbadger"
            }
            // Rimuovi l'attributo package dall'AndroidManifest del plugin (non più supportato con AGP 8+)
            val fixManifestTask = tasks.register("fixFlutterAppBadgerManifest") {
                doLast {
                    val manifestFile = file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        var content = manifestFile.readText()
                        val original = content
                        // Rimuove package="..." dal tag <manifest>
                        content = content.replace(Regex("package=\"[^\"]+\""), "")
                        if (content != original) {
                            manifestFile.writeText(content)
                            println("[flutter_app_badger] AndroidManifest.xml: rimosso attributo package")
                        }
                    }
                }
            }
            // Esegui il fix prima della build del modulo
            tasks.matching { it.name == "preBuild" }.configureEach {
                dependsOn(fixManifestTask)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
