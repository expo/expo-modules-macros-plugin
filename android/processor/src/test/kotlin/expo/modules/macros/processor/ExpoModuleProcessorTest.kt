package expo.modules.macros.processor

import com.tschuchort.compiletesting.KotlinCompilation
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * End-to-end tests: run [ExpoModuleProcessor] over a fixture module and assert on both the generated
 * source and the compile outcome. Because the generated file is compiled against the core stubs in
 * the same run, a green compilation proves the generated DSL is valid Kotlin that type-checks — the
 * shape check the Swift suite does, with a real compile on top.
 */
class ExpoModuleProcessorTest {
  @Test
  fun `generates a definition for a module with sync, suspend and property members`() {
    val result = compileWithProcessor(
      fixture(
        "MyModule.kt",
        """
        package com.example

        import expo.modules.kotlin.modules.Module
        import expo.modules.kotlin.modules.ModuleDefinitionData
        import expo.modules.macros.ExpoModule
        import expo.modules.macros.JS

        @ExpoModule("MyModule")
        class MyModule : Module() {
          @JS fun greet(name: String): String = "hi ${'$'}name"
          @JS fun reset() {}
          @JS suspend fun work(id: String): Int = id.length
          @JS val version: String get() = "1.0"
          @JS var ready: Boolean = false

          override fun definition(): ModuleDefinitionData = expoModuleDefinition()
        }
        """.trimIndent()
      )
    )

    assertEquals(KotlinCompilation.ExitCode.OK, result.exitCode, result.messages)

    val generated = result.singleGeneratedFile().collapseWhitespace()
    assertContains(generated, "Name(\"MyModule\")")
    assertContains(generated, "Function(\"greet\") { name: kotlin.String -> this@expoModuleDefinition.greet(name) }")
    assertContains(generated, "Function(\"reset\") { -> this@expoModuleDefinition.reset() }")
    assertContains(generated, "AsyncFunction(\"work\") Coroutine { id: kotlin.String -> this@expoModuleDefinition.work(id) }")
    assertContains(generated, "Property(\"version\").get { this@expoModuleDefinition.version }")
    assertContains(
      generated,
      "Property(\"ready\").get { this@expoModuleDefinition.ready }.set { value: kotlin.Boolean -> this@expoModuleDefinition.ready = value }"
    )
  }

  @Test
  fun `module name defaults to the class name when omitted`() {
    val result = compileWithProcessor(
      fixture(
        "Defaulted.kt",
        """
        package com.example

        import expo.modules.kotlin.modules.Module
        import expo.modules.kotlin.modules.ModuleDefinitionData
        import expo.modules.macros.ExpoModule

        @ExpoModule
        class Defaulted : Module() {
          override fun definition(): ModuleDefinitionData = expoModuleDefinition()
        }
        """.trimIndent()
      )
    )

    assertEquals(KotlinCompilation.ExitCode.OK, result.exitCode, result.messages)
    assertContains(result.singleGeneratedFile(), "Name(\"Defaulted\")")
  }

  @Test
  fun `JS name override sets the wire name but keeps the kotlin call`() {
    val result = compileWithProcessor(
      fixture(
        "Renamed.kt",
        """
        package com.example

        import expo.modules.kotlin.modules.Module
        import expo.modules.kotlin.modules.ModuleDefinitionData
        import expo.modules.macros.ExpoModule
        import expo.modules.macros.JS

        @ExpoModule
        class Renamed : Module() {
          @JS("doWork") fun performWork() {}

          override fun definition(): ModuleDefinitionData = expoModuleDefinition()
        }
        """.trimIndent()
      )
    )

    assertEquals(KotlinCompilation.ExitCode.OK, result.exitCode, result.messages)
    assertContains(
      result.singleGeneratedFile().collapseWhitespace(),
      "Function(\"doWork\") { -> this@expoModuleDefinition.performWork() }"
    )
  }

  @Test
  fun `nullable parameter and property types are preserved`() {
    val result = compileWithProcessor(
      fixture(
        "Nullable.kt",
        """
        package com.example

        import expo.modules.kotlin.modules.Module
        import expo.modules.kotlin.modules.ModuleDefinitionData
        import expo.modules.macros.ExpoModule
        import expo.modules.macros.JS

        @ExpoModule
        class Nullable : Module() {
          @JS fun maybe(value: String?) {}
          @JS var note: String? = null

          override fun definition(): ModuleDefinitionData = expoModuleDefinition()
        }
        """.trimIndent()
      )
    )

    assertEquals(KotlinCompilation.ExitCode.OK, result.exitCode, result.messages)
    val generated = result.singleGeneratedFile().collapseWhitespace()
    assertContains(generated, "Function(\"maybe\") { value: kotlin.String? -> this@expoModuleDefinition.maybe(value) }")
    assertContains(generated, "set { value: kotlin.String? -> this@expoModuleDefinition.note = value }")
  }

  @Test
  fun `errors when @ExpoModule class does not extend Module`() {
    val result = compileWithProcessor(
      fixture(
        "NotAModule.kt",
        """
        package com.example

        import expo.modules.macros.ExpoModule

        @ExpoModule
        class NotAModule
        """.trimIndent()
      )
    )

    assertEquals(KotlinCompilation.ExitCode.COMPILATION_ERROR, result.exitCode, result.messages)
    assertTrue(result.messages.contains("must extend expo.modules.kotlin.modules.Module"), result.messages)
  }

  @Test
  fun `errors when a @JS member is private`() {
    val result = compileWithProcessor(
      fixture(
        "PrivateMember.kt",
        """
        package com.example

        import expo.modules.kotlin.modules.Module
        import expo.modules.kotlin.modules.ModuleDefinitionData
        import expo.modules.macros.ExpoModule
        import expo.modules.macros.JS

        @ExpoModule
        class PrivateMember : Module() {
          @JS private fun secret() {}

          override fun definition(): ModuleDefinitionData = ModuleDefinitionData()
        }
        """.trimIndent()
      )
    )

    assertEquals(KotlinCompilation.ExitCode.COMPILATION_ERROR, result.exitCode, result.messages)
    assertTrue(result.messages.contains("cannot be private"), result.messages)
  }
}
