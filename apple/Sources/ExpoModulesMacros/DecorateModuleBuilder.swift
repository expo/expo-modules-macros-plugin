import SwiftSyntax

/// A `@JS func` collected for **direct JSI binding**. Instead of describing the function with a
/// `Function(...)` / `AsyncFunction(...)` DSL entry that the runtime interprets per call, the enclosing
/// macro synthesizes a decorator (`_decorateModule` / `_decorateSharedObject`) that binds each such
/// function into the JS object via the closure-taking `JavaScriptObject.setProperty(_:)`, with the
/// decode-call-encode body inlined into the closure. This omits the `[Any]`/`toTuple` dynamic-call path:
/// every argument is decoded individually by its static type.
///
/// The receiver (see `Receiver`) is the module's `self` for a module binding, or the per-call `_self`
/// unwrapped from the JS `this` for a shared-object binding. An `async` `@JS func` produces an `async`
/// closure body and is installed through the async `setProperty(_:)` overload (so JS gets a promise).
internal struct JSFunction {
  let swiftName: String
  let jsName: String
  let parameters: [FunctionParameterSyntax]
  /// The declared return type as written, or `nil` when the function returns `Void`/nothing.
  let returnType: String?
  let isThrowing: Bool
  let isAsync: Bool

  init(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax) {
    self.swiftName = funcDecl.name.text
    self.jsName = jsNameArgument(of: attribute) ?? funcDecl.name.text
    self.parameters = Array(funcDecl.signature.parameterClause.parameters)

    let declaredReturnType = funcDecl.signature.returnClause?.type
    self.returnType = isVoidType(declaredReturnType) ? nil : declaredReturnType?.trimmedDescription

    let effectSpecifiers = funcDecl.signature.effectSpecifiers
    self.isThrowing = effectSpecifiers?.throwsClause?.throwsSpecifier != nil
    self.isAsync = effectSpecifiers?.asyncSpecifier != nil
  }

  /// The number of leading parameters that must always be supplied: the total minus the maximal
  /// trailing run of *omittable* parameters (each having a default value or an optional type). A
  /// non-omittable parameter part-way through stops the run, since arguments are positional — a
  /// required parameter after an omittable one forces the earlier one to be supplied too.
  private var requiredArgumentCount: Int {
    var required = parameters.count
    for parameter in parameters.reversed() {
      guard isOmittable(parameter) else {
        break
      }
      required -= 1
    }
    return required
  }

  /// The decode-call-encode statements that form the host-function body, indented with the given
  /// prefix. Receiver unwrap (shared objects only), then an arity guard (an exact check when every
  /// parameter is required, otherwise a range check) throwing `Exceptions.ArgumentsRangeMismatch`;
  /// then the decode of the always-present required prefix (primitives via a direct typed accessor
  /// like `asDouble()` on a zero-copy `arguments.unownedValue(at:)`, others via
  /// `getDynamicType().cast(...)`); then the call and result encode (primitives via
  /// `toJavaScriptValue(in:)`, others via `castToJS(...)`). When a trailing run of parameters is
  /// omittable the call branches on `arguments.count`, decoding only the slots that branch actually
  /// has — `arguments[i]` traps past `count`, so a slot the caller didn't pass is never indexed.
  private func bodyStatements(receiver: Receiver, indent: String) -> String {
    let required = requiredArgumentCount
    let maximum = parameters.count
    var lines: [String] = []

    if let unwrap = receiver.unwrapStatement {
      lines.append(unwrap)
    }

    if required == maximum {
      lines.append(
        """
        guard arguments.count == \(maximum) else {
          throw Exceptions.ArgumentsRangeMismatch((functionName: "\(jsName)", received: arguments.count, required: \(required), maximum: \(maximum)))
        }
        """)
    } else {
      lines.append(
        """
        guard arguments.count >= \(required) && arguments.count <= \(maximum) else {
          throw Exceptions.ArgumentsRangeMismatch((functionName: "\(jsName)", received: arguments.count, required: \(required), maximum: \(maximum)))
        }
        """)
    }

    // Decode the required prefix once — these slots are present in every accepted arity, so the
    // decode is shared rather than repeated per branch.
    for index in 0..<required {
      lines.append(decodeStatement(at: index))
    }

    if required == maximum {
      // No omittable trailing run: a single flat call with every argument decoded.
      lines.append(contentsOf: callAndEncodeLines(receiver: receiver, arity: maximum, decodingFrom: required))
    } else {
      // One call shape per accepted arity. Each branch decodes only the trailing slots it has and
      // fills the rest (defaulted params drop their label so Swift applies the default; optional
      // params are passed `nil`). A value-returning function binds the result from a `switch`
      // expression and encodes once after it; a no-return one calls inline in a `switch` statement
      // and returns `.undefined`.
      if returnType != nil {
        lines.append("let result = switch arguments.count {")
      } else {
        lines.append("switch arguments.count {")
      }
      for arity in required...maximum {
        let label = arity == maximum ? "default:" : "case \(arity):"
        lines.append(label)
        for index in required..<arity {
          lines.append("  " + decodeStatement(at: index))
        }
        lines.append("  \(callExpression(receiver: receiver, arity: arity))")
      }
      lines.append("}")
      lines.append(contentsOf: encodeResultLines())
    }

    return lines
      .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
      .map { indent + $0 }
      .joined(separator: "\n")
  }

