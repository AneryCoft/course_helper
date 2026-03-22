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
    project.afterEvaluate {
        val androidExtension = project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        if (androidExtension != null) {
            val currentNamespace = androidExtension.namespace
            if (currentNamespace == null || currentNamespace.isEmpty()) {
                androidExtension.namespace = project.group.toString()
            }
        }
        
        // 强制使用 Flutter V2 embedding
        project.plugins.withId("com.android.library") {
            project.tasks.withType(JavaCompile::class.java).configureEach {
                doFirst {
                    options.compilerArgs.add("-Xlint:-deprecation")
                }
            }
        }
    }
    
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
