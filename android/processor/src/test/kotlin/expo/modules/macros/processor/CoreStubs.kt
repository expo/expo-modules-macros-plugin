package expo.modules.macros.processor

import com.tschuchort.compiletesting.SourceFile

/**
 * Minimal stand-ins for the `expo-modules-core` symbols the fixtures and the generated code touch.
 *
 * The real core isn't on the test classpath (these tests are shape-only, like the `apple/` suite),
 * but compiling the generated file against a faithful *shape* of the DSL is stronger than diffing
 * text: it proves the generated Kotlin is syntactically valid and type-checks against the DSL it
 * targets. The signatures mirror `ObjectDefinitionBuilder`/`PropertyComponentBuilder`/
 * `AsyncFunctionBuilder` closely enough for that check (reified `Function`/`AsyncFunction`/
 * `Property`, the `Coroutine` infix, a `Module` base with an abstract `definition()`).
 */
internal val coreStub = SourceFile.kotlin(
  "CoreStub.kt",
  """
  package expo.modules.kotlin.modules

  abstract class Module {
    abstract fun definition(): ModuleDefinitionData
  }

  class ModuleDefinitionData

  class ModuleDefinitionBuilder {
    fun Name(name: String) {}

    fun <R> Function(name: String, body: () -> R) {}
    fun <R, P0> Function(name: String, body: (P0) -> R) {}
    fun <R, P0, P1> Function(name: String, body: (P0, P1) -> R) {}

    fun <R> AsyncFunction(name: String, body: () -> R) {}
    fun <R, P0> AsyncFunction(name: String, body: (P0) -> R) = expo.modules.kotlin.functions.AsyncFunctionBuilder()
    fun AsyncFunction(name: String) = expo.modules.kotlin.functions.AsyncFunctionBuilder()

    fun Property(name: String) = PropertyComponentBuilder(name)
  }

  class PropertyComponentBuilder(val name: String) {
    fun <R> get(body: () -> R) = this
    fun <T> set(body: (T) -> Unit) = this
  }

  inline fun Module.ModuleDefinition(block: ModuleDefinitionBuilder.() -> Unit): ModuleDefinitionData {
    ModuleDefinitionBuilder().block()
    return ModuleDefinitionData()
  }
  """.trimIndent()
)

internal val asyncBuilderStub = SourceFile.kotlin(
  "AsyncFunctionBuilderStub.kt",
  """
  package expo.modules.kotlin.functions

  class AsyncFunctionBuilder

  infix fun <R> AsyncFunctionBuilder.Coroutine(block: suspend () -> R) {}
  infix fun <R, P0> AsyncFunctionBuilder.Coroutine(block: suspend (P0) -> R) {}
  infix fun <R, P0, P1> AsyncFunctionBuilder.Coroutine(block: suspend (P0, P1) -> R) {}
  """.trimIndent()
)

/** The real annotation sources, so fixtures can apply `@ExpoModule` / `@JS`. */
internal val annotationStubs = listOf(
  SourceFile.kotlin(
    "ExpoModuleAnnotation.kt",
    """
    package expo.modules.macros

    @Target(AnnotationTarget.CLASS)
    @Retention(AnnotationRetention.SOURCE)
    annotation class ExpoModule(val name: String = "")
    """.trimIndent()
  ),
  SourceFile.kotlin(
    "JSAnnotation.kt",
    """
    package expo.modules.macros

    @Target(AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY)
    @Retention(AnnotationRetention.SOURCE)
    annotation class JS(val name: String = "")
    """.trimIndent()
  )
)
