import SwiftSyntax

/**
 A `@JS func` collected for **direct JSI binding**. Instead of describing the function with a
 `Function(...)` / `AsyncFunction(...)` DSL entry that the runtime interprets per call,
 `@ExpoModule` synthesizes a `_decorateModule` that binds each such function into the module's JS object
 via the closure-taking `JavaScriptObject.setProperty(_:)`, with the decode-call-encode body
 inlined into the closure. This omits the `[Any]`/`toTuple` dynamic-call path: every argument is
 decoded individually by its static type.

 The receiver is the module's real `self` (a module is a singleton instance), so the body calls
 `self.<name>(...)` directly and ignores the JS `this`. An `async` `@JS func` produces an `async`
 closure body and is installed through the async `setProperty(_:)` overload (so JS gets a promise).
 */
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

  /**
   The `#name` host-function body: a `@JavaScriptActor private func` matching the
   `createFunction` closure shape `(this, arguments) throws -> JavaScriptValue`, threading
   `appContext`/`runtime` in as parameters. It checks arity, decodes each argument by its static
   type — primitives through a direct typed accessor (`asDouble()`, …) on a borrowed
   `JavaScriptUnownedValue`, other types through the
   `T.getDynamicType()` converter — calls `self.<name>(...)`, and converts the result back to JS.
   */
  /// The decode-call-encode statements that form the host-function body, indented with the given
  /// prefix. Arity guard, then per-argument decode (primitives via a direct typed accessor like
  /// `asDouble()` on a zero-copy `arguments.unownedValue(at:)`, others via `getDynamicType().cast(...)`),
  /// the `self.<name>(...)` call, and the
  /// result encode (primitives via `toJavaScriptValue(in:)`, others via `castToJS(...)`).
  private func bodyStatements(indent: String) -> String {
    var lines: [String] = []

    lines.append(
      """
      guard arguments.count == \(parameters.count) else {
        throw Exception(name: "InvalidArgumentCount", description: "Function '\(jsName)' expects \(parameters.count) argument(s), but got \\(arguments.count)")
      }
      """)

    var callArguments: [String] = []
    for (index, parameter) in parameters.enumerated() {
      let type = parameter.type.trimmedDescription

      // Primitives decode through a direct typed accessor (`asDouble()`, etc.) on a borrowed
      // `JavaScriptUnownedValue` — no owning `JavaScriptValue` allocation, no `jsi::Value` copy, no
      // `getDynamicType()` allocation, no `Any` boxing, no force-cast — while still validating and
      // throwing `TypeError` on a mismatch. Other types fall back to the dynamic converter, which
      // needs an owning value, so they index the buffer directly.
      if let accessor = fastDecodeAccessor(for: type) {
        lines.append("let arg\(index) = try arguments.unownedValue(at: \(index)).\(accessor)()")
      } else {
        lines.append(
          "let arg\(index) = try \(type).getDynamicType().cast(jsValue: arguments[\(index)], appContext: appContext) as! \(type)")
      }

      let label = parameter.firstName.text
      callArguments.append(label == "_" ? "arg\(index)" : "\(label): arg\(index)")
    }

    let tryKeyword = (isThrowing || isAsync) ? "try " : ""
    let awaitKeyword = isAsync ? "await " : ""
    let callExpression =
      "\(tryKeyword)\(awaitKeyword)self.\(swiftName)(\(callArguments.joined(separator: ", ")))"

    if let returnType {
      lines.append("let result = \(callExpression)")
      // Primitives encode through `toJavaScriptValue(in:)` (the typed `JavaScriptRepresentable`
      // conversion) — no `Any`, no dynamic-type allocation. Others go through the dynamic converter.
      if fastDecodeAccessor(for: returnType) != nil {
        lines.append("return result.toJavaScriptValue(in: runtime)")
      } else {
        lines.append("return try \(returnType).getDynamicType().castToJS(result, appContext: appContext, in: runtime)")
      }
    } else {
      lines.append(callExpression)
      lines.append("return .undefined")
    }

    return lines
      .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
      .map { indent + $0 }
      .joined(separator: "\n")
  }

  /// The `setProperty` statement that installs this function on the JS object. The decode-call-encode
  /// body is inlined directly into the closure passed to the closure-taking `setProperty` overload
  /// (which creates the host function under the hood) — no separate named binding. For an `async`
  /// function the body `await`s the call, which selects the async `setProperty` overload (so JS
  /// receives a promise).
  ///
  /// Capture mirrors core's `SyncFunctionDefinition.build`: `self` (the module) is captured
  /// **strong** — the host-function closure is what keeps the native callable alive for as long as
  /// JS can invoke it; its lifetime is bounded by the JS VM's garbage collection of the object.
  /// `appContext` is captured **weak** (and guarded) so it doesn't form a real retain cycle through
  /// the app context. When no argument or return value goes through the dynamic-type converter the
  /// body never references `appContext`, so the capture and guard are omitted to avoid the
  /// unused-capture warning.
  var decorateStatements: String {
    let captureList = usesAppContext ? "[weak appContext, self]" : "[self]"
    let guardClause = usesAppContext
      ? """

          guard let appContext else {
            throw Exceptions.AppContextLost()
          }
      """
      : ""
    return """
        object.setProperty("\(jsName)") { \(captureList) this, arguments in\(guardClause)
      \(bodyStatements(indent: "    "))
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

/**
 The single generated function that decorates the module's JS object. Core supplies the object;
 this binds every `@JS func` into it via one inlined `setProperty` closure per function. Mirrors
 core's `ObjectDefinition.decorate(object:)`, including its `borrowing` object parameter (it
 mutates through the reference without reassigning or taking ownership). Named `_decorateModule`
 with the leading-underscore convention for synthesized members the **runtime calls by name**; the
 `ExpoModule` suffix names the `@ExpoModule` macro it came from (a shared object's counterpart is
 `_decorateSharedObject`).
 */
internal func buildDecorateJavaScriptObject(functions: [JSFunction]) -> DeclSyntax {
  let body = functions.map { $0.decorateStatements }.joined(separator: "\n")
  return """
    @JavaScriptActor
    public func _decorateModule(object: borrowing JavaScriptObject, in runtime: JavaScriptRuntime, appContext: AppContext) throws {
    \(raw: body)
    }
    """
}

/// The throwing `JavaScriptUnownedValue` accessor that decodes the given primitive type directly,
/// bypassing the dynamic-type converter (`asDouble()` for `Double`, etc.). Returns `nil` for
/// types without a dedicated accessor — arrays, records, optionals, shared objects, other numeric
/// widths — which decode through `getDynamicType().cast(...)`.
private func fastDecodeAccessor(for type: String) -> String? {
  switch type {
  case "Bool":
    return "asBool"
  case "Int":
    return "asInt"
  case "Double":
    return "asDouble"
  case "String":
    return "asString"
  default:
    return nil
  }
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
