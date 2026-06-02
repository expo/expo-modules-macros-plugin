# Expo Modules v2

- **Status:** Draft for review (signatures verified against `expo/main` core)
- **Author:** Tomasz Sapeta
- **Created:** 2026-05-31 · **Updated:** 2026-06-02
- **Scope:** Apple/Swift macros in this repo (`apple/Sources/ExpoModulesMacros`)

## Goal

Use Swift macros to make authoring Expo modules and views simpler, faster, and
type-safe end to end — an author writes ordinary Swift (`@JS` members, a typed props
object, typed events) and the toolchain takes care of the rest. The work is staged
in three phases:

## Phases

1. **[DSL coverage](#phase-1--dsl-coverage)** — macros that cover the existing API
   surface and synthesize the definition using **today's DSL** (`Function`,
   `Property`, `Class`, `View`, `Events`, …). The macro reads `@JS`/`@ViewProps`/etc.
   and emits the same `*Definition` element tree the runtime walks today. This is the
   bulk of this document (Modules + Views below).
2. **[Performance — direct JSI binding](#phase-2--performance-direct-jsi-binding)** —
   instead of emitting the DSL and letting the runtime build JS objects dynamically,
   the macro generates **pure-Swift** code that **binds members directly into the JS object** via
   the `expo-modules-jsi` API. This omits the `*FunctionDefinition` indirection and the
   dynamic-type/`[Any]`/`toTuple` argument path — the biggest current bottleneck — in
   favor of statically-typed, per-argument converters covering **all supported types**.
   The existing `@OptimizedFunction` is an early proof of concept; the goal is for
   *every* synthesized function to be optimized by default, after which
   `@OptimizedFunction` is dropped.
3. **[TypeScript type generation](#phase-3--typescript-type-generation)** — generate
   the module's `.d.ts` (functions, records, view props + event callbacks) from the
   annotated Swift source, so JS types always match native.

Phase 1 produces a correct, complete surface on the existing runtime; phase 2 swaps
the *implementation strategy* underneath the same author-facing API for speed; phase 3
adds the JS-side type story on top of the same source annotations. Phases 2 and 3 both
build on the declarative description phase 1 establishes.

Cross-cutting decisions referenced throughout:

- **Events: typed payloads, no `EventDispatcher`.** An event's payload is typed at
  the Swift level (payload type is `AnyArgument`, or none) and funnels into the
  existing untyped runtime. See [Events model](#events-model).
- **Lifecycle: handled in core, not the macro.** Overridable instance methods that
  core calls directly — the macro synthesizes nothing for lifecycle. See the
  per-section lifecycle notes.
- **Macro declarations** for new attributes live in **`expo-modules-core`**
  (`ios/Core/ExpoModulesMacros.swift`), alongside `@JS`/`@ExpoModule`. Core symbols
  in this doc were read from `/Users/tsapeta/Work/expo/main/packages/expo-modules-core`.

---

# Phase 1 — DSL coverage

Cover the existing API by synthesizing the current definition DSL. The macros below
read the author's `@JS`/`@ViewProps`/etc. declarations and emit the same
`*Definition` element tree (`Function`, `AsyncFunction`, `Property`, `Class`, `View`,
`Events`, …) the runtime already consumes — no runtime changes beyond the core
dependencies noted per section. Organized as **Modules** and **Views**, each listing
its macros as subsections.

## Modules

A module is a class the macro turns into an Expo module: it synthesizes the
definition method, the `AnyModule` conformance, and the lifecycle/event plumbing,
discovering the JS surface from `@JS`-marked members.

### `@ExpoModule`

`@ExpoModule` / `@ExpoModule("CustomName")` on a module class. Synthesizes
`_synthesizedDefinition() -> [AnyDefinition]` from the module name plus the `@JS`
members in the body, and (when the class doesn't inherit `Module`/`BaseModule`)
the `appContext` storage, `init(appContext:)`, and the `AnyModule` conformance —
so inheriting from `Module` is optional. It also stamps `@ModuleDefinitionBuilder`
on a user-written `definition()`.

```swift
@ExpoModule(views: [MyView.self])
class MyModule: Module {
  @JS var version: String { "1.0" }   // getter-only → Property("version") { self.version }
  @JS var ready: Bool = false         // getter+setter (see below)
  @JS func reset() {}

  override func onModuleCreate() {}    // core calls directly — NOT macro-synthesized
  override func onStartObserving() {}  // core calls directly — NOT macro-synthesized
}
```

Arguments:
- `_ name: String? = nil` — JS module name (defaults to the class name).
- `classes: [Any.Type] = []` — shared-object classes whose
  `_synthesizedClassDefinition()` is spliced in.
- `views: [Any.Type] = []` — view classes; each contributes
  `MyView._synthesizedViewDefinition()` (see [Views](#views)). Read with the
  existing `classListArgument(of:label:"views")` `.self` parser.

#### Property getter + setter

Extend the property-entry builder to emit `.set` for a settable stored/computed
var; getter-only (`{ get }` or `let`) stays as today.

```swift
Property("ready") { self.ready }.set { (newValue: Bool) in self.ready = newValue }
```

Setter is a chained method on `PropertyDefinition`
(`Core/Objects/PropertyDefinition.swift:105`, `@discardableResult`, returns `Self`):
```swift
.set(_ setter: @escaping (_ newValue: ValueType) -> Void) -> Self
.set(_ setter: @escaping (_ this: OwnerType, _ newValue: ValueType) -> Void) -> Self
```

> **No `@Constant` macro.** `ConstantDefinition` differs from a getter-only
> `PropertyDefinition` only by also feeding the **legacy synchronous
> `getConstants()` bridge** (`getRawValue()` → `ObjectDefinition.legacyConstants`);
> on the JSI path a getter-only `Property` is equivalent. A getter-only `@JS var`
> therefore already exposes a read-only value. Revisit only if a real consumer
> needs the legacy map — and if so, prefer a `@JS(constant:)` modifier over a
> second attribute (avoids two ~95%-overlapping property attributes).

#### Module events

Typed, no `EventDispatcher` (see [Events model](#events-model)). An event is a
**function-typed property** marked `@Event` — the same "function = event" idea as view
props, but here the macro (not core) wires the dispatch, since a module has no props
object for core to populate.

```swift
@ExpoModule
class MyModule: Module {
  @Event var onProgress: (ProgressEvent) -> Void   // ProgressEvent: @Record
  @Event var onReady: () -> Void                   // no payload

  func work() {
    self.onProgress(ProgressEvent(percent: 50))    // type-checked; dispatches to JS
  }
}
```

`@Event` is an **accessor macro**: a function-typed `var` can't be a stored property
without an initializer, so it expands to a **computed property returning a closure** that
captures `self` and dispatches by name into the typed `emit`:

```swift
var onProgress: (ProgressEvent) -> Void {
  { payload in self.emit(event: "onProgress", payload: payload) }
}
```

This is the **same on modules and shared objects**: both expose
`emit<P: AnyArgument>(event:payload:)` (`SharedObject.swift:102`; assumed added to
`Module` to match — see [Core dependencies](#core-dependencies)), which converts the
payload via `(~P.self).castToJS`. So a `@Event` payload can be **any `AnyArgument`** —
primitive, `@Record`, shared object, `@Union`, etc. — with no dict requirement, and the
no-payload case (`() -> Void`) dispatches `.undefined`.

`@ExpoModule`/`@SharedObject` separately collect `@Event` member names and emit
`Events("onProgress", …)` into the synthesized definition, the same way they collect
`@JS` members — so JS knows the event exists and `OnStartObserving` works.

The synthesized closure allocates per access — negligible for events (not a hot loop).
`@Event` members are stamped `@JavaScriptActor` like other JS members.

#### Module lifecycle

Handled **entirely in core, not by the macro.** Core adds overridable instance
methods on `BaseModule` and calls the override directly at each lifecycle point;
the macro synthesizes nothing.

```swift
override func onModuleCreate() { … }       // core invokes at .moduleCreate
override func onModuleDestroy() { … }       // core invokes at .moduleDestroy
override func onAppContextDestroys() { … }
override func onStartObserving() { … }
override func onStopObserving() { … }
```

Core-side work (out of this repo): add these as `open func … {}` on `BaseModule`
(`ios/Core/Modules/Module.swift`) and call the override from `ModuleHolder` where
it currently does `post(event: .moduleCreate)` / `.moduleDestroy`
(`ios/Core/ModuleHolder.swift:50,139`) and from the observer dispatch. The old
`OnCreate`/`OnDestroy`/`OnStartObserving`/`OnStopObserving`/`OnAppContextDestroys`
DSL factories + `EventListener(.moduleCreate, …)` path can be retired once nothing
emits them.

### `@JS`

Marker (peer macro) on a module / shared-object member that should be exposed to
JS; expands to nothing on its own. `@ExpoModule` and `@SharedObject` discover
`@JS`-marked members and generate the `Function` / `AsyncFunction` / `Property` /
`Constructor` registrations. `@JS("name")` overrides the JS name.

```swift
@JS func greet(name: String) -> String { … }   // Function("greet", greet)
@JS("doWork") func performWork() async throws {} // AsyncFunction("doWork", performWork)
@JS var status: String { "ok" }                  // Property("status") { self.status }
```

The macro stamps `@JavaScriptActor` on `@JS` members (skipping `nonisolated` or members
already on a global actor), reflecting that JS calls run on the JS thread. **This now
includes `async` members** — see below.

#### Async functions

Sync vs. async is expressed by the Swift `async` keyword; there is **no Promise
parameter**.

- **A `@JS` function marked `async` in Swift automatically returns a `Promise` on the
  JS side.** The macro emits an `AsyncFunction` whose closure is the `async` function
  itself (core's `@Sendable async` overload).
- **Promise-based async functions are dropped.** We stop supporting the old form where
  the author takes a trailing `Promise` argument and calls `promise.resolve(…)`
  manually (core's `takesPromise` path). Async is the Swift `async` keyword, full stop.
- **Async functions are also stamped `@JavaScriptActor`** — a reversal of the current
  macro, which skips async members. The stamp is what makes the next point work.
- **Execution matches JS async semantics: the body runs synchronously on the runtime
  thread up to the first real suspension point** (everything before the first `await`
  that actually suspends runs inline), then the continuation is scheduled. This holds
  because the function is `@JavaScriptActor`-isolated *and* invoked from the JS-actor
  context (the runtime thread): calling an actor-isolated `async` function from the same
  actor runs synchronously until an actual suspension — no executor hop before the body
  (SE-0306). Without the `@JavaScriptActor` stamp the call would hop to a generic
  executor first and lose this property; that's why point 3 and point 4 are linked.

```swift
@JS func fetchUser(id: String) async throws -> User { … }
// JS: const user = await module.fetchUser("42")  → returns a Promise
// body up to the first awaited suspension runs synchronously on the JS thread
```

> **Core dependency.** Relies on `@JavaScriptActor`'s custom `SerialExecutor` correctly
> reporting "already on the JS thread" (SE-0471 `isIsolatingCurrentContext` / SE-0424
> `checkIsolated`) so the runtime treats a same-thread call as no-hop. The
> Promise-param `AsyncFunction` overload + `takesPromise` path can be retired from core
> once nothing emits them.

### `@SharedObject`

Member macro on a `SharedObject` subclass; synthesizes
`_synthesizedClassDefinition() -> ClassDefinition` (Function / AsyncFunction /
Property / Constructor from `@JS` members) ready to drop into a module's
`Class { ... }` slot, with the same `@JavaScriptActor` stamping as `@ExpoModule`.

```swift
@SharedObject
final class Cache: SharedObject {
  @JS init(name: String) { … }                  // Constructor
  @JS func get(_ key: String) -> String? { … }  // instance → prototype
  @JS var size: Int { … }                        // instance property
  @JS static func open(_ path: String) -> Cache { … }   // static → constructor (Cache.open)
  @Event var onEvicted: (EvictedEvent) -> Void   // event (see Module events)
}
```

#### Static vs. instance members

Shared objects (unlike modules) can expose **static/class members** alongside instance
ones. The differentiator is the Swift **`static` modifier** — no separate attribute: the
macro reads `static func` / `static var` and routes them to the static side.

This can't collide with instance members because JS places them differently, exactly as
core's `ClassDefinition` already does at install time (`ClassDefinition.swift:88–96`):
- **Instance** members (`@JS func`, `@JS var`) → decorate the **prototype**
  (`decorateWithFunctions`/`decorateWithProperties` on `object.prototype`).
- **Static** members (`@JS static func`) → decorate the **constructor object**
  (`decorateWithStaticFunctions`) — i.e. `Cache.open(...)`, callable on the class itself.

DSL mapping: an instance function emits `Function("get", …)`; a static one emits
**`StaticFunction("open", …)`** (`StaticFunctionDefinition`, the static counterpart core
already provides). In phase 2 (direct JSI binding), statics decorate the constructor and
instance members the prototype — the same split, just done by the generated builder.

**Binding names don't need a new sigil.** For a shared object, **all** `` `#…` ``
bindings are `static func`s on the type (the decoration is class-level — see
[Class-level decoration](#class-level-decoration-phase-2)) — they differ only in what the
body does: an instance-member binding recovers the native receiver from JS `this`
(`(~Cache.self).cast(jsValue: this, …)`), a static-member binding ignores `this` and calls
the Swift `static` member (`Cache.open(…)`). So a JS instance member and a JS static member
that share a name (`cache.get` vs `Cache.get`) are two distinct `static func \`#get\``
*overloads-by-context* — but to keep their Swift names unambiguous, the static-member
binding can carry a qualifier (e.g. `` `#static.get` ``), the same scheme used for property
get/set (`` `#ready.get` ``). The single `#` sigil stays the only marker.

> **Static *properties* need core support.** Core has `StaticFunction` but **no
> `StaticProperty`** today (class properties decorate an instance, not the prototype/
> constructor — `ClassDefinition.swift:91`). So `@JS static var` is gated on a core
> `StaticProperty` addition; `@JS static func` works against today's core.

#### Class-level decoration (phase 2)

A shared object's phase-2 decoration is **class-level — once per class, no per-instance
pass** — because every member resolves its native receiver from JS `this`, not a captured
instance. This mirrors core's `ClassDefinition.decorate` (`ClassDefinition.swift:87–98`):

- **static functions** → decorate the **constructor**.
- **instance functions** → decorate the **prototype**; the native receiver is resolved
  per-call from `this` via the shared-object registry (core's `takesOwner` path,
  `SyncFunctionDefinition`).
- **properties** → also decorate the **prototype**. The getter/setter take the owner
  (`takesOwner`, the `(_ this: OwnerType)` accessor form) and resolve the native instance
  from `this`, so a single prototype accessor serves all instances — no per-instance
  binding needed. (Core does exactly this: `decorateWithProperties(object: prototype)`,
  `ClassDefinition.swift:97`. A stale comment two lines above says properties decorate an
  instance — the code below it puts them on the prototype.)

So `@SharedObject` emits a **`static func _decorateJavaScriptClass(_ klass:…)`** that sets
up the prototype + constructor once. The only genuinely per-instance work is core's
internal native↔JS pairing (`sharedObjectId`, `SharedObjectRegistry.swift:114`), which the
macro doesn't generate.

**How an instance member reaches its receiver without `self`.** This is the key
difference from modules. A shared-object binding is `static` — it has no `self` — so it
recovers the native instance from JS **`this`**: every instance's JS object is paired with
its native object in the `SharedObjectRegistry` at construction (`ClassDefinition.swift:68`),
and `(~Cache.self).cast(jsValue: this, …)` resolves it back (core's `takesOwner` path →
`DynamicSharedObjectType` → `sharedObjectRegistry.get(...).native`,
`DynamicSharedObjectType.swift:41`). The receiver is a *resolved parameter*, not the
binding's `self`:

```swift
// shared-object instance function `get` — static, receiver resolved from `this`
static func `#get`(_ this: JavaScriptValue, _ arguments: borrowing JavaScriptValuesBuffer,
                   appContext: AppContext, in runtime: JavaScriptRuntime) throws -> JavaScriptValue {
  let owner = try (~Cache.self).cast(jsValue: this, appContext: appContext) as! Cache
  let key   = try (~String.self).cast(jsValue: arguments[0], appContext: appContext) as! String
  return try (~(String?).self).castToJS(owner.get(key), appContext: appContext, in: runtime)
}
```

**Modules differ exactly here:** a module *is* a singleton instance, so its binding is an
**instance method** using the real `self` (`self.add(…)`, the
[sketch above](#example-a-sync-function)) and ignores `this`. So: module binding = instance
method on real `self`; shared-object binding = `static`, receiver recovered from `this`.
The decode/convert of the *other* arguments is identical in both.

**Events** use the same `@Event` function-typed property as modules
([Module events](#module-events)); the synthesized closure dispatches into
`emit<P: AnyArgument>(event:payload:)` (`SharedObject.swift:102`). `@SharedObject`
collects `@Event` names into the class definition's `Events(…)`. (Modules and shared
objects share one events model — same `@Event`, same typed `emit`.)

For full parity, `@SharedObject` should also gain **property setters** (as modules do).

### `@Record`

`@Record` on a `Record` type synthesizes `_recordFields(of:)` — compile-time
field/key pairs that replace the runtime `Mirror` walk in `fieldsOf(_:)`.

**All stored properties are fields by default** — `@Field` is no longer required to
make a property a field. The macro can see every stored property at expansion time,
so the common case needs no annotation:

```swift
@Record
struct Options: Record {
  var name: String = ""
  var count: Int = 0
  var flag: Bool = false
}
```

**Requiredness is inferred from the declaration** (default value / optional type), so
`@Field(.required)` is rarely needed:

| Property | JS requiredness |
|---|---|
| has a default value (`var x: T = …`) | **optional** — may be omitted; default applies |
| optional type (`var x: T?`) | **nullable** *and* optional — may be omitted or `null` |
| non-optional, no default (`var x: T`) | **required** — must be provided |

`@Field` still exists to **set options** — force `.required` on a defaulted/optional
field, or remap the key:

```swift
@Record
struct Options: Record {
  var name: String                               // required (no default, non-optional)
  var count: Int = 0                              // optional (has default)
  var note: String?                               // nullable + optional
  @Field(.required) var token: String = ""        // force-required despite the default
  @Field(.keyed("custom_key")) var flag: Bool = false  // custom JS key
}
```

Because the default flipped, **exclusion needs an explicit opt-out** (omitting
`@Field` no longer excludes a property). Open: the opt-out spelling — an `@Ignore`
attribute vs. a convention. Also: every stored property is now expected to be
`AnyArgument`/convertible; a non-convertible stored property must be opted out or it's
a diagnostic.

`@Record`'s field synthesis is reused by `@ViewProps` for its value props — see
[`@ViewProps` vs `@Record`](#viewprops-vs-record).

### `@Union`

A **typed union of types** — the JS value may be any one of several types (`A | B | C`).
`@Union` is applied to a Swift `enum` whose cases carry the alternatives as associated
values; the macro synthesizes the decode and the JS/TS type.

```swift
@Union
enum Media {
  case url(URL)
  case data(Data)
  case config(MediaConfig)   // a @Record
}

@JS func load(_ media: Media) { … }
// JS type:  Media = string | ArrayBuffer | MediaConfig
// author:   switch media { case .url(let u): … }   ← typed, exhaustive
```

Why an enum (vs. the existing `Either`):
- **Tagged + typed.** A Swift enum with associated values *is* a tagged union — no
  `Any?` box, no `.get()` optionals, exhaustive `switch`. Each payload keeps its static
  type.
- **N cases, named.** `Either` is fixed at two and anonymous (you nest
  `Either<A, Either<B, C>>` for three); `@Union` is any number of named cases and maps
  cleanly to a TS union (the case payloads → `A | B | C`).
- **Faster decode (phase 2).** The macro knows the cases statically, so it generates an
  ordered, typed decode straight into the matching case — no `DynamicEitherType` walk,
  no `Any?` erasure, no thrown-and-caught exception per failed candidate (`Either`'s
  current trial loop). See [Phase 2](#phase-2--performance-direct-jsi-binding).

**Discrimination is structural, in declaration order** (the same model `Either` uses
today): the decoder tries each case's payload converter top-to-bottom and takes the
first that succeeds. **Caveat:** when payload shapes overlap (e.g. two `@Record`s with
compatible fields, or `Int` vs `Double`), the match is order-dependent. A
*discriminated* mode — picking the case by a tag field, like a TS discriminated union —
is a **deferred follow-up** (`@Union(discriminator: "type")`), not v1.

**`Either` stays** for the quick inline anonymous 2-type case
(`func a(_ x: Either<String, Int>)`); the macro optimizes its decode the same way.
`@Union` is the named, N-case option. (Two ways to express a union — `Either` for inline
2-type, `@Union` for named unions.)

---

## Views

A view is a `: ExpoView` (UIKit) class plus a typed **props object**. Props are
declared once as a `@ViewProps` record. The view exposes **`var props`** — always the
current props instance — and receives **batched, atomic** updates via an
`onViewPropsChanged(oldProps:)` lifecycle method (by the time it's called, `self.props`
is already the new value; the parameter is the previous one, for diffing — `nil` on the
first application). There is no per-property `Prop(…)` closure and **no `@Prop`
attribute**.

> **Core dependency (UIKit).** This unified props-object model needs core runtime
> that doesn't exist yet on the UIKit path. The macro is designed against the
> contract below; core implements it separately. SwiftUI already has the model
> (`ExpoSwiftUI.ViewProps` is `open class ViewProps: ObservableObject, Record`);
> UIKit today has only per-prop closures (`ExpoFabricView.updateProps(_:)`,
> `ios/Fabric/ExpoFabricView.swift:84`). See
> [Core dependencies](#core-dependencies).

### `@ExpoView`

`@ExpoView(props: MyViewProps.self)` on a `: ExpoView` class. Synthesizes
`_synthesizedViewDefinition() -> ViewDefinition<MyView>`, registering the props
type and the event names gathered from the props object:

```swift
@ExpoView(props: MyViewProps.self)
class MyView: ExpoView {
  // self.props is always current. The callback gets the OLD props for diffing —
  // nil on the first application (initial mount, no previous value).
  override func onViewPropsChanged(oldProps: MyViewProps?) {
    if oldProps?.color != props.color { backgroundColor = props.color }
    if oldProps?.radius != props.radius { layer.cornerRadius = props.radius }
  }
}
```

Synthesized output:
```swift
public static func _synthesizedViewDefinition() -> ViewDefinition<MyView> {
  return View(MyView.self) {
    Props(MyViewProps.self)   // ← new core element; replaces per-Prop closures
    Events("onTap")           // names gathered from function-typed fields on the props object
    // onViewPropsChanged is an override called by core — not emitted here
  }
}
```

> `Props(_:)` is a **new core element** (see [Core dependencies](#core-dependencies)).
> If core instead exposes this via a `View<Props, ViewType>` overload (as the
> SwiftUI path does), the synthesized wrapper changes shape — pin when core lands.

The macro does a `: ExpoView` inheritance check (mirroring `@SharedObject`), reads
the props type from the `props: MyViewProps.self` metatype argument (reusing the
`classListArgument`-style `.self` parser), and wiring into a module is via
`@ExpoModule(views: [MyView.self])`.

**Why the props type is a metatype arg, not a generic in the inheritance clause:**
the longer-term direction is to stop requiring the inheritance clause, so the props
type must not live there. Also `@ExpoView<MyViewProps>` is not legal Swift
(attributes can't take generic args), and a macro can only add conformances, not a
superclass.

#### View lifecycle

`onViewPropsChanged(oldProps:)` is a core-called **override** — not macro-synthesized.
Contract: core sets `view.props` to the new value **first**, then calls the override with
the **previous** props as `oldProps` (typed `Props?` — **`nil` on the first
application**, since there's no prior value); the user diffs `oldProps` against
`self.props` (= the new props). One typed, optional parameter, and a single
authoritative non-optional "current" — `self.props`.
(Depends on the core contract — see [Core dependencies](#core-dependencies).) Core today
exposes only
`OnViewDidUpdateProps`; there is no `OnViewDestroys`.

### `@ViewProps`

`@ViewProps` on a props **`struct`**. **Value stored properties are props;
function-typed properties are events** (see [Events model](#events-model)). Like
`@Record`, fields need no `@Field` annotation by default; `@Field` is only for
options. One record ⇄ one TS type, callbacks included — exact native/TS symmetry. No
`EventDispatcher`, no `@ViewEvent`.

```swift
@ViewProps
struct MyViewProps {
  var color: UIColor = .red       // has default      → optional in JS
  var radius: CGFloat?            // optional type     → nullable + optional in JS
  var title: String               // no default, non-optional → required in JS
  var onTap: (TapEvent) -> Void   // event: payload TapEvent (AnyArgument), name "onTap"
  var onClose: () -> Void         // event: no payload
}
```

**Requiredness is inferred from the declaration** (so `@Field(.required)` is rarely
needed — see [`@Record`](#record)):

| Property | JS requiredness |
|---|---|
| **has a default value** (`var x: T = …`) | **optional** — may be omitted; the default applies |
| **optional type** (`var x: T?`) | **nullable** *and* optional — may be omitted or `null` |
| **non-optional, no default** (`var x: T`) | **required** — must be provided |

"Optional" (key may be omitted) and "nullable" (value may be `null`) are independent: a
property can be one, both, or neither. The rule maps to core's `isRequired` — a field is
required only in the last row. `@Field(.required)` can still force-require a defaulted or
optional property when an author wants that.

**Struct, for performance.** Props are decoded on every React update; a value type
avoids per-update heap allocation + ARC churn and makes the `oldProps` vs `self.props`
comparison in `onViewPropsChanged(oldProps:)` a clean value diff. v1 is **UIKit-only**, and
the UIKit path (`ExpoFabricView.updateProps`) does **not** observe props — it compares
values and calls setters — so nothing forces a reference type here.

#### Struct or class — the conformance carries the constraint

SwiftUI can't observe a struct. Its props path shares **one props instance** between
the framework and the view: `HostingView` holds `private let props: Props` and on each
React update calls `props.updateRawProps(…)` → `objectWillChange.send()`; the view
observes that same instance (`@ObservedObject`, props a `class … ObservableObject`).
This "framework owns and pushes mutations" pattern is inherently reference-based —
`@State` on a struct can't replace it, and `ObservableObject` / `@Observable` (SE-0395)
are class-only. UIKit, by contrast, doesn't observe at all (`ExpoFabricView.updateProps`
compares values and calls setters), so a `struct` is fine — and faster (no per-update
heap alloc/ARC; clean value diff).

**Decision: `@ViewProps` may be a `struct` or a `class`; the author picks per view, and
a wrong choice is a compile error — not via a macro type-check (a macro can't see
whether `MyViewProps.self` resolves to a struct or class), but via the conformance the
macro emits.** `@ViewProps` is attached directly to the type, so it *can* see the
`struct`/`class` keyword and emit the matching props protocol:

- `@ViewProps struct` → a **value** props protocol (value-friendly; `Record` + fields).
- `@ViewProps class` → a **class-bound observable** props protocol
  (`: AnyObject, ObservableObject`). The author's class uses real
  `@Observable`/`ObservableObject` (author-written — so no macro-reexpansion problem,
  and the author picks the mechanism for their deployment target).

`@ExpoView` checks nothing itself. SwiftUI's `View<Props>` / `ExpoSwiftUIView`
`associatedtype Props` bound requires the **observable** protocol, so a `struct` props
simply doesn't conform → **clean compiler error at the SwiftUI view**. UIKit requires
only the value protocol (or takes the struct directly). Both frameworks coexist in one
target — a UIKit view uses a struct props, a SwiftUI view uses a class props; they're
just different types.

```swift
@ViewProps struct CardProps { var color: UIColor = .red }      // UIKit view ✓ ; SwiftUI view ✗ (compile error)
@ViewProps class  PanelProps: ObservableObject { … }           // SwiftUI view ✓ ; UIKit view ✓
```

Trade-off: a props type **shared** by both a UIKit *and* a SwiftUI view must be the
common denominator — a `class`. The common case (props belongs to one view) is
unaffected, and the author opts into the class only when they actually need SwiftUI.

This replaces the earlier "macro generates a nested observable class" idea, which would
have forced the macro to hand-emit observation plumbing (macro output isn't
re-expanded, so it couldn't reuse `@Observable`/`@Published`). Letting the author write
the class and enforcing via the conformance is simpler and avoids that cost.

**Core dependency:** the props protocol must be **split** into a value-props and a
class-bound observable-props protocol, with SwiftUI's `View<Props>` bound on the latter.
Today there's one `ExpoSwiftUI.ViewProps` (already a class). This split is core-side
work — see [Core dependencies](#core-dependencies). SwiftUI support itself is deferred
past v1 (UIKit-only).

Synthesis — the macro adds:
- **`Record`** + `@Record`'s value-field descriptor synthesis for the prop fields.
- The **view-props conformance** core requires (the `ExpoSwiftUI.ViewProps`-equivalent
  / props marker — exact protocol TBD against the core work).
- **Function-typed-property event recognition**: their names feed the view
  definition's `Events(...)`. The macro emits no closure body; core dispatches the
  event by name.

> **Struct ⇒ events wiring can't mutate the props instance.** Core's current
> `setUpEvents` finds `EventDispatcher` fields via `Mirror` and *assigns* their
> `.handler` — that needs reference semantics. With a `struct` props and
> function-typed event properties, core can't mutate a stored closure on a value copy;
> instead the synthesized event property must *call into* a core-held dispatcher
> (by event name). This sharpens the §0a core contract — see
> [Core dependencies](#core-dependencies).

#### `@ViewProps` vs `@Record`

A props object *is* a `Record` at the **runtime** level (same
`fieldsOf`/`update(withDict:)` machinery; there's no separate props marker protocol in
core today). Even so, `@ViewProps` is a **distinct attribute**, not a `@Record` alias:

- **Property classification differs.** A function-typed property is *invalid* in a
  `@Record` (Records are pure `toDictionary` data) but *is an event* in `@ViewProps`.
  One attribute can't apply both rules to the same syntax.
- **TS generation reads the attribute from Swift source.** The generator keys on
  `@ViewProps` to emit a *component-props type* (value properties → props, function
  properties → event callbacks, plus the React view-props base) vs `@Record` → a plain
  data object. A typealias would erase exactly this source-level signal.
- **Implementation is shared.** `@ViewProps` reuses `@Record`'s value-field
  synthesis (factored out of `RecordMacro.swift`); it adds event-property recognition
  and the view-props conformance — value-props for a `struct`, class-bound
  observable-props for a `class` (see above).
- The runtime conformance is still emitted (core decodes/observes props through it)
  but is **not** the TS distinction — that's the attribute. So the core side is
  free to pick whatever conformance/marker it needs without affecting TS generation.

---

# Phase 2 — Performance: direct JSI binding

Phase 1 keeps the existing execution model: the macro emits `*Definition` elements,
and at call time the runtime walks the definition, builds a `[Any]` argument array,
resolves each argument through a **dynamic type** converter, and assembles a tuple
via `toTuple` before invoking the Swift function. That dynamic path — boxing every
argument to `Any` and the `toTuple` conversion — is the **biggest runtime
bottleneck** today.

Phase 2 changes the *strategy*, not the author-facing API. Because the macro already
knows each member's **static Swift signature** at compile time, it can generate
**pure-Swift** code that **binds members directly into the JS object** via the `expo-modules-jsi`
API — creating the JS functions/properties itself instead of describing them with
`*FunctionDefinition` for the runtime to interpret. The generated binding can then:

1. **Validate arity statically** — the argument count is known at expansion time, so
   the generated function checks it directly (no definition lookup).
2. **Use per-argument typed converters** — each argument's concrete type is known, so
   the macro emits a specific converter per argument and reads each from the JS call
   **individually into its Swift type**, avoiding the `[Any]` boxing and the `toTuple`
   step entirely (instead of today's runtime dynamic-type resolution).
3. **Skip the `*FunctionDefinition` indirection** — the JS-visible function is created
   straight against JSI, so there's no per-call definition walk.

This must cover **all supported argument/return types** — not just primitives, but
records, shared objects, arrays/typed-arrays, enums, unions (`@Union` / `Either`),
optionals, `Promise`, etc. (the full `AnyArgument` set) — each with a statically-selected
converter. Phase 2 isn't done until the optimized path is a complete replacement, not a
fast lane for a subset.

Unions are a notable win: today `Either` boxes its payload in `Any?` and decodes by
*trying each candidate type in a `try?`/throw loop* through `DynamicEitherType`. With the
static type known, the macro emits an **ordered typed decode** straight into the matching
`@Union` enum case (or `Either`), eliminating the `Any?` erasure and the
exception-driven trial. See [`@Union`](#union).

### Example: a sync function

Author writes the same thing in both phases:

```swift
@JS func add(a: Double, b: Double) -> Double { a + b }
@JS var ready: Bool = false   // getter + setter (settable stored var)
```

**Phase 1** — the macro emits DSL entries; core builds the JS function/property and
resolves arguments dynamically at call time:

```swift
// in _synthesizedDefinition():
Function("add", add)
Property("ready") { self.ready }.set { (newValue: Bool) in self.ready = newValue }
// at every call, core: collects args into [Any] → resolves each via dynamic types
// → assembles a tuple (toTuple) → invokes the native fn/getter/setter. The [Any] boxing
// + toTuple is the cost.
```

**Phase 2** — the macro emits code that **builds the JS host function itself** with
`runtime.createFunction` (from `expo-modules-jsi`) and assigns it to the module's /
shared object's JS object, decoding each argument by its static type and calling the
Swift function directly — no `[Any]`/`toTuple` assembled by a generic call path, no
per-call definition walk. Illustrative expansion (the exact registration entry point is
part of the [core contract](#core-dependencies)):

```swift
// One binding per @JS member. The binding IS the host-function body — it has the
// createFunction closure signature (this, arguments) -> JavaScriptValue — rather than
// wrapping it; `_decorateJavaScriptObject` does the createFunction call. Named with a backtick
// raw identifier `#add` so it's unmistakably generated and never spelled by users (see
// note). `self` is the native module instance; `this` is the JS owner; `arguments` is a
// JavaScriptValuesBuffer. appContext/runtime are threaded in (no longer captured).
@JavaScriptActor
private func `#add`(_ this: JavaScriptValue, _ arguments: borrowing JavaScriptValuesBuffer,
                    appContext: AppContext, in runtime: JavaScriptRuntime) throws -> JavaScriptValue {
  // 1. static arity check — count known at expansion time
  guard arguments.count == 2 else { throw InvalidArgCount(expected: 2, got: arguments.count) }

  // 2. per-argument decode, one cast per arg by its static type — no [Any] collection,
  //    no toTuple. (For now via the existing dynamic-type converters; see note.)
  let a = try (~Double.self).cast(jsValue: arguments[0], appContext: appContext) as! Double
  let b = try (~Double.self).cast(jsValue: arguments[1], appContext: appContext) as! Double

  // 3. call the Swift function directly, convert the typed result back to JS
  let result: Double = self.add(a: a, b: b)
  return try (~Double.self).castToJS(result, appContext: appContext, in: runtime)
}

// A settable property → a getter binding + a setter binding. A getter-only property
// omits the setter. Same host-function-body shape as above.
@JavaScriptActor
private func `#ready.get`(_ this: JavaScriptValue, _ arguments: borrowing JavaScriptValuesBuffer,
                          appContext: AppContext, in runtime: JavaScriptRuntime) throws -> JavaScriptValue {
  return try (~Bool.self).castToJS(self.ready, appContext: appContext, in: runtime)
}
@JavaScriptActor
private func `#ready.set`(_ this: JavaScriptValue, _ arguments: borrowing JavaScriptValuesBuffer,
                          appContext: AppContext, in runtime: JavaScriptRuntime) throws -> JavaScriptValue {
  self.ready = try (~Bool.self).cast(jsValue: arguments[0], appContext: appContext) as! Bool
  return .undefined
}

// A single generated function decorates the JS object core hands it with every binding.
// This is what the runtime calls instead of walking a DSL definition. Core supplies the
// target object — the module's JS object, or a shared object's prototype/constructor;
// never a plain object the macro creates. Mirrors core's `ObjectDefinition.decorate(object:)`.
// The createFunction call lives here once; each binding is passed in as the closure body.
@JavaScriptActor
public func _decorateJavaScriptObject(_ object: borrowing JavaScriptObject,
                                      appContext: AppContext, in runtime: JavaScriptRuntime) throws {
  // function → a plain property holding the function
  let add = runtime.createFunction("add") { [self] this, args in
    try `#add`(this, args, appContext: appContext, in: runtime)
  }
  object.setProperty("add", value: add.asObject())

  // property → a get/set descriptor, installed with defineProperty
  let descriptor = try runtime.createObject()
  descriptor.setProperty("enumerable", value: true)
  descriptor.setProperty("get", value: runtime.createFunction("ready") { [self] this, args in
    try `#ready.get`(this, args, appContext: appContext, in: runtime)
  })
  descriptor.setProperty("set", value: runtime.createFunction("ready") { [self] this, args in   // omit for getter-only
    try `#ready.set`(this, args, appContext: appContext, in: runtime)
  })
  object.defineProperty("ready", descriptor: descriptor)

  // … one entry per @JS function / property / constructor / event …
}
```

Notes:
- Uses real `expo-modules-jsi` types — `JavaScriptRuntime`, `JavaScriptValue`
  (`arguments[i]`), `JavaScriptFunction`, `JavaScriptObject` — and
  `runtime.createFunction(name) { this, arguments in … }`, the same primitive
  `SyncFunctionDefinition.build` uses today (`SyncFunctionDefinition.swift:129`). `this`
  is the JS owner; the native receiver is the macro's `self`, so the body calls
  `self.add(…)` directly.
- Each `` `#…` `` binding **is the host-function body**, not a factory — it has the
  `createFunction` closure shape `(this, arguments) throws -> JavaScriptValue`. The single
  `runtime.createFunction(...)` call (and `.asObject()`) lives in `_decorateJavaScriptObject`,
  which passes the binding as the closure. This keeps the per-member generated code to
  just the decode-call-convert work, and avoids each binding capturing `self`/`appContext`
  (they're plain method parameters / the implicit receiver).
- **Properties** emit a getter binding (`` `#ready.get` ``) and, if settable, a setter
  binding (`` `#ready.set` ``); the builder wraps each in `createFunction` and assembles a
  JS **descriptor** (`enumerable` + `get`/`set` functions), installed with
  `object.defineProperty(name, descriptor:)` — the same descriptor shape
  `PropertyDefinition.buildDescriptor` uses today (`PropertyDefinition.swift:183`).
  Getter-only properties (computed `{ get }` / `let`) omit the setter binding. The
  getter/setter decode + result conversion uses the same per-type `(~T.self)` casts as
  functions.
- **First cut reuses the existing converters.** `(~A.self).cast(jsValue:appContext:)` is
  the current per-type dynamic cast — it returns `Any`, so there's still a boxing + force
  cast here. The win at this stage is structural: each argument is cast *individually by
  its known type*, with no `[Any]` argument array and no `toTuple`. **Eliminating the
  `Any` round-trip** (a converter that returns the concrete `A` directly) is the deeper
  optimization, layered on later.
- The converter is chosen at expansion by the static type, so `@Record`, `@Union`,
  shared object, optional, etc. each get their own `(~T.self)` cast (the full
  `AnyArgument` set).
- **Async** (`@JS func … async`) wraps the same body in the JS `Promise` machinery and
  runs on `@JavaScriptActor` (synchronous until the first suspension) — see
  [`@JS` › Async functions](#async-functions).
- This sketch decorates a module's single JS object. A **shared object** uses a
  `static func _decorateJavaScriptClass` instead — same per-member bindings, but applied
  to the **constructor** (statics) and **prototype** (instance funcs + properties), once
  per class; receivers resolve from JS `this`. See
  [Class-level decoration](#class-level-decoration-phase-2).
- **The bindings are never called by name** — only the generated `_decorateJavaScriptObject`
  references them (it knows the full set, since the macro emits both in one expansion).
  They're named with **backtick raw identifiers `` `#add` ``** (SE-0451), which makes them
  visually unmistakable as generated and unspellable in ordinary code, and `private` so they
  don't leak. `_decorateJavaScriptObject` keeps the existing leading-underscore convention
  since the **runtime calls it**, and takes the target object core supplies (it doesn't
  create one) — mirroring core's `ObjectDefinition.decorate(object:)`, including its
  **`borrowing`** parameter: it mutates the object through its reference
  (`setProperty`/`defineProperty`) without reassigning or taking ownership, so it borrows
  rather than `inout` (no rebinding) or `consuming` (caller keeps using it).
  Same convention core uses (`ObjectDefinition.swift:97`).
- **Prerequisite: Swift 6.2.** Raw identifiers (`` `#…` ``) require Swift 6.2 **where the
  generated code compiles — i.e. the consumer module**, not just the macro plugin (the
  plugin is already on swift-tools 6.2). Core / consumer modules are currently
  `swift_version 6.0`, so this binding style is gated on raising that floor. Until then the
  fallback is a plain leading-underscore name (`_expoBind_add`), which has no version
  requirement. Tracked in [Core dependencies](#core-dependencies).

### Proof of concept: `@OptimizedFunction`

`@OptimizedFunction` (`ExpoModulesOptimizedMacro.swift`,
`OptimizedFunctionHelpers.swift`) is an early **proof of concept** of this idea — it
demonstrates that a typed function can be bound with per-argument types instead of the
dynamic path. It is **not the target shape**:

- It currently bridges through **ObjC** — a `@convention(block)` wrapper plus a
  hand-built ObjC type-encoding string (e.g. `"d@?dd"`) and an
  `OptimizedFunctionDescriptor`. Phase 2 should be **pure Swift** (no ObjC encoding /
  `@convention(block)` round-trip), reading arguments directly through the JSI Swift
  API.
- Its converter table covers only primitives (`Double`/`Int`/`String`/`Bool`/`Void`);
  phase 2 covers the full type set above.
- It's opt-in per function. Phase 2 makes the optimized strategy the **default for
  every synthesized function** (sync + async, properties, constructors).

**End state: `@OptimizedFunction` is removed.** Once every synthesized function is
optimized by definition, a separate opt-in attribute is redundant — the
proof-of-concept macro and its ObjC bridge get deleted.

### Scope & dependencies

- **Author API is unchanged** from phase 1 — same `@JS`/`@ExpoModule` declarations;
  only what the macro emits (and the core entry points it targets) changes. The DSL
  itself can also remain as a hand-written fallback.
- **First cut needs little new core.** `runtime.createFunction` and the per-type
  `(~T.self).cast(jsValue:appContext:)` / `castToJS` converters already exist in
  `expo-modules-jsi` + core; the macro just emits the binding that uses them directly
  (skipping `[Any]`/`toTuple`). What's needed is a clear **registration entry point** to
  attach the generated functions/properties to the module's / shared object's JS object.
- **Deeper optimization is a later layer:** an `Any`-free converter (returns the concrete
  `A` instead of `Any`, removing the boxing + force-cast in the sketch above). This is
  the real perf dependency, pinned with core when we get there.
- Open: how non-`AnyArgument` / unconvertible types are diagnosed at expansion time
  (compile error vs. fallback to the dynamic path).

---

# Phase 3 — TypeScript type generation

Generate the module's `.d.ts` (function signatures, record shapes, **view props +
event callbacks**) directly from the annotated Swift source, so JS types are always
in sync with native and never hand-maintained. The macro attributes from phases 1–2
(`@ExpoModule`, `@JS`, `@SharedObject`, `@Record`, `@ViewProps`, `@ExpoView`) form a
declarative, machine-readable description of the module's native + JS surface — the
basis for generation. The `@ViewProps`-vs-`@Record` distinction
([above](#viewprops-vs-record)) exists partly to make this unambiguous: a `@ViewProps`
type maps to a React component-props type with event callbacks; a `@Record` maps to a
plain data object.

**This cannot live in the macro.** Swift compiler macros run in an OS-level sandbox
with **no filesystem or network access** (WWDC23, *Expand on Swift Macros*: "Compiler
plug-ins run in a sandbox that stops macro implementations from reading files on disk
or accessing the network") and must be deterministic for incremental builds. So a
macro can never write a `.ts` file — it can only transform Swift in-place. Type
generation is a **separate source-parsing tool** — and that tool already exists
(`expo-type-information`, below).

The generator reads the **declarations from source** (the decided signal), not a
runtime conformance — it doesn't need the code to compile or link. Open design points:
how view-props events map to TS callback signatures (payload `Record` → TS object), how
`AnyArgument` payload types resolve to TS, and optional/required field mapping.

### Reuse `expo-type-information`

**The pipeline already exists** — the `expo-type-information` package
(`packages/expo-type-information`) parses Swift Expo modules and emits TypeScript today.
Phase 3 is **adapting it to the new macro surface**, not building a generator from
scratch.

What it already does:
- **Parses Swift modules for type info via `sourcekitten`** (SourceKit-backed, so it has
  *resolved* types, not just syntax; macOS-only, needs the `sourcekitten` tool).
- **Emits TypeScript** — types, wrapper functions, and mocks
  (`typescriptGeneration.ts`, `mockgen.ts`).
- Ships CLI commands that already line up with our surface:
  `inlineModulesInterfaceCommand`, `moduleInterfaceCommand`, `generateModuleTypesCommand`,
  `generateViewTypesCommand`, and `generateJSXIntrinsicsCommand` (view JSX intrinsics ≈
  our `@ViewProps`).

So phase 3 work is mostly **teaching it the new attributes** — `@JS` (incl. `async` →
`Promise`), `@Record`/field-by-default + requiredness inference, `@ViewProps` (value
props vs. function-typed events), `@ExpoView`, `@Union`, `@Event` — and mapping each to
the right TS shape (e.g. `@ViewProps` → component-props type with event callbacks;
`@Union` → `A | B | C`; optional/default → optional TS field).

Note: it uses **SourceKitten**, not SwiftSyntax (which the phase-1/2 macros and the
sandbox discussion assume). That's fine for an external tool — SourceKitten gives
resolved types, which can be *more* than enough — but it's a different front end than the
macros use. Open: whether to keep SourceKitten or move the parser to SwiftSyntax for
consistency with the macro toolchain.

---

# Cross-cutting concerns

## Events model

**Requirement: an event's payload must be typed.** The runtime is untyped end to
end — `Module.sendEvent(_:_: [String: Any?])`; `EventDispatcher`'s handler is
`([String: Any]) -> Void`; the Fabric path ends at `dispatchEvent(name, payload: id)`
→ JSI. So "typed" means **compile-time typing in Swift**, funneled into the existing
untyped runtime; no generic runtime type is required.

**Payload type = `AnyArgument`** (or no payload). "Everything we can convert to JS"
is exactly the `AnyArgument` protocol: primitives, `Record`, `Convertible`, shared
objects (`AnySharedObject: AnyArgument`), `UIView`, `JavaScriptObject`,
arrays/typed-arrays, `Either`, `Promise`. `Conversions.anyToJavaScriptValue` already
casts any `AnyArgument` to JS via `getDynamicType().castToJS()`. Precedent:
`SharedObject.emit<P: AnyArgument>(event:payload:)`
(`SharedObjects/SharedObject.swift:102`) is already exactly a typed-payload event
send — modules/views just don't have an equivalent yet.

**`EventDispatcher` is dropped from the macro's output.** It's a heap class found
reflectively (`Mirror`) that only forwards to a `([String: Any]) -> Void` handler;
the real emitters (`sendEvent`, `dispatchEvent`) take a dict directly.

- **Views:** events fold into `@ViewProps` function-typed properties (above). Core
  dispatches by event name; the synthesized event property calls into a core-held
  dispatcher rather than core mutating a stored closure on the props instance (the
  props are a `struct` — value semantics, so the old "assign `.handler` via `Mirror`"
  approach in `SwiftUIViewProps.setUpEvents` doesn't apply). Still a *reducing* change
  vs. the `EventDispatcher` indirection. See [Core dependencies](#core-dependencies).
- **Modules & shared objects:** a `@Event` function-typed property; the macro (not core)
  synthesizes a computed property whose closure dispatches by name into
  `emit<P: AnyArgument>(event:payload:)` — the same typed call on both
  (`SharedObject` has it; `Module` assumed to match). Names are collected by
  `@ExpoModule`/`@SharedObject` into `Events(…)`.

## Verified core DSL signatures

The contract generated code must match. All paths under
`…/expo/main/packages/expo-modules-core/ios`.

**Base classes**
- `Module = AnyModule & BaseModule` (`Core/Modules/Module.swift:29`). Module init is
  `required init(appContext:)`; overriding `init()` is unavailable — use lifecycle.
- View base: `public typealias ExpoView = ExpoFabricView` (`Core/ExpoView.swift:3`);
  `required public init(appContext: AppContext? = nil)` (`Fabric/ExpoFabricView.swift`).

**Module-level factories**
- `Name(_ name: String) -> AnyDefinition` (`ModuleFactories.swift:4`).
- `Events(_ names: String...) -> EventsDefinition` and `Events(_ names: [String])`
  (`ObjectFactories.swift:33`).
- `OnStartObserving(_ event: String? = nil, _ closure:)` / `OnStopObserving(...)`
  (`ObjectFactories.swift:47`).
- `OnCreate(...)`, `OnDestroy(...)`, `OnAppContextDestroys(...)`
  (`EventListenersFactories.swift:4`).
- **No `Exceptions(...)` factory exists** → out of scope.
- `Function`/`AsyncFunction`: name + function-reference / name + closure overloads
  confirmed; existing macro output stays valid.
- `Constant<Value: AnyArgument>(_ name, get:) -> ConstantDefinition<Value>`
  (`ConstantFactories.swift:11`); `Constants(...)` dict form is deprecated. (Not
  emitted — see the `@Constant` note above.)

**Property + setters**
- `Property<Value, OwnerType>(_ name, get:)` and a no-owner getter overload
  (`PropertyFactories.swift:11,18`).
- Chained `.set` setter (`PropertyDefinition.swift:105`) — see
  [Property getter + setter](#property-getter--setter).

**Views**
- `View<ViewType: UIView>(_ viewType:, @ViewDefinitionBuilder<ViewType> _ elements)
  -> ViewDefinition<ViewType>` (`Factories/ViewFactories.swift:10`). Concrete return
  type, not `AnyViewDefinition`. (SwiftUI overloads exist; UIKit-only for v1.)
- `Prop<ViewType, PropType: AnyArgument>(_ name, _ setter: @MainActor (ViewType, PropType) -> Void)`
  + `defaultValue` overload (`ViewFactories.swift:38,52`). **Superseded by the props
  object** — listed for reference.
- View events (core today): names from `Events("onX")`; dispatcher is a property on
  the view/props (`var onTap = EventDispatcher()`), discovered via `Mirror` in
  `setUpEvents`. **Our design drops `EventDispatcher`** (see events model).
- View lifecycle: only `OnViewDidUpdateProps<ViewType: UIView>(...)`
  (`ViewFactories.swift:70`). No `OnViewDestroys`.

**Existing macro declarations (the pattern to copy)** — `ios/Core/ExpoModulesMacros.swift`:
- `@attached(peer) public macro JS(_ jsName: String? = nil) = …`
- `@attached(member, names: named(_synthesizedDefinition), named(appContext), named(init)) public macro ExpoModule(_ name: String? = nil, classes: [Any.Type] = []) = …`
- `@attached(member, names: named(_synthesizedClassDefinition)) public macro SharedObject(_ name: String? = nil) = …`
- All point at `module: "ExpoModulesMacros"`.

## Core dependencies

**1. The `_synthesized…` rename must land in core.** Core on `expo/main` still uses
the old names: `_exposedDefinition` / `_exposedClassDefinition` in
`ExpoModulesMacros.swift` `names:` lists and the `AnyModule._exposedDefinition()`
requirement. Until core's declarations and protocol are renamed to match, a module
built with the new plugin won't satisfy the declared `names` and won't conform.

**2. Unified `@ViewProps` runtime (UIKit).** The props object is a **`struct`** for
v1 (value semantics, for performance — see [`@ViewProps`](#viewprops)), so the contract
must be value-friendly. The macro depends on core adding:
1. A way to register a typed props `Record` **struct** for a UIKit `ExpoView` (a
   `Props(MyProps.self)` definition element, or a `View<Props, ViewType>` overload).
2. A typed **`var props: Props`** on the base view, always holding the current props.
3. In `updateProps(_:)`: decode the incoming dict into a `MyProps` value, capture
   `oldProps = view.props`, **set `view.props = newProps` first**, then call
   `view.onViewPropsChanged(oldProps:)`. So inside the callback `self.props` is already
   the new value and `oldProps` is the previous one.
4. An overridable `open func onViewPropsChanged(oldProps: Props?)` on the base view
   (generic or associated props type). `oldProps` is **`nil` on the first application**
   (initial mount — no previous value); `view.props` is non-optional and always current.
4. **Event dispatch by name**, not by mutating a stored closure: since props are a
   value type, core can't assign a handler onto a function-typed field the way
   `setUpEvents` does for `EventDispatcher` today. The synthesized event property
   instead calls a core-held dispatcher keyed by event name; core exposes that entry
   point.

**3. Props protocol split (for SwiftUI; deferred).** To let `@ViewProps` be a `struct`
*or* `class` and have a `struct` props be rejected only on the SwiftUI path, the single
`ExpoSwiftUI.ViewProps` (today a class) must split into a **value** props protocol and a
**class-bound observable** props protocol (`: AnyObject, ObservableObject`), with
SwiftUI's `View<Props>` bound on the latter. A `struct` props then fails to conform at a
SwiftUI view → clean compiler error; no macro type-check needed. UIKit binds on the
value protocol. (See [`@ViewProps`](#struct-or-class--the-conformance-carries-the-constraint).)

**4. Typed `Module.emit`.** Module events synthesize a call to
`emit<P: AnyArgument>(event:payload:)`, which `SharedObject` already has
(`SharedObject.swift:102`) but `Module`/`BaseModule` does not (it has only the
dict-based `sendEvent(_:_: [String: Any?])`). Add the same typed `emit` to `BaseModule`
so module and shared-object events share one mechanism and accept any `AnyArgument`
payload. (See [Module events](#module-events).)

**5. Swift 6.2 floor (for phase-2 binding names).** The phase-2 bindings use backtick
raw identifiers (`` `#add` ``, SE-0451), which require **Swift 6.2 in the consumer module**
where the generated code compiles. Core / consumer modules are `swift_version 6.0` today,
so this is gated on raising that floor (the macro plugin is already on 6.2). Fallback
until then: leading-underscore binding names (`_expoBind_…`), no version requirement.

**6. `StaticProperty` for shared objects.** `@JS static func` maps to the existing
`StaticFunction` (decorates the constructor), but there's **no `StaticProperty`** in core
(class properties decorate an instance, `ClassDefinition.swift:91`). A `@JS static var`
needs a core `StaticProperty` that decorates the constructor object. (See
[Static vs. instance members](#static-vs-instance-members).)

Until these land, generated `@ViewProps`/`@ExpoView`/`@Event` code won't run; the macro
tests verify expansion shape only, not runtime.

## Implementation plan

Phase-1 staging (DSL coverage). Phase 2 (direct JSI binding) and phase 3 (TS
generation) are sequenced after, each gated on its own core/tooling contract — see
those sections. Each step = PR + tests + `node build.js` (rebuild the plugin binary
before committing); each new impl struct → add to `providingMacros` in `Plugin.swift`.

1. **Helper refactor.** Extract the duplicated param-rewrite/closure builders from
   `SharedObjectMacro.swift` into `MacroHelpers.swift`; factor `@Record`'s
   field-descriptor synthesis out of `RecordMacro.swift` for `@ViewProps` reuse. No
   behavior change.
2. **Module property setters.** Establishes the property-modifier pattern. (Module
   lifecycle is core-only override work; confirm the rename lands in core.)
3. **`@ViewProps` macro.** New `ViewPropsMacro.swift` reusing the record field
   synthesis, plus view-props conformance and function-typed-field event
   recognition. **Gated on the core props/events contract.**
4. **`@ExpoView` macro.** New `ExpoViewMacro.swift`, `_synthesizedViewDefinition()`,
   `: ExpoView` check, props metatype arg, `Props(...)`/`View<Props,_>` wrapper,
   event-name gathering, `@ExpoModule(views:)` wiring. **Gated on the core contract.**
5. **`@SharedObject` parity** — class-level `Events` + property setters.
6. **Module + view events** — typed function-typed members/fields and their send
   synthesis, once the events contract is pinned.

## Testing

- `assertExpansion(input, expandedSource:)` pairs in the existing style; new suites
  `ViewPropsMacroTests.swift`, `ExpoViewMacroTests.swift`. Whitespace must match
  (output is string-spliced).
- Error paths: `@ExpoView` on non-class / missing `: ExpoView`; `@ViewProps` on an
  unsupported decl kind; etc.
- `swift test --package-path apple` green after each stage.
- **Caveat:** these tests verify *expansion shape*, not real compilation against
  core. Integration is only proven by building a real module against the paired core
  PR — state this in every PR.

## Open questions

1. **Core view contract** — `Props(_:)` element vs `View<Props,_>` overload; the
   props-object conformance/marker; the `onViewPropsChanged` base-class shape
   (generic vs associated type); the function-typed-field event wiring in
   `setUpEvents`. The macro output can't be pinned until this is decided; owned by
   the core side.
2. **`GroupView` / `ViewName`** — in scope or follow-up?
3. **Record field opt-out** — with all stored properties fields by default, how to
   exclude one (an `@Ignore` attribute vs. a convention), and how a non-convertible
   stored property is handled (diagnostic vs. silent skip).
4. **Discriminated unions** — `@Union` matches structurally in declaration order for v1;
   a tag-based mode (`@Union(discriminator: "type")`) for overlapping payload shapes is a
   deferred follow-up. Also: confirm `Union` is the right attribute name (vs. `JSUnion`).
5. **`@Event` name override** — JS event name comes from the property name; a per-event
   override (`@Event("customName")`) if needed is a small follow-up.
6. **Phase 3 front end** — `expo-type-information` already parses Swift modules (via
   SourceKitten) and emits TS; phase 3 adapts it to the new attributes. Open: keep
   SourceKitten or move to SwiftSyntax for consistency with the macro toolchain.

Resolved: events → typed payloads (`AnyArgument`), no `EventDispatcher`; view events
fold into `@ViewProps` function-typed fields; **module & shared-object events are a
`@Event` function-typed property → macro synthesizes a computed closure dispatching into
the typed `emit<P: AnyArgument>` (same on both; needs `Module.emit` added to core)**;
module + view lifecycle → overridable instance methods (core-called); view props →
single `@ViewProps` object (no `@Prop`), exposed as non-optional `self.props` (always
current); `onViewPropsChanged(oldProps:)` gets only the previous props, typed `Props?`
(`nil` on first application); `@ViewProps` distinct from `@Record`; no
`@Constant` macro; `@ExpoView` props via metatype arg; `@Record`/`@ViewProps` fields
are all stored properties by default — `@Field` only for options; field requiredness is
**inferred** (default value → optional; optional type → nullable+optional; non-optional
no-default → required); **`@ViewProps` may be
a `struct` (UIKit) or `class` (SwiftUI) — `@ViewProps` emits a value vs. class-bound
observable props conformance, and a `struct` used by a SwiftUI view is a compile error
via that conformance (no macro type-check). Needs a core props-protocol split; SwiftUI
deferred past v1**. Async: **drop Promise-based async; `async` Swift keyword →
JS `Promise`; `async` functions stamped `@JavaScriptActor`; body runs synchronously on
the JS thread until the first suspension (JS-like)**. Unions: **`@Union` on an enum =
typed N-case union (tagged, no `Any?`, → TS `A | B | C`); `Either` kept for inline
2-type; structural match in declaration order, discriminated mode deferred**. Phase 2:
**per-member bindings named with backtick raw identifiers (`` `#add` ``, never called by
users; needs Swift 6.2 in the consumer), installed by one generated
`_decorateJavaScriptObject(_ object:…)` that decorates the JS object core supplies (module
object / SO prototype / constructor) — mirrors `ObjectDefinition.decorate(object:)`; each
binding *is* the host-function body `(this, arguments) -> JavaScriptValue`, the decorate
function does the `createFunction` call (parameter is `borrowing`, matching
`ObjectDefinition.decorate`)**. Shared objects: **`static` Swift modifier marks JS-static
members (→ constructor, `StaticFunction`) vs instance (→ prototype). All shared-object
bindings are `static func`s (class-level decoration); an instance-member binding recovers
its receiver from JS `this`, a static-member binding calls the Swift `static` member. A JS
instance + static member sharing a name disambiguate by a `` `#static.name` `` qualifier
(same scheme as property `` `#ready.get` ``). `static var` needs a core `StaticProperty`.
Decoration is **class-level, once per class** — `static func _decorateJavaScriptClass`
sets up constructor (statics) + prototype (instance funcs *and* properties, receivers from
`this`); no per-instance pass. A module decorates its single object via
`_decorateJavaScriptObject` with instance-method bindings on real `self`**.

## Further ideas

Beyond the three phases, but enabled by the same source-level description:

- **JS/JSI binding generation** — beyond `.d.ts` (phase 3), the same source
  description could drive generated JS glue, reducing hand-written
  `requireNativeModule` boilerplate.
- **Android / Kotlin parity** — an equivalent annotation-processing path (KSP) so a
  single conceptual module surface generates both platforms' definitions and shared
  TS types.
- **Diagnostics from the description** — lint native modules against the generated
  surface (e.g. flag a `@JS` member whose payload type isn't JS-convertible) at build
  time rather than runtime.
- **Dropping the inheritance clause entirely** — the `@ExpoModule`/`@ExpoView`
  metatype-arg design (props not tied to the inheritance line) is a step toward
  protocol-izing the base classes so `: Module` / `: ExpoView` become optional, with
  the macro supplying all conformances.

## Risks

- **Out-of-repo coupling (high).** Generated code only compiles against matching
  core symbols/declarations; the `_synthesized…` rename is a live example where this
  repo and core have already diverged. Every stage needs a paired core PR, and green
  tests here do **not** prove integration.
- **The view contract is a hard dependency, not just coupling (high).** The unified
  `@ViewProps` model can't run on UIKit until core ships the props-object decode +
  `onViewPropsChanged` runtime + function-field event wiring. View stages should not
  merge ahead of that core work.
- **Whitespace-sensitive tests** — the helper refactor limits duplication that would
  otherwise multiply formatting-drift breakage.
- **Async execution semantics depend on the executor contract.** The "synchronous up
  to the first suspension" behavior (see [`@JS` › Async functions](#async-functions))
  holds only if `@JavaScriptActor`'s custom `SerialExecutor` correctly reports being on
  the JS thread (SE-0471/SE-0424). If that's wrong, same-thread async calls would hop
  and lose the JS-like prefix. Also: stamping `@JavaScriptActor` on `async` functions
  reverses current macro behavior — verify it doesn't over-isolate functions that
  intentionally hop off the JS thread.
