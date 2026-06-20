package expo.modules.macros.processor

import com.google.devtools.ksp.getDeclaredFunctions
import com.google.devtools.ksp.getDeclaredProperties
import com.google.devtools.ksp.validate
import com.google.devtools.ksp.processing.CodeGenerator
import com.google.devtools.ksp.processing.Dependencies
import com.google.devtools.ksp.processing.KSPLogger
import com.google.devtools.ksp.processing.Resolver
import com.google.devtools.ksp.processing.SymbolProcessor
import com.google.devtools.ksp.symbol.ClassKind
import com.google.devtools.ksp.symbol.KSAnnotated
import com.google.devtools.ksp.symbol.KSClassDeclaration
import com.google.devtools.ksp.symbol.KSFunctionDeclaration
import com.google.devtools.ksp.symbol.KSPropertyDeclaration
import com.google.devtools.ksp.symbol.Modifier

/**
 * Reads `@ExpoModule` classes and their `@JS` members and generates a `<Module>.expoModuleDefinition()`
 * extension per module (see [DefinitionGenerator]). The Android counterpart of the Swift
 * `ExpoModuleMacro`: same job (discover the JS surface from annotations, emit the definition), done
 * with KSP's resolved symbols instead of SwiftSyntax.
 *
 * Type-convertibility is *not* asserted here the way the Swift `@JS` macro emits a peer assertion —
 * KSP hands us resolved types, and a non-JS-convertible argument/return type already fails to compile
 * at the generated DSL call site (the reified `Function`/`Property` builders can't resolve a
 * `TypeConverter` for it), with the error pointing at the generated lambda.
 */
class ExpoModuleProcessor(
  private val codeGenerator: CodeGenerator,
  private val logger: KSPLogger
) : SymbolProcessor {
  override fun process(resolver: Resolver): List<KSAnnotated> {
    val symbols = resolver.getSymbolsWithAnnotation(EXPO_MODULE_ANNOTATION).toList()
    val deferred = symbols.filterNot { it.validate() }

    symbols
      .filterIsInstance<KSClassDeclaration>()
      .filter { it.validate() }
      .forEach { processModule(it) }

    return deferred
  }

  private fun processModule(declaration: KSClassDeclaration) {
    if (declaration.classKind != ClassKind.CLASS) {
      logger.error("@ExpoModule can only be applied to a class", declaration)
      return
    }
    if (!extendsModule(declaration)) {
      logger.error(
        "@ExpoModule class '${declaration.simpleName.asString()}' must extend ${MODULE_CLASS}",
        declaration
      )
      return
    }

    val model = buildModel(declaration) ?: return
    writeDefinition(declaration, model)
  }

  private fun buildModel(declaration: KSClassDeclaration): ModuleModel? {
    val packageName = declaration.packageName.asString()
    val simpleName = declaration.simpleName.asString()
    val jsName = declaration.expoModuleName().ifBlank { simpleName }

    val annotatedFunctions = declaration.getDeclaredFunctions()
      .filter { it.hasAnnotation(JS_ANNOTATION) }
      .toList()
    val annotatedProperties = declaration.getDeclaredProperties()
      .filter { it.hasAnnotation(JS_ANNOTATION) }
      .toList()

    val functions = annotatedFunctions.mapNotNull { functionModel(it) }
    val properties = annotatedProperties.mapNotNull { propertyModel(it) }

    // A member that failed validation has already logged an error (which fails the build). Don't
    // also emit a definition that omits it — a partial file would only add noise on top of the
    // real diagnostic.
    if (functions.size != annotatedFunctions.size || properties.size != annotatedProperties.size) {
      return null
    }

    return ModuleModel(
      qualifiedName = declaration.qualifiedName?.asString() ?: "$packageName.$simpleName",
      packageName = packageName,
      simpleName = simpleName,
      jsName = jsName,
      functions = functions,
      properties = properties
    )
  }

  private fun functionModel(function: KSFunctionDeclaration): FunctionModel? {
    val kotlinName = function.simpleName.asString()
    if (function.modifiers.contains(Modifier.PRIVATE)) {
      logger.error("@JS function '$kotlinName' cannot be private — the generated definition is in the same package but can't see private members", function)
      return null
    }
    val parameters = function.parameters.map { parameter ->
      ParameterModel(
        name = parameter.name?.asString() ?: "_",
        type = parameter.type.resolve().toTypeName()
      )
    }
    return FunctionModel(
      kotlinName = kotlinName,
      jsName = function.jsName(kotlinName),
      parameters = parameters,
      isSuspend = function.modifiers.contains(Modifier.SUSPEND)
    )
  }

  private fun propertyModel(property: KSPropertyDeclaration): PropertyModel? {
    val kotlinName = property.simpleName.asString()
    if (property.modifiers.contains(Modifier.PRIVATE)) {
      logger.error("@JS property '$kotlinName' cannot be private — the generated definition is in the same package but can't see private members", property)
      return null
    }
    return PropertyModel(
      kotlinName = kotlinName,
      jsName = property.jsName(kotlinName),
      type = property.type.resolve().toTypeName(),
      isMutable = property.isMutable
    )
  }

  private fun writeDefinition(declaration: KSClassDeclaration, model: ModuleModel) {
    val source = DefinitionGenerator.generate(model)
    val file = codeGenerator.createNewFile(
      dependencies = Dependencies(aggregating = false, declaration.containingFile!!),
      packageName = model.packageName,
      fileName = "${model.simpleName}\$ExpoModuleDefinition"
    )
    file.bufferedWriter().use { it.write(source) }
  }

  companion object {
    private const val EXPO_MODULE_ANNOTATION = "expo.modules.macros.ExpoModule"
    private const val JS_ANNOTATION = "expo.modules.macros.JS"
    private const val MODULE_CLASS = "expo.modules.kotlin.modules.Module"
  }
}
