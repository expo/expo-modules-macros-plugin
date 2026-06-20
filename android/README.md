# Android (KSP) macros

The Android counterpart of the Swift macros in [`../apple`](../apple). Where Apple uses Swift
compiler macros, Android uses a [KSP](https://kotlinlang.org/docs/ksp-overview.html) (Kotlin Symbol
Processing) processor: the author annotates ordinary Kotlin, and the processor generates the Expo
module's JS surface at build time.

## Why KSP, not a port of the Swift macros

Swift macros rewrite the annotated declaration in place; KSP can only **generate new files**. So this
is a parallel implementation that lands on the same author-facing API, not a translation of the macro
code. (Pika, the IR plugin core uses for `@OptimizedRecord`, is sealed and can't be extended, so the
processor is first-party and Pika-independent.)

## What's here

- **`annotations/`** — the markers an author applies: `@ExpoModule` on a `Module` class, `@JS` on its
  functions and properties.
- **`processor/`** — the KSP `SymbolProcessor`. It reads `@ExpoModule`/`@JS` and generates a
  `<Module>.expoModuleDefinition()` extension that builds the module's `ModuleDefinitionData` through
  the existing `ModuleDefinition { … }` DSL.

## Author API

```kotlin
@ExpoModule("MyModule")
class MyModule : Module() {
  @JS fun greet(name: String): String = "hi $name"
  @JS suspend fun work(id: String): Int = id.length
  @JS val version: String get() = "1.0"
  @JS var ready: Boolean = false

  // KSP can't add this override the way a Swift macro adds members to its type,
  // so the author wires the generated definition in with one line.
  override fun definition() = expoModuleDefinition()
}
```

The generated extension compiles against today's `expo-modules-core` with no core changes — the only
contract is that the generated DSL is valid against core, not that this tool shares core's compiler
version. A later step can add a core convention so `definition()` doesn't need to be written by hand.

## Building and testing

```sh
./gradlew :processor:test
```

Tests use [`kotlin-compile-testing`](https://github.com/ZacSweers/kotlin-compile-testing) (the KSP
analog of the Swift suite's `assertExpansion`): they run the processor over fixture modules and assert
on the generated source. The fixtures compile against minimal stubs of the core DSL, so a green run
proves the generated code is valid Kotlin that type-checks — it does **not** prove it links against
real core. Like the `apple/` suite, integration is only proven by building a real module against core.
