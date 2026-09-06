# Expo Modules v2 — Android / Kotlin parity

- **Status:** Draft companion to `expo-modules-v2.md` (Apple/Swift). Grounded against
  `expo/main` Kotlin core, not yet prototyped.
- **Author:** Tomasz Sapeta
- **Created:** 2026-06-11
- **Scope:** Android/Kotlin annotation-processing path for the same author-facing model
  the Swift macros deliver (`apple/Sources/ExpoModulesMacros`). Read alongside
  `expo-modules-v2.md` — that doc owns the *design*; this one owns the *Android mapping*.

## TL;DR — can we expose the same API?

**Yes.** The author-facing API (what someone types) can be the same on both platforms, and
that's the whole point — same annotations, same mental model, same generated TypeScript:
`@ExpoModule` classes, `@JS` on functions/properties, `@Record` with fields-by-default and
inferred requiredness, `@SharedObject` (instance + static), typed events, `@Union`, the
typed view-props object, and `async` → JS `Promise`. Field requiredness lines up because
Swift optional/default and Kotlin nullable/default map to the same rule.

Three asterisks — none of them break the *API*; they're behavioral or syntactic:

1. **Async behaves differently underneath.** Same spelling, same `Promise` to the JS
   caller, but iOS runs synchronously to the first suspension (actor isolation) while
   Kotlin dispatches via coroutines. Identical API, different timing semantics.
2. **Unions are spelled per-language.** Swift `enum` with associated values vs Kotlin
   `sealed interface` — same `@Union` annotation and same `A | B | C` TS, just idiomatic
   native declaration kinds.
3. **One Android visibility wrinkle.** A `@JS` member may need to be `internal`+ (not
   `private`), because the KSP-generated companion sits outside the class. Settle in the
   prototype; doesn't change the annotation surface.

What is **not** shared is the *implementation*: a parallel KSP processor, not a port of the
Swift macros, because KSP generates files instead of rewriting declarations. That's an
implementation cost, not an API limitation. The rest of this doc works through the mapping.

## Why this companion exists

`expo-modules-v2.md` lists "Android / Kotlin parity — an equivalent annotation-processing
path (KSP) so a single conceptual module surface generates both platforms' definitions
and shared TS types" as a *Further idea*. This doc works out whether that's real and what
it costs, grounded in the actual Kotlin core (paths under
`…/expo/main/packages/expo-modules-core/android/src/main/java/expo/modules/kotlin`).

**The headline finding:** the author-facing model ports cleanly, and the compile-time
strategy is **already shipping on Android** in a narrow form. Expo's Kotlin type system
is already wired through **Pika** (`io.github.lukmccall.pika`), a **KSP-based
compile-time introspection** library used today for `@OptimizedRecord`/
`@OptimizedComposeProps` — it generates `PIntrospectionData` so the runtime can skip
`kotlin.reflect`. So "a KSP processor that reads annotations and emits compile-time
binding data instead of reflecting at runtime" is not a leap on Android; it's an
*extension of a pattern that already exists in core* (`types/typeDescriptorOf.kt:32`
already prefers the Pika `ctTypeDescriptorOf<T>()` path and falls back to `typeOf<T>()`).

## The fundamental tooling difference (read this first)

Swift compiler macros and KSP are **not the same kind of tool**, and every section below
is shaped by this:

| | Swift macros (iOS) | KSP (Android) |
|---|---|---|
| Mechanism | Rewrite/attach **in place** on the annotated decl (member/peer/accessor) | **Generate new files only** — cannot touch existing source |
| Sees | SwiftSyntax (unresolved syntax) | Resolved symbols (`KSClassDeclaration`, resolved `KSType`) — *more* type info |
| Output | New members on the same type, conformances, peers | Separate `.kt` files (new top-level/extension/companion decls) |
| Runs | Per-decl during type-check, sandboxed (no FS/network) | Gradle build step, **has** FS access (can emit TS as a side artifact) |

Two consequences dominate:

