package expo.modules.macros.processor

import com.tschuchort.compiletesting.JvmCompilationResult
import com.tschuchort.compiletesting.KotlinCompilation
import com.tschuchort.compiletesting.SourceFile
import com.tschuchort.compiletesting.configureKsp
import com.tschuchort.compiletesting.kspSourcesDir
import java.io.File

/**
 * Runs [ExpoModuleProcessor] over a fixture plus the core/annotation stubs and returns the
 * compilation result. The KSP analog of the Swift macros' `assertExpansion` harness: process
 * in-process, then assert over the generated sources and/or the compile outcome.
 */
internal fun compileWithProcessor(vararg fixtures: SourceFile): JvmCompilationResult {
  val compilation = KotlinCompilation().apply {
    sources = annotationStubs + coreStub + asyncBuilderStub + fixtures.toList()
    configureKsp(useKsp2 = true) {
      symbolProcessorProviders += ExpoModuleProcessorProvider()
    }
    inheritClassPath = true
    messageOutputStream = System.out
  }
  return compilation.compile()
}

/** All files KSP generated during the run, read back as text for shape assertions. */
internal fun JvmCompilationResult.generatedKotlin(): Map<String, String> {
  val generatedDir = outputDirectory.parentFile.resolve("ksp/sources/kotlin")
  if (!generatedDir.exists()) {
    return emptyMap()
  }
  return generatedDir.walkTopDown()
    .filter { it.isFile && it.extension == "kt" }
    .associate { it.name to it.readText() }
}

/** Convenience: the single generated definition file's text, failing if there isn't exactly one. */
internal fun JvmCompilationResult.singleGeneratedFile(): String {
  val generated = generatedKotlin()
  check(generated.size == 1) { "expected exactly one generated file, got ${generated.keys}" }
  return generated.values.first()
}

internal fun fixture(name: String, contents: String): SourceFile = SourceFile.kotlin(name, contents)

/** Normalizes whitespace so shape assertions aren't brittle to indentation. */
internal fun String.collapseWhitespace(): String = trim().replace(Regex("\\s+"), " ")
