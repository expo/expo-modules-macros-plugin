import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/**
 Member macro applied to an `ExpoView` subclass, binding it to its props type:

   @ExpoView<CardProps>
   final class CardView: ExpoView {
     override func didUpdateProps(_ diff: CardProps.Diff) {
       if diff.changed(.color) {
         backgroundColor = props.color
       }
     }
   }

 The props type is the attribute's **generic argument**, so it sits in type position: no
 `.self` metatype to write, and the macro reads it straight off the attribute's
 `genericArgumentClause`. Core's declaration constrains the parameter
 (`macro ExpoView<Props: AnyViewProps>()`), so passing a type that isn't a props type is a
 compile error at the author's own line ("requires that 'X' conform to 'AnyViewProps'")
 rather than a macro diagnostic. This macro therefore validates nothing about the props type.

 The whole expansion is one line:

   public typealias Props = CardProps

 That is deliberately all of it. There is **no view definition**: no `ViewDefinition`, no
 `View(…) { }` builder, no `Props(_:)` or `Events(_:)` element. `_synthesizedViewDefinition()`
 existed only to hand core a DSL value the old registration path could consume, and modules and
 shared objects already moved to direct hooks. Core reads the props type from this typealias and
 the event names from the props type's own `_eventNames` (synthesized by `@ViewProps`), both
 static, neither needing a builder to be evaluated.

 Views also get no `_decorateView` hook in its place: `_decorateModule` and `_decorateSharedObject`
 exist to bind members into a JS object, and a view has no such object. Props reach a view through
 Fabric's mounting layer, not a JS call, so a view's runtime entry point is the props update hook.

 `didUpdateProps` is a core-called override, not synthesized here.
 */
public struct ExpoViewMacro: MemberMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
      throw MacroExpansionErrorMessage("@ExpoView can only be applied to a class")
    }

    guard inheritsFromAny(classDecl, names: expoViewBaseClassNames) else {
      throw MacroExpansionErrorMessage(
        "@ExpoView class must inherit from ExpoView. Add `: ExpoView` to the class declaration."
      )
    }

    // The props type is the attribute's generic argument. Core's declaration is generic, so a bare
    // `@ExpoView` never reaches expansion: it fails type-checking first with "generic parameter
    // 'Props' could not be inferred". This diagnostic covers the case where the macro is declared
    // differently than core declares it, so the author still gets a message naming the attribute.
    guard let propsType = genericArgument(of: node) else {
      throw MacroExpansionErrorMessage(
        "@ExpoView requires its props type as a generic argument, as in `@ExpoView<MyViewProps>`"
      )
    }

    return [
      """
      public typealias Props = \(raw: propsType)
      """
    ]
  }
}

/// Base classes an `@ExpoView` may inherit from. `ExpoView` is the UIKit base; the qualified
/// spelling appears when the author hasn't imported the core module unqualified.
private let expoViewBaseClassNames: Set<String> = ["ExpoView"]

/**
 The attribute's single generic argument, verbatim (`@ExpoView<CardProps>` → `"CardProps"`), or
 `nil` when the attribute carries no generic argument clause.

 A generic attribute parses as an `IdentifierTypeSyntax` whose `genericArgumentClause` holds the
 arguments, so the type is available syntactically without any type resolution. Only the first
 argument is read: core's declaration has exactly one parameter, so a second would already be a
 compile error at the use site.
 */
private func genericArgument(of attribute: AttributeSyntax) -> String? {
  guard let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self),
    let arguments = identifier.genericArgumentClause?.arguments,
    let first = arguments.first else {
    return nil
  }
  guard case .type(let type) = first.argument else {
    return nil
  }
  return type.trimmedDescription
}
