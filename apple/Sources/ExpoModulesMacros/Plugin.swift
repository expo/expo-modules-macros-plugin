import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ExpoModulesMacrosPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    OptimizedFunctionAttachedMacro.self,
  ]
}
