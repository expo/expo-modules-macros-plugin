<p>
  <a href="https://docs.expo.dev/modules/">
    <img
      src=".github/resources/expo-modules-macros.svg"
      alt="expo-modules-macros-plugin"
      height="64" />
  </a>
</p>

Swift compiler plugin that implements the macros behind the Expo Modules API. [`expo-modules-core`](https://github.com/expo/expo/tree/main/packages/expo-modules-core) declares them, this package expands them.

```swift
import ExpoModulesCore

@ExpoModule(classes: [Cache.self])
public final class MyModule {
  @JS
  func greet(name: String) -> String {
    "Hi, \(name)"
  }

  @JS("doWork")
  func performWork() async throws { ... }

  @Event
  var onProgress: (ProgressEvent) -> Void
}

@SharedObject
final class Cache: SharedObject {
  @JS
  init(name: String) { ... }

  @JS
  func get(_ key: String) -> String? { ... }
}
```

Each `@JS` member is bound straight into the JavaScript object, with argument decoding, the call and result encoding inlined into the binding. There is no dynamic per-call path.

You don't install this package directly. `expo-modules-core` depends on it, so every Expo project already has it. The published package ships a prebuilt universal macOS binary at `apple/ExpoModulesMacros-tool`, so nobody has to build the plugin.

# Macros

| Macro | Applies to |
| --- | --- |
| `@ExpoModule(_ name: String? = nil, classes: [Any.Type] = [])` | a module class |
| `@JS(_ jsName: String? = nil, _ options: JSOptions...)` | a member to expose |
| `@Event(_ name: String? = nil, sync: Bool = false)` | a function-typed `var` |
| `@SharedObject(_ name: String? = nil)` | a `SharedObject` subclass |
| `@Record()` | a record type |
| `@Union()` | an enum whose cases carry one value each |

A few things that aren't obvious from the signatures:

- `@ExpoModule` synthesizes everything that inheriting from `Module` used to provide, so a module class can have any superclass, or none.
- `@JS` checks that each type crossing the boundary is convertible in the direction it travels. Errors land on the marked declaration, not on the enclosing type. `.concurrent` runs an `async` body off the JavaScript thread, with arguments and results still converted on it.
- `@Event` drops a leading `on` from the property name (`onProgress` emits `progress`). `sync: true` dispatches inline instead of asynchronously.
- `@Record` takes every stored property as a field, no wrapper needed. A default value makes it optional, an optional type makes it nullable.
- `@Union` decodes in case order and the first match wins, so put the more specific case first. It maps to a TypeScript union.

Per-macro documentation for module authors lives next to the declarations in `expo-modules-core`, in `ios/Core/ExpoModulesMacros.swift`.

# Scanner

The compiler launches a plugin with no arguments and talks to it over stdin, so the same binary treats any argument as a scanner invocation:

```
ExpoModulesMacros-tool <subcommand> [options] <path> [<path> ...]

subcommands:
  scan-modules   fast scan for top-level @ExpoModule types (autolinking)
  scan-exports   deep scan of the full JS-exported surface (type generation)

options (scan-modules only):
  --platform <os>   evaluate '#if os(...)' against this platform
  --define <flag>   treat a conditional compilation flag as set; repeatable
```

Paths are `.swift` files or directories to walk. Both subcommands write a JSON report to stdout.

# Loading the plugin

`expo-modules-core` declares each macro with `#externalMacro(module: "ExpoModulesMacros", type: …)`. On `pod install`, `expo-modules-autolinking` locates this package and appends

```
-Xfrontend -load-plugin-executable -Xfrontend <plugin>/apple/ExpoModulesMacros-tool#ExpoModulesMacros
```

to `OTHER_SWIFT_FLAGS` for `ExpoModulesCore`, everything that depends on it, and their test specs. Renaming the plugin module or a macro type means updating `#externalMacro` on the other side.

# Development

Needs macOS 13+ and Swift 6.2, which means Xcode 26 or newer.

```sh
cd apple
swift build
swift test
```

`npm run build` produces the shipped binary: release builds for arm64 and x86_64, merged with `lipo` into `apple/ExpoModulesMacros-tool` and stripped. SwiftPM only builds macro tools for the host architecture, so the x86_64 slice goes through Rosetta, which the script installs if it's missing. The binary is committed.

# Releasing

Run the **Publish** workflow and pick a release type. It bumps the version, builds, and publishes to npm over OIDC trusted publishing. The commit, tag and GitHub release come after a successful publish, so a failed build leaves the branch alone.

# Contributing

Contributions are very welcome! Please refer to the guidelines described in the [contributing guide](https://github.com/expo/expo#contributing).
