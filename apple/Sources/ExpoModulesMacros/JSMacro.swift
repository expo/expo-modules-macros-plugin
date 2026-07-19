import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro applied to module / shared-object members that should be exposed to JavaScript.
/// `@ExpoModule` and `@SharedObject` discover declarations carrying this attribute and generate the
/// corresponding `Function` / `AsyncFunction` / `Property` / `Constructor` registrations; that part
/// of the expansion lives in those macros.
///
/// On its own, `@JS` emits one thing: a never-called peer that asserts each type crossing the JS
/// boundary is convertible in the direction it travels — arguments are `JavaScriptDecodable`, return
/// values are `JavaScriptEncodable` (a settable property's value type is both). Because it's a
/// **peer** of the marked member, a non-conforming type produces a compile error located on the
/// user's own `@JS` declaration rather than on the enclosing `@ExpoModule`. The assertion mechanism
/// itself is shared (see `directionalConformanceAssertion`); `@JS` only supplies the boundary types,
/// split by direction, that it reads off the declaration.
///
/// Usage:
///
///   @JS
///   func greet(name: String) -> String { ... }
///
///   @JS("doWork")
///   func performWork() async throws { ... }
///
///   @JS
///   var status: String { "ok" }
public struct JSMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    diagnoseFreeFormTypes(in: declaration, in: context)

    guard let member = boundaryMember(of: declaration),
      let assertion = directionalConformanceAssertion(
        name: member.name,
        decodableTypes: member.decodableTypes,
        encodableType: member.encodableType,
        isStatic: member.isStatic
      ) else {
      return []
    }
    return [assertion]
  }
}

/// Emits the free-form (`Any` / `[Any]` / `[String: Any]`) diagnostics for a `@JS` declaration.
///
/// A free-form type is only supported crossing the boundary as an **argument**, decoded through
/// `JavaScriptValue.decodeAny…`; there is no free-form encode, so any position that encodes is a hard
/// error. That means:
/// - a function/constructor **parameter** typed free-form gets a warning steering to
///   `[String: JavaScriptValue]` (the type-safe alternative), but compiles;
/// - a function **return** typed free-form is an error (it would need to encode);
/// - a **property** typed free-form is an error regardless of settability, because its getter always
///   encodes.
///
/// Types are matched by their written spelling on the type node, so the diagnostic points at the
/// offending type in the user's source.
private func diagnoseFreeFormTypes(
  in declaration: some DeclSyntaxProtocol,
  in context: some MacroExpansionContext
) {
  if let funcDecl = declaration.as(FunctionDeclSyntax.self) {
    warnFreeFormArguments(funcDecl.signature.parameterClause.parameters, in: context)
    if let returnType = funcDecl.signature.returnClause?.type,
      isFreeFormBoundaryType(returnType.trimmedDescription) {
      context.diagnose(
        Diagnostic(node: returnType, message: freeFormReturnError(for: returnType.trimmedDescription)))
    }
    return
  }

  // A constructor decodes its arguments exactly like a function; it has no return value to encode, so
  // only the argument warning applies.
  if let initDecl = declaration.as(InitializerDeclSyntax.self) {
    warnFreeFormArguments(initDecl.signature.parameterClause.parameters, in: context)
    return
  }

  if let varDecl = declaration.as(VariableDeclSyntax.self),
    let type = varDecl.bindings.first?.typeAnnotation?.type,
    isFreeFormBoundaryType(type.trimmedDescription) {
    context.diagnose(
      Diagnostic(node: type, message: freeFormPropertyError(for: type.trimmedDescription)))
  }
}

/// The tail of a free-form encode error: the reshaped `JavaScriptValue` alternative when the type is a
/// container (`[String: Any]` -> `[String: JavaScriptValue]`), otherwise the passthrough suggestion
/// for a bare `Any`. Both conform to the codable protocols, so either is a valid fix.
private func suggestedAlternative(for freeFormType: String) -> String {
  if let reshaped = typedFreeFormReplacement(for: freeFormType), reshaped != "JavaScriptValue" {
    return "Use '\(reshaped)', or 'JavaScriptValue' to pass a JS value through unchanged."
  }
  return "Use a concrete type, or 'JavaScriptValue' to pass a JS value through unchanged."
}

/// Emits the steering warning for each free-form parameter in a list. Shared by the function and
/// constructor cases, which both decode their arguments through the same path.
private func warnFreeFormArguments(
  _ parameters: FunctionParameterListSyntax,
  in context: some MacroExpansionContext
) {
  for parameter in parameters {
    let type = parameter.type.trimmedDescription
    guard let suggested = typedFreeFormReplacement(for: type) else {
      continue
    }
    context.diagnose(
      Diagnostic(
        node: parameter.type,
        message: freeFormArgumentWarning(for: type, suggesting: suggested)))
  }
}

