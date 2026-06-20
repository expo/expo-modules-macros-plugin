package expo.modules.macros.processor

import com.google.devtools.ksp.processing.SymbolProcessor
import com.google.devtools.ksp.processing.SymbolProcessorEnvironment
import com.google.devtools.ksp.processing.SymbolProcessorProvider

/**
 * KSP entry point. Registered via `META-INF/services` so the Kotlin compiler discovers it, this is
 * the Android analog of the Swift `Plugin.swift` `providingMacros` list — the single place the
 * toolchain hooks into to run our processing.
 */
class ExpoModuleProcessorProvider : SymbolProcessorProvider {
  override fun create(environment: SymbolProcessorEnvironment): SymbolProcessor {
    return ExpoModuleProcessor(environment.codeGenerator, environment.logger)
  }
}