1. **KSP can't rewrite the user's declaration.** Every iOS trick that *stamps something
   onto the author's own member* must be redesigned as *generate a companion*. Concretely
   affected: the `@JS` peer conformance-assertion (iOS attaches it to the member);
   `@JavaScriptActor` stamping (the actor-isolation that makes async run sync-to-first-
   suspension — **no Kotlin equivalent at all**); `@Event` as an accessor macro rewriting
   a stored `var` into a computed property (KSP can't, so the event shape must change).
2. **KSP sees resolved types, which is actually easier for the binding work.** A Swift
   macro only sees `a: Double` as syntax and must trust it; KSP resolves `KSType` so it
   *knows* the type, nullability, defaults, and annotations without guessing. The
   per-argument typed converter selection that iOS phase 2 does at expansion time is
   *more* reliable on Android.

So: **the model ports; the mechanism does not.** This is a parallel implementation that
lands on the same author API, not a translation of the macro code.

## Prior art already in core (the Android equivalent of "the macro knows the type")

Before designing anything, note what core already does so we don't reinvent it:

- **Pika / KSP is live.** `expo-modules-core`'s gradle plugin pins a KSP version
  (`ExpoModulesCorePlugin.gradle:20-39`) and the type system imports Pika throughout
  (`types/JSTypeConverterHelper.kt`, `types/ReturnType.kt`,
  `types/descriptors/TypeDescriptor.kt`, `records/RecordTypeConverter.kt`). Modules opt
  into KSP today (`expo-image`, `expo-updates`, `expo-app-metrics`).
- **`@OptimizedRecord` is the proof of concept** — the Android analog of the iOS
  `@OptimizedFunction` POC. It's a `@Target(CLASS)` annotation
  (`types/OptimizedRecord.kt`) whose Pika-generated introspection lets
  `RecordTypeConverter` skip the reflective `KClass.memberProperties` /
  `KProperty.javaField` walk. v2 generalizes the *same idea* from records to the whole
  `@JS` surface.
- **The runtime already has a clean direct-binding seam.** `JSDecoratorsBridgingObject`
  (`jni/decorators/JSDecoratorsBridgingObject.kt`) exposes `registerSyncFunction`,
  `registerAsyncFunction`, `registerProperty`, `registerConstant` — each takes a
  `JNIFunctionBody` closure + an `Array<ExpectedType>` of C++ type codes. This is the
  Android counterpart of iOS's `JavaScriptObject.setProperty`/`defineProperty`. A
  generated binding has a real, existing entry point to target.

This is why Android is in some ways *better positioned* than iOS for phase 2: the
"describe-then-interpret" vs "bind-directly" seam (`registerSyncFunction` taking a
closure) already exists, and a compile-time-data pattern (Pika) is already accepted.

---

# Phase mapping

The three iOS phases map onto Android, but the **risk profile is different**: Phase 1 and
Phase 3 are the safe, high-value targets; Phase 2's *story* changes because the cost model
is JNI/JVM, not Swift/JSI.

## Phase 1 — DSL coverage (KSP generates `ModuleDefinition { … }`)

**iOS:** the macro emits the `*Definition` element tree onto the type.
**Android:** a KSP processor reads the annotations and **generates a `.kt` file** that
builds the existing `ModuleDefinitionData` via the current DSL
(`modules/ModuleDefinitionBuilder.kt`, `objects/ObjectDefinitionBuilder.kt`).

The existing Kotlin DSL is a near-perfect target — same grammar family as iOS:

- `Name(name)` (`ModuleDefinitionBuilder.kt:73`)
- `Function(name) { … }` / `AsyncFunction(name) { … }` (reified-generic builders in
  `objects/ObjectDefinitionBuilder.kt`, up to 8 params via `FunctionBuilder.kt:34`)
- `Property(name) { get { … } set { … } }` → `PropertyComponent` (getter+setter as two
  `SyncFunctionComponent`s, `objects/PropertyComponent.kt`,
  `objects/PropertyComponentBuilder.kt`)
- `Events("a", "b")` (`ObjectDefinitionBuilder.kt:438`)
- `View(MyView::class) { Prop(name) { v, p -> } … }` (`views/ViewDefinitionBuilder.kt:92`)
- `Class(name) { … }` for shared objects (`ModuleDefinitionBuilder.kt:181`)

**How the generated code attaches to the user's class.** Because KSP can't add a method
*to* `class MyModule`, it generates an **extension** or a **separate definition provider**.
Two viable shapes (pick during prototype):

```kotlin
// authored
@ExpoModule class MyModule {
  @JS fun greet(name: String): String = "hi $name"
  @JS var ready: Boolean = false
}

// KSP-generated  MyModule_ExpoDefinition.kt
internal fun MyModule.synthesizedDefinition(): ModuleDefinitionData =
  ModuleDefinition {
    Name("MyModule")
    Function("greet") { name: String -> greet(name) }
    Property("ready").get { ready }.set { v: Boolean -> ready = v }
  }
```

The author's base `Module.definition()` (`modules/Module.kt:68`) either calls the
generated extension, or core gains a tiny convention: if a generated
`<ClassName>_ExpoDefinition` exists, `ModuleHolder` uses it. (This is the Android version
of the iOS `_synthesizedDefinition()` core-rename dependency — same coupling, different
lookup mechanism.)

**Per-attribute mapping for Phase 1:**

### `@ExpoModule`
KSP `SymbolProcessor` visits `@ExpoModule` classes, collects `@JS`/`@Event` members
(resolved symbols — names, param `KSType`s, nullability, `suspend`, `static`/companion,
defaults all available), and emits the `ModuleDefinition { … }` builder. The
`views = [...]`/`classes = [...]` args become generated `View(...)`/`Class(...)` entries.
Unlike iOS, **no inheritance synthesis is needed** — the author still `: Module`
(or core adds an interface later); KSP just generates the definition.

### `@JS` (functions & properties)
- `@JS fun f(...)` → `Function("f") { … }`; `@JS suspend fun f(...)` →
  `AsyncFunction`/suspend component (see async below). `@JS("name")` overrides.
- `@JS val/var p` → `Property("p").get { p }` plus `.set { p = it }` **iff settable** —
  Kotlin makes this *cleaner than Swift*: `var` → settable, `val` → read-only, decided
  syntactically with no accessor analysis. Visibility (`private`) doesn't gate JS exposure
  for the same reason as iOS: the generated accessor must be able to read it — **caveat**,
  unlike a Swift macro expanding *inside* the type, a KSP-generated extension is *outside*
  the class, so it **can't see `private` members**. So either: (a) require `@JS` members to
  be at least `internal`, or (b) generate into the same module/package and rely on
  `internal` visibility. This is a real divergence from iOS to settle in the prototype.
- **The conformance assertion** iOS emits as a peer becomes either a KSP **diagnostic**
  (`KSPLogger.error` at processing time — strictly better UX, fails the build with a
  precise message on the user's decl) or generated `require`-style checks. KSP diagnostics
  are the natural and superior form here.

### Async — the biggest semantic divergence
iOS: `async` Swift func, stamped `@JavaScriptActor`, runs **synchronously on the JS thread
until the first real suspension** (SE-0306 actor-reentrancy guarantee). **Kotlin has no
analog.** Android async is one of:
- `SuspendFunctionComponent` (`functions/SuspendFunctionComponent.kt`) — author writes
  `@JS suspend fun`, KSP emits a suspend component that `launch`es on a `CoroutineScope`
  (queue-selected: `MAIN`/`DEFAULT`/custom) and resolves a `Promise`. **This already
  exists and is the right target.**
- The older `AsyncFunctionWithPromiseComponent` (explicit `Promise` arg) — drop it, same
  as iOS drops the Promise-param form.

**Decision:** `@JS suspend fun` → JS `Promise`, via `SuspendFunctionComponent`. **Do not
promise iOS's "synchronous to first suspension" semantics** — Kotlin coroutines dispatch
per the chosen dispatcher; document the difference rather than fake it. This is acceptable
(JS callers `await` either way) but it is a genuine behavioral difference between platforms
that the shared TS surface hides.

### `@Record`
iOS `@Record` synthesizes compile-time field/key pairs replacing the `Mirror` walk.
Android already has the runtime (`records/Record` marker, `@Field`, `@Required`,
`RecordTypeConverter`) **and** the compile-time path (`@OptimizedRecord` + Pika). So the
v2 `@Record` annotation on Android = **the existing `@OptimizedRecord` story, made the
default and given inference**:
- Every property is a field — but today Android requires explicit `@Field`
  (`RecordTypeConverter.kt` only picks up `findAnnotation<Field>()`). v2 = **field-by-
  default** (drop the per-field `@Field` requirement; KSP sees every property).
- **Requiredness inference** matches iOS: non-null + no default → required; has default →
  optional; nullable `T?` → nullable+optional. Today Android uses an explicit `@Required`
  annotation; v2 infers it from the Kotlin declaration (KSP resolves nullability and sees
  default values). `@Field("jsKey")` stays as the name-override escape hatch.
- The reflective `KClass.memberProperties`/`javaField.set` path
  (`RecordTypeConverter.kt:46-150`) is replaced by generated field descriptors — exactly
  what `@OptimizedRecord` + Pika already do; v2 makes it automatic.

### `@Union`
iOS: `@Union` on an enum with associated-value cases; structural decode in declaration
order; `Either` kept for inline 2-type. Android has `Either` (`apifeatures`, the
deprecated `@EitherType`) and a `DynamicEitherType`-equivalent trial decode. Kotlin's
analog of "enum with typed payloads" is a **sealed class/interface** (each subtype carries
its typed payload), not an `enum class` (Kotlin enum cases can't carry distinct
per-case types). So:
- `@Union` on a **`sealed interface`/`sealed class`**; KSP reads the subtypes and emits an
  ordered, typed decode into the matching subtype — the Android counterpart of the iOS
  enum-case decode, and it kills the `Either` `try?`-each-candidate trial loop the same way.
- `Either` stays for inline 2-type.

### Views — same hard core dependency as iOS, different runtime
iOS phase 1 views are **gated on a core props-object contract that doesn't exist yet**
(`Props(_:)` element, `var props`, `onViewPropsChanged(oldProps:)`). Android is in the
*same position but further*: today views are per-prop closures
(`Prop(name) { view, prop -> }`, `views/ConcreteViewProp.kt`) and there is **no unified
props object** at all on Android. So `@ViewProps`/`@ExpoView` on Android need the **same
core runtime work iOS needs**, ported to Kotlin:
- A typed props type registered for an `ExpoView` (a `Props(MyProps::class)` element or a
  `View<Props, T>` overload).
- `var props: Props` always-current + `onViewPropsChanged(oldProps: Props?)` override,
  with core setting `props` before the callback.
- **Event dispatch by name**, not by mutating a stored closure. Android's current view
  events use the `ViewEventDelegate`/`EventDispatcher` property-delegate
  (`viewevent/ViewEventDelegate.kt`, `View.EventDispatcher<T>()`), discovered per-view.
  A `data class`/value props object can't carry a mutated delegate, so — exactly like iOS —
  the generated event must *call into* a core dispatcher keyed by name.

**Struct-vs-class on Android:** iOS's `@ViewProps struct` (value) vs `class` (SwiftUI
observable) distinction maps to Kotlin `data class` (value props, the common case) vs a
class implementing an observable contract (Jetpack Compose path — note core already has
`@OptimizedComposeProps`, so a Compose props story exists to align with). The "wrong kind
is a compile error via the conformance" trick is **weaker on Android** — KSP can see
`class` vs `data class` and emit a *diagnostic* directly (better than iOS's conformance
trick), rather than relying on a protocol bound to fail.

### `@SharedObject`
iOS synthesizes `_synthesizedClassDefinition()` / `_decorateSharedObject`. Android already
has `Class(name) { … }` (`ModuleDefinitionBuilder.kt:181`), `SharedObject`
(`sharedobjects/SharedObject.kt`), the `SharedObjectRegistry` native↔JS id pairing
(`sharedobjects/SharedObjectRegistry.kt`, `SharedObjectTypeConverter`). So `@SharedObject`
on Android = KSP generates the `Class(name) { Constructor(...); Function(...);
Property(...) }` block from `@JS`/`@JS static`(companion)/`init` members. Instance vs
static maps to **instance members vs `companion object` members** (Kotlin's static analog).
Events use the existing `SharedObject.emit(event, payload)` (`SharedObject.kt`), which is
already typed-payload-friendly — closer to done than iOS was before core's `EventEmitter`
work.

## Phase 2 — Performance: the story changes (this is where the analogy breaks)

iOS phase 2's win = generated Swift binds directly into the JS object via JSI, decoding
each arg by its **static Swift type** with no `[Any]`/`toTuple` boxing, measured ~2.2×
over the DSL.

On Android the win is **real but differently shaped**, for three reasons:

1. **There is no `[Any]`/`toTuple` to delete.** The Kotlin path already crosses JNI as an
   `Array<Any?>` and converts per-arg via `AnyType.convert` →
   `TypeConverterProvider.obtainTypeConverter` (`functions/AnyFunction.kt:67`,
   `types/AnyType.kt`). The expensive part isn't a tuple reinterpret; it's **runtime
   converter resolution + `kotlin.reflect`** (for records: `memberProperties`,
   `KProperty.returnType`, `javaField.set`).
2. **The "skip reflection" win is the one that ports — and core already does it.** The
   Android phase-2 win is: KSP knows each arg's resolved `KSType`, so it emits the
   concrete `TypeConverter` selection (or a direct primitive read) at **compile time**,
   eliminating the lazy `obtainTypeConverter` lookup and the reflective record walk. This
   is *exactly* what Pika + `@OptimizedRecord` already prove for records; phase 2
   generalizes it to functions/properties/unions. The existing `getCppRequiredTypes()`
   (`ExpectedType` arrays) are already emitted per-component, so the JNI registration
   surface needs no change — just statically-resolved converters behind it.
3. **No `@JavaScriptActor` no-hop guarantee exists** to lean on for async, so there is no
   "synchronous to first suspension" perf/semantics win to claim. Async stays
   coroutine-dispatched.

So phase 2 on Android = **make every generated component use compile-time converters
(Pika-style) by default**, the way iOS makes every function direct-JSI by default. The
runtime seam (`JSDecoratorsBridgingObject.registerSyncFunction(... JNIFunctionBody ...)`)
already binds a closure directly — the generated `JNIFunctionBody` just contains a
statically-resolved decode-call-encode body instead of one that calls
`convertArgs`/`obtainTypeConverter` dynamically.

**`@OptimizedFunction`/`@OptimizedRecord` are the Android POC, same end state.**
`@OptimizedRecord` (records) is the shipped proof that compile-time introspection beats
reflection on Android; v2 makes it the default for the whole `@JS` surface and the
explicit opt-in annotation becomes redundant — mirroring the iOS plan retiring
`@OptimizedFunction`.

**What phase 2 does NOT get on Android that iOS does:** the elimination of an `Any` box.
JNI hands Kotlin `Array<Any?>`; you can avoid *reflective converter resolution* but the
boxed-`Any?` argument array is the JNI ABI. A deeper win (specialized JNI entry points per
arity/type) is a much larger core/C++ change and is **out of scope** — note it explicitly
so the perf story isn't oversold as "same as iOS."

## Phase 3 — TypeScript generation (the strongest case for doing this at all)

iOS phase 3 **cannot live in the macro** (sandbox) and is a separate source-parser
(`expo-type-information`, SourceKitten-based) — today **Swift-only** (confirmed: the
package has `src/swift/sourcekittenTypeInformation.ts` and no Kotlin parser).

Android has **two routes**, and the second is the prize:

1. **KSP-emitted type info.** Because KSP *does* have filesystem access (unlike the Swift
   macro sandbox), the same processor that generates the binding can **also emit a TS/JSON
   type artifact** as a build output. This is *easier* than iOS, where a wholly separate
   SourceKitten tool is required.
2. **Unified cross-platform generation (the goal).** The ideal end state from the iOS doc's
   Further-ideas bullet: **one TS surface generated from both platforms**. Two
   sub-options:
   - Both KSP (Android) and `expo-type-information` (iOS) emit a common intermediate
     type-info JSON; a small merge step produces the shared `.d.ts` and **diffs the two**
     (flagging when a module's Swift and Kotlin surfaces disagree — a real, valuable
     cross-platform lint that neither platform can do alone).
   - Or teach `expo-type-information` a Kotlin front end. The agent confirmed it has none
     today, so this is net-new; the KSP-emits-its-own-info route is lower-friction since
     KSP already has resolved types in hand.

Phase 3 is where "single conceptual module surface, shared TS types" actually pays off, and
Android is *better* suited to it than iOS (KSP can write files; the macro can't).

---

# Cross-cutting: what ports, what doesn't

**Ports cleanly (the model):**
- Author API: annotated class, `@JS` members, fields-by-default records with inferred
  requiredness, typed events, `@Union`, typed view props object. This is the whole point —
  symmetric authoring + shared TS.
- Field-requiredness inference (Kotlin nullability + default params give the same 3-way
  table as Swift).
- The compile-time-over-reflection performance thesis (Pika/`@OptimizedRecord` already
  prove it on Android).
- The direct-binding seam (`JSDecoratorsBridgingObject` ≈ `JavaScriptObject.setProperty`).
- Shared-object id pairing, events (`SharedObject.emit` is already typed-payload-shaped).

**Does NOT port (the mechanism), needs redesign:**
- **In-place declaration rewriting.** KSP generates companions; it can't stamp the user's
  member. Affects: `@JS` peer assertion (→ KSP diagnostic, *better*), `@Event` accessor
  rewrite (→ generated wiring or a delegate, *different shape*), and `private`-member
  access (a generated extension can't see `private` — iOS expands *inside* the type and
  can; **settle the visibility rule in the prototype**).
- **`@JavaScriptActor` / actor-isolation async semantics.** No Kotlin equivalent. Async =
  `suspend fun` → coroutine → Promise; **no "sync to first suspension" guarantee**.
- **The `Any`-box-elimination half of phase 2.** JNI ABI is `Array<Any?>`; you remove
  reflective resolution, not the box.
- **`enum`-with-payload unions** → Kotlin `sealed interface`, not `enum class`.

**Core dependencies (Android) — same coupling risk the iOS doc flags repeatedly:**
- Generated definition lookup (`<Class>_ExpoDefinition` convention or
  `ModuleHolder`/`Module.definition()` hook) — the Android analog of the iOS
  `_synthesized…` rename. Every stage needs a paired core PR; green processor tests do not
  prove integration.
- **Unified view-props runtime on Android does not exist** (today: per-prop closures, no
  props object) — `@ViewProps`/`@ExpoView` are gated on the same core work iOS needs,
  ported to Kotlin (props-object decode, `onViewPropsChanged`, name-keyed event dispatch).
- `@JS static var` ↔ a companion-object/static property binding (iOS's `StaticProperty`
  gap has an Android sibling).
- Field-by-default records: core's `RecordTypeConverter` must stop *requiring* `@Field`
  (or the generated descriptor must supply all fields).

# Recommended sequencing

Mirror the iOS staging, lead with the lowest-risk highest-value pieces:

1. **`@Record` field-by-default + inferred requiredness** via KSP, reusing the existing
   Pika/`@OptimizedRecord` machinery. Lowest risk — the runtime and compile-time paths both
   exist; this is mostly "make it the default and infer."
2. **`@ExpoModule` + `@JS` (sync functions, properties)** → generated `ModuleDefinition`.
   Establishes the processor, the generated-definition lookup convention (paired core PR),
   and the visibility rule.
3. **`@JS suspend fun`** → `SuspendFunctionComponent`/Promise. Document the async-semantics
   divergence from iOS.
4. **`@SharedObject`** (instance + companion statics, events via `SharedObject.emit`).
5. **`@Union`** on sealed types.
6. **Phase 2 default** — statically-resolved converters for every generated component
   (generalize Pika beyond records); retire `@OptimizedRecord`/`@OptimizedFunction`-style
   opt-ins.
7. **Views** (`@ViewProps`/`@ExpoView`) — **gated on the core props-object runtime**, the
   same hard dependency as iOS. Don't land ahead of that core work.
8. **Phase 3** — KSP emits type-info; build the cross-platform merge/diff against
   `expo-type-information`'s output. The highest-leverage cross-platform payoff.

# Risks specific to Android

- **Visibility (high, and iOS doesn't have it).** A KSP-generated extension is outside the
  class and can't read `private` members; a Swift macro expands inside and can. Either
  constrain `@JS` to `internal`+ or generate into the same package and rely on `internal`.
  Decide early — it shapes every generated accessor.
- **Async semantics differ from iOS (medium).** No actor no-hop; the shared TS surface
  hides a genuine behavioral difference. Document, don't paper over.
- **View core contract is a hard dependency, and Android is *further behind* iOS (high).**
  No props object exists today; this is net-new core runtime, not just a rename.
- **Out-of-repo coupling (high).** Same as iOS: generated code only compiles against
  matching core; every stage needs a paired core PR. Plus a build-wiring concern unique to
  Android: KSP is applied **per-module** today (`apply plugin: 'com.google.devtools.ksp'`),
  not centrally — v2 likely wants the `expo-module-gradle-plugin` to apply the v2 processor
  automatically so authors don't hand-wire it.
- **Pika dependency (medium).** Leaning on Pika generalizes a third-party
  (`io.github.lukmccall.pika`) KSP library beyond its current record-only use; either
  commit to it as the introspection substrate or write a first-party `SymbolProcessor`
  (none exists in the repo today).

# Bottom line

Yes — the same author-facing model can be implemented on Android, and the design intent is
already in the iOS doc. **Phase 1 and Phase 3 are the safe, high-value targets** (Phase 3
is *better* on Android than iOS and is the real cross-platform payoff), **Phase 2's perf
story must be re-derived for the JVM/JNI reality** (compile-time converter resolution, not
`Any`-box elimination — and core already proves the pattern via Pika/`@OptimizedRecord`),
and **the mechanism is a parallel KSP implementation, not a port** — every "rewrite the
author's declaration" trick from the macros becomes "generate a companion," with async
actor-isolation having no Kotlin equivalent at all.