  /// `let arg<index> = …` decoding the slot at `index` by its static type: a primitive through a
  /// direct typed accessor on a borrowed `JavaScriptUnownedValue` (no owning value, no `jsi::Value`
  /// copy, no `getDynamicType()` allocation, no `Any` boxing, no force-cast — still validating and
  /// throwing `TypeError` on a mismatch), any other type through the dynamic converter (which needs
  /// an owning value, so it indexes the buffer directly).
  private func decodeStatement(at index: Int) -> String {
    let type = parameters[index].type.trimmedDescription
    if let accessor = fastDecodeAccessor(for: type) {
      return "let arg\(index) = try arguments.unownedValue(at: \(index)).\(accessor)()"
    }
    let exprType = expressionType(type)
    return "let arg\(index) = try \(exprType).getDynamicType().cast(jsValue: arguments[\(index)], appContext: appContext) as! \(exprType)"
  }

  /// The `<callee>.<name>(...)` call for the given arity. Slots `0..<arity` are passed their decoded
  /// `arg<i>`; a trailing optional-without-default slot that this arity omits is passed `nil`; a
  /// trailing defaulted slot that this arity omits is dropped entirely so Swift applies its default.
  private func callExpression(receiver: Receiver, arity: Int) -> String {
    var callArguments: [String] = []
    for (index, parameter) in parameters.enumerated() {
      let label = parameter.firstName.text
      let value: String?
      if index < arity {
        value = "arg\(index)"
      } else if hasDefaultValue(parameter) {
        // Omitted defaulted slot: drop it from the call so Swift fills in the default.
        value = nil
      } else {
        // Omitted optional-without-default slot: pass `nil`.
        value = "nil"
      }
      guard let value else {
        continue
      }
      callArguments.append(label == "_" ? value : "\(label): \(value)")
    }
    let tryKeyword = (isThrowing || isAsync) ? "try " : ""
    let awaitKeyword = isAsync ? "await " : ""
    return "\(tryKeyword)\(awaitKeyword)\(receiver.callee).\(swiftName)(\(callArguments.joined(separator: ", ")))"
  }

  /// The flat (single-arity) call-and-encode lines used when no trailing parameter is omittable:
  /// `let result = <callee>.f(...)` then the return encode (or the no-return `<callee>.f(...)` +
  /// `.undefined`).
  private func callAndEncodeLines(receiver: Receiver, arity: Int, decodingFrom: Int) -> [String] {
    var lines: [String] = []
    for index in decodingFrom..<arity {
      lines.append(decodeStatement(at: index))
    }
    if returnType != nil {
      lines.append("let result = \(callExpression(receiver: receiver, arity: arity))")
      lines.append(contentsOf: encodeResultLines())
    } else {
      lines.append(callExpression(receiver: receiver, arity: arity))
      lines.append("return .undefined")
    }
    return lines
  }

  /// Encode the `result` local back to JS and return it: a primitive through `toJavaScriptValue(in:)`
  /// (the typed `JavaScriptRepresentable` conversion — no `Any`, no dynamic-type allocation), any
  /// other type through the dynamic converter. A no-return function returns `.undefined` instead.
  private func encodeResultLines() -> [String] {
    guard let returnType else {
      return ["return .undefined"]
    }
    if fastDecodeAccessor(for: returnType) != nil {
      return ["return result.toJavaScriptValue(in: runtime)"]
    }
    return ["return try \(expressionType(returnType)).getDynamicType().castToJS(result, appContext: appContext, in: runtime)"]
  }

