<p>
  <a href="https://docs.expo.dev/modules/">
    <img
      src=".github/resources/expo-modules-macros.svg"
      alt="expo-modules-macros-plugin"
      height="64" />
  </a>
</p>

`@expo/expo-modules-macros-plugin` is the Swift compiler plugin behind the Expo Modules API. It implements the macros that [`expo-modules-core`](https://github.com/expo/expo/tree/main/packages/expo-modules-core) declares, so a module author writes plain Swift declarations and the plugin synthesizes the code that binds them to JavaScript.

The same executable doubles as a source scanner CLI.

# Installation

This package is not meant to be installed directly. It is a dependency of `expo-modules-core`, so every Expo project already has it. The published package contains a prebuilt universal (arm64 + x86_64) macOS binary at `apple/ExpoModulesMacros-tool`, so consumers never build the plugin themselves.

# Macros

- **`@ExpoModule(_ name: String? = nil, classes: [Any.Type] = [])`** on a class. Turns the class into a module: binds its `@JS` members into the module's JavaScript object and resolves the module name from the argument, falling back to the class name. It also synthesizes everything inheriting from `Module` used to provide, so a module class can carry any superclass, or none.
- **`@JS(_ jsName: String? = nil, _ options: JSOptions...)`** on a member of a module or shared object. Marks a function, property or initializer for export. `@ExpoModule` and `@SharedObject` bind each marked member straight into the JavaScript object, with the argument decoding, the call and the result encoding inlined, so there is no dynamic per-call path. The JS name defaults to the Swift name; pass a string to override it. The macro also checks that every type crossing the boundary is convertible in the direction it travels, so a bad type is reported on the author's own declaration rather than on the enclosing type. The `.concurrent` option moves an `async` body off the JavaScript thread while still decoding and encoding on it.
- **`@Event(_ name: String? = nil, sync: Bool = false)`** on a function-typed `var`. Expands the property into a closure that emits the event, so calling the property sends it to JavaScript with the closure's parameter as the payload. The JS name defaults to the property name with a leading `on` stripped. `sync: true` dispatches inline instead of asynchronously.
- **`@SharedObject(_ name: String? = nil)`** on a `SharedObject` subclass. Collects the class's `@JS` members into a class definition that a module exposes through `@ExpoModule(classes:)`.
- **`@Record()`** on a record type. Treats every non-static, non-private, non-computed stored property as a field, with no per-field wrapper, and synthesizes the memberwise initializer, the conversions in both directions, and the `Record` conformance. Requiredness is inferred: a default value makes a field optional, an optional type makes it nullable and optional.
- **`@Union()`** on an enum whose cases each carry one associated value. Models a TypeScript union. Synthesizes the conversions in both directions, a typed accessor per payload type, and the `JavaScriptDecodable` and `JavaScriptEncodable` conformances. Decoding is ordered: the first case whose payload decodes wins, so the more specific case goes first.

How that looks in a module:

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

The author-facing documentation for each macro lives next to its declaration in `expo-modules-core`, in `ios/Core/ExpoModulesMacros.swift`. This repository holds the implementations.

# Scanner

The Swift compiler launches a plugin executable with no arguments and speaks the plugin protocol over stdin, so the binary treats any argument as a scanner invocation instead:

```
ExpoModulesMacros-tool <subcommand> [options] <path> [<path> ...]

subcommands:
  scan-modules   fast scan for top-level @ExpoModule types (autolinking)
  scan-exports   deep scan of the full JS-exported surface (type generation)

options (scan-modules only):
  --platform <os>   evaluate '#if os(...)' against this platform
  --define <flag>   treat a conditional compilation flag as set; repeatable
```

Each path is a `.swift` file or a directory, scanned recursively for `.swift` files. Both subcommands print a JSON report to stdout.

# How the plugin reaches the compiler

`expo-modules-core` declares the macro signatures with `#externalMacro(module: "ExpoModulesMacros", type: …)`. During `pod install`, `expo-modules-autolinking` resolves this package from the core package and appends

```
-Xfrontend -load-plugin-executable -Xfrontend <plugin>/apple/ExpoModulesMacros-tool#ExpoModulesMacros
```

to `OTHER_SWIFT_FLAGS` for `ExpoModulesCore`, every pod that depends on it, and their test specs. Expo's SPM prebuilds pass the same flag when they generate `Package.swift`, so both build systems load the same binary.

The module and type names in `#externalMacro` must stay in sync with `apple/Sources/ExpoModulesMacros/Plugin.swift`.

# Development

Requires macOS 13 or newer and a toolchain with Swift 6.2, which means Xcode 26 or newer.

```sh
cd apple
swift build
swift test
```

`npm run build` runs `apple/build.js`, which builds the release binary for arm64 and x86_64, merges the slices into `apple/ExpoModulesMacros-tool` with `lipo`, strips it, and verifies both slices are present. SwiftPM only builds macro tools for the host architecture, so the x86_64 slice is produced by running the toolchain under Rosetta; the script installs Rosetta if it is missing. The resulting binary is committed to the repository.

# Releasing

The **Publish** workflow is manual (`workflow_dispatch`) and takes a release type. It bumps the version, builds the universal binary, and publishes to npm through OIDC trusted publishing. The commit, tag and GitHub release are created only after the publish succeeds, so a failed build leaves the branch untouched.

# Contributing

Contributions are very welcome! Please refer to the guidelines described in the [contributing guide](https://github.com/expo/expo#contributing).
