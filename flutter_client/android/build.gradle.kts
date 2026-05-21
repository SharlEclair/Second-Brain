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
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
            compileSdkVersion(36)
        }
        if (project.name == "isar_flutter_libs") {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
                namespace = "dev.isar.isar_flutter_libs"
            }
        }
    }

    // Dynamically match Kotlin's JVM target to the Java compatibility of each subproject
    plugins.withId("kotlin-android") {
        project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            val androidExt = project.extensions.findByType(com.android.build.gradle.BaseExtension::class.java)
            val javaCompat = androidExt?.compileOptions?.targetCompatibility
            val target = when (javaCompat) {
                JavaVersion.VERSION_17 -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                JavaVersion.VERSION_11 -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
            }
            compilerOptions {
                jvmTarget.set(target)
            }
        }
    }

    configurations.all {
        resolutionStrategy {
            force("androidx.glance:glance:1.1.1")
            force("androidx.glance:glance-appwidget:1.1.1")
            force("com.google.android.libraries.places:places:3.5.0")
        }
    }
}



tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
