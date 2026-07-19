allprojects {
    repositories {
        google()
        mavenCentral()
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

// Some plugins (e.g. receive_sharing_intent) ship their own build.gradle
// without pinning a JVM target, so their Kotlin compile task silently picks
// up whatever JDK is installed (17 on current CI images) while javac stays
// on its plugin-default 1.8/11 — causing a target-mismatch build failure.
// Force every subproject's javac + kotlinc onto the SAME Java 17 target so
// this can never happen again, no matter which plugin is added later.
subprojects {
    val configureJvmTarget = {
        extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let { android ->
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
            kotlinOptions {
                jvmTarget = JavaVersion.VERSION_17.toString()
            }
        }
    }
    // evaluationDependsOn(":app") above can force :app (or other modules in
    // the dependency chain) to already be evaluated by the time this runs —
    // calling afterEvaluate on an already-evaluated project throws. Guard both cases.
    if (project.state.executed) {
        configureJvmTarget()
    } else {
        afterEvaluate { configureJvmTarget() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
