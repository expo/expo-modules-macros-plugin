import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Member macro applied to a view-props struct. Classifies every stored property that is not
/// `static`, `private`, `fileprivate`, `lazy` or computed — no `@Field` wrapper needed:
/// a **function-typed property is an event prop**, every other stored property is a **value prop**.
/// It synthesizes the change-tracking surface that a view's `viewPropsChanged(_ diff:)` override
/// consumes:
///
/// - `PropName` — a `String`-backed `CaseIterable` enum with one case per value prop. The raw value
///   is the prop's wire name (always the property name), so the enum doubles as the string → prop
///   translation table (`PropName(rawValue:)` when the runtime maps raw changed keys,
///   `prop.rawValue` for a printable name) with no separate map. Event props have no case: they
///   are wired once at view creation and never participate in change detection.
/// - `Diff` — a typealias for core's generic `PropsDiff<Self>`, so the view override spells the
///   nested `MyProps.Diff`. The diff type itself is **not** generated: `PropsDiff` is one generic
///   core type that reaches the per-props case type through the `AnyViewProps` conformance's
///   `PropName` associated type (`Set<Props.PropName>`), so both its storage and its queries
///   (`changed(_:)`, `oldValue(_:)`, `isFirstUpdate`) evolve in core without regenerating modules.
/// - The `AnyViewProps` conformance (as an extension), which is what lets the generic `PropsDiff`
///   name the enum. Skipped when the author already declares it.
///
/// Author-facing shape:
///
///   @ViewProps
///   struct CardProps {
///     var title: String               // required value prop
///     var color: UIColor = .red       // optional value prop (default applies)
///     var radius: CGFloat?            // nullable + optional value prop
///     var onTap: (TapEvent) -> Void   // event prop — no PropName case
///   }
///
/// Classes are rejected for now: a class props type is the SwiftUI observable path, which is
/// deferred until core splits the props protocols.
public struct ViewPropsMacro: MemberMacro, ExtensionMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let structDecl = declaration.as(StructDeclSyntax.self) else {
      if declaration.is(ClassDeclSyntax.self) {
        throw MacroExpansionErrorMessage(
          "@ViewProps classes (SwiftUI observable props) aren't supported yet: apply it to a struct"
        )
      }
      throw MacroExpansionErrorMessage("@ViewProps can only be applied to a struct")
    }
    let propsTypeName = structDecl.name.text
    let valueProps = try valuePropNames(of: declaration)
    return [
      propNameEnum(cases: valueProps),
      "public typealias Diff = PropsDiff<\(raw: propsTypeName)>",
    ]
  }

  /// Auto-conforms the props type to `AnyViewProps` — the protocol whose `PropName` associated
  /// type lets core's generic `PropsDiff` reference the synthesized enum. The conformance is
  /// skipped when the type already declares it, and non-struct declarations emit nothing here:
  /// the member expansion above already diagnoses them, so a second error would be noise.
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    guard declaration.is(StructDeclSyntax.self) else {
      return []
    }
    if inheritsProtocol(named: "AnyViewProps", in: declaration) {
      return []
    }
    let ext: DeclSyntax = """
      extension \(type.trimmed): AnyViewProps {}
      """
    guard let extDecl = ext.as(ExtensionDeclSyntax.self) else {
      return []
    }
    return [extDecl]
  }
}

// MARK: - Property classification

/// The value props of the declaration, in declaration order: every stored property that isn't
/// excluded by a modifier and isn't function-typed (an event prop). Each value prop must have a
/// type the macro can name — an explicit annotation or a literal-inferable default — because the
/// upcoming decode surface spells the type out (`Type.decode(…)`); requiring it now keeps the
/// surface stable when that lands.
private func valuePropNames(of declaration: some DeclGroupSyntax) throws -> [String] {
  var names: [String] = []

  for member in declaration.memberBlock.members {
    guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
      continue
    }
    if isExcludedByModifier(varDecl.modifiers) {
      continue
    }
    // `@Field` is the v1 property wrapper and has no meaning here — every stored property is a
    // prop. Left in place it would wrap the value in `Field<T>` (backing storage `_name`), so the
    // synthesized surface would be generated against the wrong type. Flag it explicitly rather
    // than emit broken code.
    if varDecl.attributes.firstAttribute(named: "Field") != nil {
      throw MacroExpansionErrorMessage(
        "@Field is not used with @ViewProps: every stored property is a prop. Remove the @Field attribute"
      )
    }
    for binding in varDecl.bindings {
      // Computed properties (and `{ get set }`) carry an accessor block — never props.
      if binding.accessorBlock != nil {
        continue
      }
      guard let ident = binding.pattern.as(IdentifierPatternSyntax.self) else {
        continue
      }
      let annotation = binding.typeAnnotation?.type
      // A function-typed property is an event prop: no PropName case, no change tracking.
      if underlyingFunctionType(of: annotation) != nil {
        continue
      }
      // An optional function type is neither a value prop (functions don't decode) nor a valid
      // event (an event prop is always present), so reject it instead of silently classifying.
      if let annotation, isOptionalFunctionType(annotation) {
        throw MacroExpansionErrorMessage(
          "@ViewProps event '\(ident.identifier.text)' can't have an optional function type: an event prop is always present. Remove the '?'"
        )
      }
      // Prefer the explicit annotation. When it's omitted, recover the type from a literal default
      // (Swift's own default-literal type) — covers the common `var enabled = true` case. Anything
      // whose type a syntactic macro can't determine (calls, collections, member access) still
      // needs an annotation.
      let inferredType = annotation?.trimmedDescription
        ?? binding.initializer.flatMap { inferredLiteralType(of: $0.value) }
      guard inferredType != nil else {
        throw MacroExpansionErrorMessage(
          "@ViewProps properties must declare an explicit type: '\(ident.identifier.text)' has none"
        )
      }
      names.append(ident.identifier.text)
    }
  }
  return names
}

/// True when the type is an optional wrapping a function type (`((P) -> Void)?`), unwrapping
/// the same attribute/parenthesis shapes `underlyingFunctionType` does.
private func isOptionalFunctionType(_ type: TypeSyntax) -> Bool {
  guard let optional = type.as(OptionalTypeSyntax.self) else {
    return false
  }
  return underlyingFunctionType(of: optional.wrappedType) != nil
}

// MARK: - Synthesized members

/// The `PropName` enum: one case per value prop, in declaration order. `String`-backed so the raw
/// value is the wire name, `CaseIterable` so the first application can mark every prop changed
/// (`Set(PropName.allCases)`). Empty (uninhabited) when the props type has no value props.
private func propNameEnum(cases: [String]) -> DeclSyntax {
  if cases.isEmpty {
    return """
      public enum PropName: String, CaseIterable {
      }
      """
  }
  let caseLines = cases.map { "  case \($0)" }.joined(separator: "\n")
  return """
    public enum PropName: String, CaseIterable {
    \(raw: caseLines)
    }
    """
}