  /// The `setProperty` statement that installs this function on the JS object. The decode-call-encode
  /// body is inlined directly into the closure passed to the closure-taking `setProperty` overload
  /// (which creates the host function under the hood) — no separate named binding. For an `async`
  /// function the body `await`s the call, which selects the async `setProperty` overload (so JS
  /// receives a promise).
  ///
  /// Capture mirrors core's `SyncFunctionDefinition.build`: a module captures its `self` **strong** —
  /// the host-function closure is what keeps the native callable alive for as long as JS can invoke
  /// it; its lifetime is bounded by the JS VM's garbage collection of the object. A shared object
  /// captures nothing of the instance: it recovers the typed receiver from the JS `this` per call.
  /// `appContext` is captured **weak** (and guarded) so it doesn't form a real retain cycle through
  /// the app context. When no argument or return value goes through the dynamic-type converter the
  /// body never references `appContext`, so the capture and guard are omitted to avoid the
  /// unused-capture warning.
  func decorateStatements(receiver: Receiver) -> String {
    // Synchronous `@JS` bindings bind through the unowned-`this` `setProperty` overload, which hands
    // `this` in as a borrowed `JavaScriptUnownedValue` instead of allocating an owning
    // `JavaScriptValue` and forming its `weak`-runtime reference on every call. A module ignores
    // `this`; a shared object unwraps it (still borrowed). The first parameter is typed `borrowing
    // JavaScriptUnownedValue` to select that (otherwise `@_disfavoredOverload`) overload — which
    // requires the *parenthesized, fully typed* parameter list, since Swift rejects a type annotation
    // on a shorthand `{ [capture] name, name in }` parameter. Async functions keep the untyped
    // shorthand and the owning-`this` overload: there is no unowned-`this` async variant and the buffer
    // escapes into the task anyway.
    let captures = receiver.captureClause(usesAppContext: usesAppContext)
    let parameters =
      isAsync
      ? "this, arguments"
      : "(this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer)"

    let object = receiver.decoratedObject
    if usesAppContext {
      return """
          \(object).setProperty("\(jsName)") { \(captures)\(parameters) in
            guard let appContext else {
              throw Exceptions.AppContextLost()
            }
        \(bodyStatements(receiver: receiver, indent: "    "))
          }
        """
    }
    return """
        \(object).setProperty("\(jsName)") { \(captures)\(parameters) in
      \(bodyStatements(receiver: receiver, indent: "    "))
        }
      """
  }

  /// True when the host-function body references `appContext` — i.e. some parameter or the return
  /// type lacks a fast accessor and decodes/encodes through `getDynamicType()`, which threads
  /// `appContext` in.
  private var usesAppContext: Bool {
    if parameters.contains(where: { fastDecodeAccessor(for: $0.type.trimmedDescription) == nil }) {
      return true
    }
    if let returnType, fastDecodeAccessor(for: returnType) == nil {
      return true
    }
    return false
  }
}

/// A `@JS var` collected for **direct JSI binding**. Instead of describing the property with a
/// `Property(...)` DSL entry, the enclosing macro synthesizes a get/set accessor into the JS object
/// inside its decorator (`_decorateModule` / `_decorateSharedObject`): it builds a descriptor object
/// (`enumerable` + `get`, and `set` when the property is settable) and installs it with
/// `object.defineProperty(name, descriptor:)`, mirroring core's `PropertyDefinition.buildDescriptor`.
/// The `get`/`set` host functions are installed the same way `@JS func`s are — the closure-taking
/// `setProperty(_:)` overload, with the read/write body inlined into the closure.
///
/// The receiver (see `Receiver`) is the module's `self` for a module binding, or the per-call `_self`
/// unwrapped from the JS `this` for a shared object. The getter reads `<callee>.<name>` and the setter
/// writes `<callee>.<name> = …`. Decode/encode of the value reuse the same static-type fast path as
/// functions (primitives through a direct typed accessor / `toJavaScriptValue`, other types through
/// the `getDynamicType()` converter).
internal struct JSProperty {
  let swiftName: String
  let jsName: String
  /// The property's value type as written, or `nil` when it couldn't be inferred (no annotation and
  /// no literal default). When `nil` the getter still works (the encode infers from `self.<name>`)
  /// but the setter uses an untyped closure parameter.
  let valueType: String?
  /// Whether the property is settable from JS: `true` for a stored `var` or a computed `var` with an
  /// explicit `set` accessor; `false` for a getter-only computed `var` or a `let`.
  let isSettable: Bool

