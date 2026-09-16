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

    // A generic view can't be registered: `@ExpoModule(views: [CardView.self])` on a generic type
    // fails with "generic parameter 'T' could not be inferred", and the props type ignores the
    // parameter anyway. Reject it here, at the author's line, rather than at the registration site.
    // `@ViewProps` rejects generic props types for the same reason.
    if classDecl.genericParameterClause != nil {
      throw MacroExpansionErrorMessage(
        "@ExpoView does not support generic classes — a view registered with @ExpoModule(views:) must be concrete"
      )
    }

    // The expansion is a `Props` typealias, so a member of that name already on the class collides.
    // Left alone, the compiler reports "invalid redeclaration of 'Props'" positioned inside the
    // macro expansion, which is code the author never wrote. Name it here instead.
    if let existing = existingPropsMemberKind(in: classDecl) {
      throw MacroExpansionErrorMessage(
        "@ExpoView synthesizes a `Props` typealias, but this class already declares a \(existing) named 'Props'. Rename it"
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

/**
 Describes an existing `Props` member on the class, for the collision diagnostic, or `nil` when the
 name is free. Covers the shapes that would clash with the synthesized typealias: another typealias,
 and a nested type of any kind.
 */
private func existingPropsMemberKind(in classDecl: ClassDeclSyntax) -> String? {
  for member in classDecl.memberBlock.members {
    let decl = member.decl
    if let typealiasDecl = decl.as(TypeAliasDeclSyntax.self), typealiasDecl.name.text == "Props" {
      return "typealias"
    }
    if let structDecl = decl.as(StructDeclSyntax.self), structDecl.name.text == "Props" {
      return "struct"
    }
    if let nestedClass = decl.as(ClassDeclSyntax.self), nestedClass.name.text == "Props" {
      return "class"
    }
    if let enumDecl = decl.as(EnumDeclSyntax.self), enumDecl.name.text == "Props" {
      return "enum"
    }
    if let actorDecl = decl.as(ActorDeclSyntax.self), actorDecl.name.text == "Props" {
      return "actor"
    }
  }
  return nil
}

/// Base classes an `@ExpoView` may inherit from. The check is syntactic, matching the name in the
/// class's own inheritance clause: both `: ExpoView` and a qualified `: ExpoModulesCore.ExpoView`
/// pass, since `baseIdentifier` reads the trailing name.
///
/// Indirect inheritance does not: a view whose superclass is itself an `ExpoView` subclass
/// (`class Base: ExpoView` then `class CardView: Base`) is rejected, because a macro can't resolve
/// the superclass to check. `@SharedObject` has the same limitation, through the same helper. The
/// workaround is to apply `@ExpoView` to the class that names `ExpoView` directly.
private let expoViewBaseClassNames: Set<String> = ["ExpoView"]

/**
 The attribute's single generic argument, verbatim (`@ExpoView<CardProps>` → `"CardProps"`), or
 `nil` when the attribute carries no generic argument clause.

 The type is available syntactically, with no type resolution. Two spellings carry it, mirroring
 `baseIdentifier`'s handling of the inheritance clause: a bare `@ExpoView<CardProps>` parses as an
 `IdentifierTypeSyntax`, and a qualified `@ExpoModulesCore.ExpoView<CardProps>` as a
 `MemberTypeSyntax`. Both have a `genericArgumentClause`, and both are legal at the use site, so
 reading only the bare form would reject valid code while claiming the author omitted the argument.

 Only the first argument is read: core's declaration has exactly one parameter, so a second is
 already a compile error at the use site ("specialized with too many type parameters").
 */
private func genericArgument(of attribute: AttributeSyntax) -> String? {
  let arguments: GenericArgumentListSyntax?
  if let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) {
    arguments = identifier.genericArgumentClause?.arguments
  } else if let member = attribute.attributeName.as(MemberTypeSyntax.self) {
    arguments = member.genericArgumentClause?.arguments
  } else {
    arguments = nil
  }
  guard let first = arguments?.first, case .type(let type) = first.argument else {
    return nil
  }
  return type.trimmedDescription
}
