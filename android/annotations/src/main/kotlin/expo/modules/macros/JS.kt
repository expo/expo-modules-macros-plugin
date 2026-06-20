package expo.modules.macros

/**
 * Exposes a member of an [ExpoModule] class to JavaScript.
 *
 * Applied to functions and properties:
 * - `@JS fun f(…)` becomes a synchronous `Function`.
 * - `@JS suspend fun f(…)` becomes an asynchronous function returning a JS `Promise`.
 * - `@JS val p` / `@JS var p` becomes a `Property`; a `var` (or a `val`/`var` with a setter)
 *   additionally gets a JS setter, a `val` stays read-only.
 *
 * `@JS("name")` overrides the JS-visible name; otherwise the Kotlin member name is used.
 *
 * The Android counterpart of the Swift `@JS` macro. Like its Swift sibling it applies to both
 * functions and properties, not functions alone.
 *
 * @param name JS-visible name. Defaults to the member's Kotlin name when blank.
 */
@Target(AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY)
@Retention(AnnotationRetention.SOURCE)
annotation class JS(val name: String = "")
