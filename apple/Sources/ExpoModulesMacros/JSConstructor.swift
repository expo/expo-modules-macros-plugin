import SwiftSyntax

/// A `@JS init` collected for direct JSI binding. A shared-object type has at most one (JS classes
/// have a single constructor). Instead of a `Constructor { … }` DSL entry, the macro synthesizes an
/// override of `SharedObject._constructSharedObject(...)` that decodes the JS arguments and returns a
/// fresh instance; unlike the method/property bindings it produces the native instance rather than
/// recovering one.
internal struct JSConstructor {
  let parameters: [FunctionParameterSyntax]

  init(initDecl: InitializerDeclSyntax) {
    self.parameters = Array(initDecl.signature.parameterClause.parameters)
  }

  /// The body statements, indented with `indent`: arity guard, per-argument decode (primitives via a
  /// typed accessor, others via the dynamic converter), then `return <Type>(label: arg0, …)`.
  private func bodyStatements(typeName: String, indent: String) -> String {
    var lines: [String] = []

    lines.append(
      """
      guard arguments.count == \(parameters.count) else {
        throw Exceptions.ArgumentsRangeMismatch((functionName: "\(typeName)", received: arguments.count, required: \(parameters.count), maximum: \(parameters.count)))
      }
      """)

    var callArguments: [String] = []
    for (index, parameter) in parameters.enumerated() {
      let type = parameter.type.trimmedDescription

      if let accessor = fastDecodeAccessor(for: type) {
        lines.append("let arg\(index) = try arguments.unownedValue(at: \(index)).\(accessor)()")
      } else {
        let exprType = expressionType(type)
        lines.append(
          "let arg\(index) = try \(exprType).getDynamicType().cast(jsValue: arguments[\(index)], appContext: appContext) as! \(exprType)")
      }

      let label = parameter.firstName.text
      callArguments.append(label == "_" ? "arg\(index)" : "\(label): arg\(index)")
    }

    lines.append("return \(typeName)(\(callArguments.joined(separator: ", ")))")

    return lines
      .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
      .map { indent + $0 }
      .joined(separator: "\n")
  }

  /// The `_constructSharedObject` entry point the runtime calls to build an instance from JS
  /// arguments. Overrides the base `SharedObject` class method so core can dispatch to it through the
  /// concrete type's metatype; the body returns the concrete instance, which promotes to the base
  /// `SharedObject?` return type. `this`/`appContext` may go unreferenced, which is harmless.
  func buildConstructor(typeName: String) -> DeclSyntax {
    return """
      @JavaScriptActor
      public override class func _constructSharedObject(this: JavaScriptValue, arguments: borrowing JavaScriptValuesBuffer, in runtime: JavaScriptRuntime, appContext: AppContext) throws -> SharedObject? {
      \(raw: bodyStatements(typeName: typeName, indent: "  "))
      }
      """
  }
}
