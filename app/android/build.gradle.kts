import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import com.android.build.gradle.LibraryExtension
import org.gradle.api.tasks.compile.JavaCompile

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

// home_widget 0.9.0 ships Kotlin bytecode with a JVM 11 target. Keep every
// Android library module aligned with the app's Java/Kotlin 17 target so a
// release build does not fail only after dependency compilation starts.
subprojects {
    afterEvaluate {
        extensions.findByType<LibraryExtension>()?.compileOptions?.apply {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
            }
        }
    }
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.glance") {
                useVersion("1.0.0")
                because("home_widget 0.9.0 declares glance-appwidget:1.+; newer alpha builds require Android API 37 and AGP 9.1.")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
