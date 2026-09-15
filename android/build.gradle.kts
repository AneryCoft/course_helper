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
            if (currentNamespace.isNullOrEmpty()) {
                androidExtension.namespace = project.group.toString()
            }
            // 强制设置 compileSdk 以支持新版本 API（permission_handler 需要 37）
            androidExtension.compileSdk = 37
            // 禁用 lint 检查
            androidExtension.lint {
                checkDependencies = false
                abortOnError = false
                checkReleaseBuilds = false
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

// Flutter 插件若为 AGP 9 内置 Kotlin 风格，其 build.gradle.kts 仅有顶层 kotlin {}
// 而未 apply kotlin-android，本项目使用 AGP 8.x，需在脚本编译前补上 Kotlin 插件。
subprojects {
    if (name != "app") {
        pluginManager.withPlugin("com.android.library") {
            if (!pluginManager.hasPlugin("org.jetbrains.kotlin.android")) {
                pluginManager.apply("org.jetbrains.kotlin.android")
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
