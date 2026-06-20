package expo.modules.macros.processor

import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.google.devtools.ksp.symbol.KSDeclaration
import com.google.devtools.ksp.symbol.KSType
import com.google.devtools.ksp.symbol.Nullability

/** True if the declaration carries an annotation with the given fully-qualified name. */
internal fun KSDeclaration.hasAnnotation(qualifiedName: String): Boolean {
  return annotations.any {
    it.annotationType.resolve().declaration.qualifiedName?.asString() == qualifiedName
  }
}

/**
 * The JS name for a `@JS` member: the annotation's `name` argument when non-blank, else the given
 * Kotlin member name. Reading the argument by name (not position) keeps it robust to the annotation
 * gaining more parameters later.
 */
internal fun KSDeclaration.jsName(fallback: String): String {
  return jsNameArgument().ifBlank { fallback }
}

private fun KSDeclaration.jsNameArgument(): String {
  val annotation = annotations.firstOrNull {
    it.annotationType.resolve().declaration.qualifiedName?.asString() == "expo.modules.macros.JS"
  } ?: return ""
  val value = annotation.arguments.firstOrNull { it.name?.asString() == "name" }?.value
  return (value as? String).orEmpty()
}

/** The `name` argument of `@ExpoModule`, or blank when omitted. */
internal fun KSClassDeclaration.expoModuleName(): String {
  val annotation = annotations.firstOrNull {
    it.annotationType.resolve().declaration.qualifiedName?.asString() == "expo.modules.macros.ExpoModule"
  } ?: return ""
  val value = annotation.arguments.firstOrNull { it.name?.asString() == "name" }?.value
  return (value as? String).orEmpty()
}

/** True if the class transitively extends `expo.modules.kotlin.modules.Module`. */
internal fun extendsModule(declaration: KSClassDeclaration): Boolean {
  return declaration.getAllSuperTypes().any {
    it.declaration.qualifiedName?.asString() == "expo.modules.kotlin.modules.Module"
  }
}

private fun KSClassDeclaration.getAllSuperTypes(): Sequence<KSType> {
  return superTypes
    .map { it.resolve() }
    .flatMap { superType ->
      val declaration = superType.declaration
      val transitive = if (declaration is KSClassDeclaration) {
        declaration.getAllSuperTypes()
      } else {
        emptySequence()
      }
      sequenceOf(superType) + transitive
    }
}

/**
 * Renders a resolved type as source the generated file can use: fully-qualified name plus a trailing
 * `?` when nullable. Qualified names avoid having to manage imports for arbitrary parameter/property
 * types in the generated file. Type arguments are intentionally not rendered yet — the first cut
 * targets simple types; generic argument support is a follow-up.
 */
internal fun KSType.toTypeName(): String {
  val qualified = declaration.qualifiedName?.asString()
    ?: declaration.simpleName.asString()
  val suffix = if (nullability == Nullability.NULLABLE) "?" else ""
  return qualified + suffix
}