  /// The statements that install this property's accessor on the JS object, indented for the
  /// decorator body. Builds a descriptor object (`enumerable` + `get`, and `set` when settable) via
  /// the closure-taking `setProperty(_:)` overload — with the read/write body inlined into each
  /// closure — and installs it with `object.defineProperty(name, descriptor:)`. Capture matches the
  /// function bindings: a module captures `self` strong, a shared object captures nothing of the
  /// instance; `appContext` is weak + guarded — and, like functions, the `appContext` capture + guard
  /// are omitted from an accessor whose body never references it (a primitive value, decoded/encoded
  /// without the dynamic converter), to avoid the unused-capture warning. Getter and setter are gated
  /// independently.
  func decorateStatements(receiver: Receiver) -> String {
    let descriptorName = "\(swiftName)Descriptor"
    let callee = receiver.callee
    let object = receiver.decoratedObject
    // A primitive value type encodes/decodes without `getDynamicType()`, so its accessor body never
    // references `appContext`. `nil` (untyped) goes through the dynamic-less `toJavaScriptValue`
    // getter, which also doesn't use it.
    let usesAppContext = valueType.map { fastDecodeAccessor(for: $0) == nil } ?? false
    // A shared object's accessors unwrap the JS `this` into `_self` before reading/writing; a module
    // reads `self` directly. The unwrap leads each accessor body.
    let unwrap = receiver.unwrapStatement.map { "\($0)\n" } ?? ""
    var lines: [String] = []

    lines.append("let \(descriptorName) = runtime.createObject()")
    lines.append("\(descriptorName).setProperty(\"enumerable\", value: true)")

    // Getter: read `<callee>.<name>` and encode the result back to JS.
    let getEncode: String
    if let valueType, fastDecodeAccessor(for: valueType) != nil {
      getEncode = "return \(callee).\(swiftName).toJavaScriptValue(in: runtime)"
    } else if let valueType {
      getEncode =
        "return try \(expressionType(valueType)).getDynamicType().castToJS(\(callee).\(swiftName), appContext: appContext, in: runtime)"
    } else {
      // No known type: fall back to converting whatever `<callee>.<name>` is. This only happens when
      // the declaration has neither an annotation nor a literal default, which is rare for a stored
      // var.
      getEncode = "return \(callee).\(swiftName).toJavaScriptValue(in: runtime)"
    }
    lines.append(
      accessorClosure(
        descriptorName, "get", receiver: receiver, usesAppContext: usesAppContext, body: "\(unwrap)\(getEncode)"))

    // Setter: decode argument 0 by the static type and write `<callee>.<name>`. A typed setter needs
    // a known value type; when the type couldn't be inferred the property is bound getter-only (a
    // settable var with neither an annotation nor a literal default is rare and can't be decoded).
    if isSettable, let valueType {
      let setDecode: String
      if let accessor = fastDecodeAccessor(for: valueType) {
        setDecode = "\(callee).\(swiftName) = try arguments.unownedValue(at: 0).\(accessor)()"
      } else {
        let exprType = expressionType(valueType)
        setDecode =
          "\(callee).\(swiftName) = try \(exprType).getDynamicType().cast(jsValue: arguments[0], appContext: appContext) as! \(exprType)"
      }
      lines.append(
        accessorClosure(
          descriptorName, "set", receiver: receiver, usesAppContext: usesAppContext,
          body: "\(unwrap)\(setDecode)\nreturn .undefined"))
    }

    lines.append("\(object).defineProperty(\"\(jsName)\", descriptor: \(descriptorName))")

    return lines
      .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
      .map { "  " + $0 }
      .joined(separator: "\n")
  }