private func freeFormArgumentWarning(
  for freeFormType: String,
  suggesting suggestedType: String
) -> JSDiagnosticMessage {
  return JSDiagnosticMessage(
    "Prefer '\(suggestedType)' over the free-form '\(freeFormType)' for a @JS argument. Free-form decoding boxes every value as 'Any' (slower, no static typing); the 'JavaScriptValue' element keeps each value inspectable without erasing it.",
    id: "js-free-form-argument",
    severity: .warning
  )
}

private func freeFormReturnError(for freeFormType: String) -> JSDiagnosticMessage {
  return JSDiagnosticMessage(
    "A @JS function can't return the free-form '\(freeFormType)': there's no way to encode an untyped value back to JavaScript. \(suggestedAlternative(for: freeFormType))",
    id: "js-free-form-return",
    severity: .error
  )
}

private func freeFormPropertyError(for freeFormType: String) -> JSDiagnosticMessage {
  return JSDiagnosticMessage(
    "A @JS property can't have the free-form '\(freeFormType)': its getter would have to encode an untyped value back to JavaScript, which isn't supported. \(suggestedAlternative(for: freeFormType))",
    id: "js-free-form-property",
    severity: .error
  )
}

private struct JSDiagnosticMessage: DiagnosticMessage {
  let message: String
  let diagnosticID: MessageID
  let severity: DiagnosticSeverity

  init(_ message: String, id: String, severity: DiagnosticSeverity) {
    self.message = message
    self.diagnosticID = MessageID(domain: "ExpoModulesMacros", id: id)
    self.severity = severity
  }
}

/// What an assertion peer needs about the `@JS` member it sits beside: a name (to keep the peer unique
/// among siblings), the boundary types split by conversion direction, and whether the member is
/// type-level. Arguments (and a settable property's incoming value) are decoded; return values (and a
/// property's outgoing value) are encoded, so each is asserted against the protocol for its direction.
private struct BoundaryMember {
  let name: String
  /// Types decoded from JS: function/constructor arguments, and a settable property's value type.
  let decodableTypes: [String]
  /// The single type encoded to JS: a function's return type, or a property's value type on read;
  /// `nil` when the member produces nothing JS-visible (a `Void` function).
  let encodableType: String?
  /// True for `static`/`class` members, so the peer is emitted in the same metatype context.
  let isStatic: Bool
}

/// Reads the boundary member off a `@JS` declaration, splitting its types by conversion direction. A
/// function contributes its parameter types (decodable) and its return type when non-Void (encodable);
/// a property contributes its value type as encodable (the getter) and also as decodable when settable
/// (the setter). Composed types (`[Int]`, `String?`, …) are kept verbatim, their conditional
/// conformances transitively constraining the elements. Returns `nil` for declaration kinds `@JS`
/// doesn't read types from, or a property whose type isn't spelled out (a syntactic macro can't
/// recover it).
private func boundaryMember(of declaration: some DeclSyntaxProtocol) -> BoundaryMember? {
  if let funcDecl = declaration.as(FunctionDeclSyntax.self) {
    let decodableTypes = funcDecl.signature.parameterClause.parameters.map { $0.type.trimmedDescription }
    let returnType = funcDecl.signature.returnClause?.type
    let encodableType = returnType.flatMap { isVoidType($0) ? nil : $0.trimmedDescription }
    return BoundaryMember(
      name: funcDecl.name.text,
      decodableTypes: decodableTypes,
      encodableType: encodableType,
      isStatic: isTypeLevel(funcDecl.modifiers)
    )
  }

  if let varDecl = declaration.as(VariableDeclSyntax.self),
    let binding = varDecl.bindings.first,
    let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
    let type = binding.typeAnnotation?.type {
    // A `let`, or a `var` with no setter, is read-only (encodable only). A settable `var` is also
    // decoded on write, so its value type is asserted in both directions.
    let typeText = type.trimmedDescription
    let isVar = varDecl.bindingSpecifier.tokenKind == .keyword(.var)
    let isSettable = isVar && bindingIsSettable(binding)
    return BoundaryMember(
      name: identifier.identifier.text,
      decodableTypes: isSettable ? [typeText] : [],
      encodableType: typeText,
      isStatic: isTypeLevel(varDecl.modifiers)
    )
  }

  return nil
}

/// True when a return clause is written as `Void` / `()` — nothing crosses the boundary, so it needs
/// no conformance assertion. (A missing return clause never reaches here: `returnClause` is `nil`.)
private func isVoidType(_ type: TypeSyntax) -> Bool {
  let text = type.trimmedDescription
  return text == "Void" || text == "()"
}
