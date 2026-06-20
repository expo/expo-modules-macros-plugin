plugins {
  kotlin("jvm")
}

kotlin {
  jvmToolchain(17)
}

dependencies {
  implementation(project(":annotations"))
  implementation("com.google.devtools.ksp:symbol-processing-api:2.1.20-2.0.1")

  // `kotlin-compile-testing` (the maintained `kctfork` fork, which tracks modern KSP) is the
  // KSP analog of the Swift macros' `assertExpansion`: it runs the processor over fixture
  // sources in-process and lets the tests assert over the generated files. Like the `apple/`
  // tests, this verifies the *shape* of the generated code, not that it links against real core.
  testImplementation("dev.zacsweers.kctfork:core:0.7.0")
  testImplementation("dev.zacsweers.kctfork:ksp:0.7.0")
  testImplementation(kotlin("test"))
  testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
  testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.named<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>("compileTestKotlin") {
  compilerOptions {
    // `kotlin-compile-testing` exposes the compiler-plugin API, which is marked experimental.
    optIn.add("org.jetbrains.kotlin.compiler.plugin.ExperimentalCompilerApi")
  }
}

tasks.test {
  useJUnitPlatform()
}