  /// One `descriptor.setProperty("get"/"set") { … }` accessor entry. The capture list follows the
  /// receiver (a module captures `self` strong; a shared object captures nothing of the instance) and,
  /// when `usesAppContext`, adds `appContext` weak + guarded (matching the function bindings);
  /// otherwise the guard is omitted so a primitive accessor doesn't warn on an unused capture.
  private func accessorClosure(
    _ descriptorName: String, _ key: String, receiver: Receiver, usesAppContext: Bool, body: String
  ) -> String {
    let captures = receiver.captureClause(usesAppContext: usesAppContext)
    // Indent each line of a (possibly multi-line) body to sit one level inside the closure, aligned
    // with the `guard`; a bare `\(body)` interpolation would only indent the first line.
    let indentedBody = body
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { "  \($0)" }
      .joined(separator: "\n")
    // Property `get`/`set` accessors are always synchronous, so they bind through the unowned-`this`
    // `setProperty` overload like sync functions. The parameter list is parenthesized and fully typed
    // because Swift rejects a type annotation on a shorthand closure parameter; the explicit
    // `borrowing JavaScriptUnownedValue` selects the unowned-`this` overload. A module ignores `this`;
    // a shared object unwraps it in the body.
    let parameters = "(this: borrowing JavaScriptUnownedValue, arguments: consuming JavaScriptValuesBuffer)"
    if usesAppContext {
      return """
        \(descriptorName).setProperty("\(key)") { \(captures)\(parameters) in
          guard let appContext else {
            throw Exceptions.AppContextLost()
          }
        \(indentedBody)
        }
        """
    }
    return """
      \(descriptorName).setProperty("\(key)") { \(captures)\(parameters) in
      \(indentedBody)
      }
      """
  }
}

/// The body shared by both decorators: every `@JS func` bound via an inlined `setProperty` closure
/// and every `@JS var` via a `defineProperty` accessor, joined for the function body. The `receiver`
/// selects how each binding reaches its Swift value (module `self` vs. shared-object `_self`).
private func decorateBody(functions: [JSFunction], properties: [JSProperty], receiver: Receiver) -> String {
  let functionBody = functions.map { $0.decorateStatements(receiver: receiver) }
  let propertyBody = properties.map { $0.decorateStatements(receiver: receiver) }
  return (functionBody + propertyBody).joined(separator: "\n")
}

/// The single generated function that decorates the module's JS object. Core supplies the object;
/// this binds every `@JS func` (via an inlined `setProperty` closure) and every `@JS var` (via a
/// `defineProperty` accessor) into it. Mirrors core's `ObjectDefinition.decorate(object:)`, including
/// its `borrowing` object parameter (it mutates through the reference without reassigning or taking
/// ownership). Named `_decorateModule` with the leading-underscore convention for synthesized members
/// the **runtime calls by name**; the `ExpoModule` suffix names the `@ExpoModule` macro it came from (a
/// shared object's counterpart is `_decorateSharedObject`). The bindings call into the module `self`.
internal func buildDecorateJavaScriptObject(functions: [JSFunction], properties: [JSProperty]) -> DeclSyntax {
  let body = decorateBody(functions: functions, properties: properties, receiver: .module)
  return """
    @JavaScriptActor
    public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
    \(raw: body)
    }
    """
}

/// The shared-object counterpart of `_decorateModule`. Core supplies the class `prototype`; this binds
/// every `@JS func` and `@JS var` of the given shared-object type onto it. Because a shared object has a
/// distinct native instance behind each JS object, the bindings are **static** and recover the typed
/// receiver from the JS `this` per call (`try SharedObject.native(from: this.asObject(in: runtime), as: <Type>.self)`)
/// rather than capturing a singleton `self`. The first parameter is `prototype` (not `object` as on
/// `_decorateModule`) because it's the shared class prototype, not an instance. The constructor is
/// bound separately (see `JSConstructor.buildConstructor`). Only emitted when the type has at least one
/// `@JS func`/`var`.
internal func buildDecorateSharedObject(
  functions: [JSFunction], properties: [JSProperty], typeName: String
) -> DeclSyntax {
  let body = decorateBody(functions: functions, properties: properties, receiver: .sharedObject(typeName: typeName))
  return """
    @JavaScriptActor
    public static func _decorateSharedObject(prototype: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
    \(raw: body)
    }
    """
}

/// True when a return clause is absent or written as `Void` / `()` — i.e. the function returns
/// nothing JS-visible, so the binding returns `.undefined`.
private func isVoidType(_ type: TypeSyntax?) -> Bool {
  guard let type else {
    return true
  }
  let text = type.trimmedDescription
  return text == "Void" || text == "()"
}
