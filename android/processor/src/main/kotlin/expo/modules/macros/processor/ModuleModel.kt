package expo.modules.macros.processor

/**
 * The resolved description of one `@ExpoModule` class, built from the KSP symbols and consumed by
 * [DefinitionGenerator]. Keeping the generator off the KSP API makes the generated-code logic plain
 * to read and unit-testable in isolation.
 */
internal data class ModuleModel(
  /** Fully-qualified name of the annotated class, e.g. `com.example.MyModule`. */
  val qualifiedName: String,
  /** Package the generated file is emitted into (shared with the module so it can call the result). */
  val packageName: String,
  /** Simple class name, e.g. `MyModule`. */
  val simpleName: String,
  /** JS module name: the `@ExpoModule("…")` argument, or the simple class name when blank. */
  val jsName: String,
  val functions: List<FunctionModel>,
  val properties: List<PropertyModel>
)

/** A `@JS`-annotated function. */
internal data class FunctionModel(
  /** Kotlin function name — used to call it from the generated lambda. */
  val kotlinName: String,
  /** JS-visible name: the `@JS("…")` argument, or [kotlinName] when blank. */
  val jsName: String,
  /** Parameters in order, used to type and forward the generated lambda. */
  val parameters: List<ParameterModel>,
  /** True for `suspend fun` — generated as an `AsyncFunction … Coroutine { }` returning a Promise. */
  val isSuspend: Boolean
)

/**
 * One function parameter. The generated `Function`/`AsyncFunction` DSL infers each argument's
 * `TypeConverter` from the closure's parameter types via reified generics, so the lambda must spell
 * the type out — Kotlin can't infer a lambda parameter type from how the body uses it.
 */
internal data class ParameterModel(
  val name: String,
  /** Fully-qualified, nullability-preserving type, e.g. `kotlin.String`, `kotlin.Int?`. */
  val type: String
)

/** A `@JS`-annotated property (`val`/`var`). */
internal data class PropertyModel(
  /** Kotlin property name — used to read/write it from the generated accessors. */
  val kotlinName: String,
  /** JS-visible name: the `@JS("…")` argument, or [kotlinName] when blank. */
  val jsName: String,
  /** Fully-qualified, nullability-preserving type. Spelled on the generated setter's value param so
   *  the builder's reified `set` resolves the converter without relying on backward inference. */
  val type: String,
  /** True when the property is mutable (`var`, or a `val`/`var` with an explicit setter). */
  val isMutable: Boolean
)
