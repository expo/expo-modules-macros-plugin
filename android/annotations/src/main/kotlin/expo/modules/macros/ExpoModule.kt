package expo.modules.macros

/**
 * Marks a class as an Expo module whose JS surface is generated at build time.
 *
 * The processor reads the [JS]-annotated members in the class body and generates a
 * `<ClassName>.expoModuleDefinition()` extension that builds the module's `ModuleDefinitionData`
 * via the existing `ModuleDefinition { … }` DSL. The author wires it in with a one-line
 * `definition()` override:
 *
 * ```
 * @ExpoModule("MyModule")
 * class MyModule : Module() {
 *   @JS fun greet(name: String): String = "hi $name"
 *   @JS var ready: Boolean = false
 *
 *   override fun definition() = expoModuleDefinition()
 * }
 * ```
 *
 * This is the Android counterpart of the Swift `@ExpoModule` macro. KSP cannot add the
 * `definition()` override to the class the way a Swift macro adds members to its type, so the
 * generated definition is exposed as an extension the author returns from `definition()`.
 *
 * @param name JS module name. Defaults to the class's simple name when blank.
 */
@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.SOURCE)
annotation class ExpoModule(val name: String = "")
