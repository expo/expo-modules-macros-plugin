import ExpoModulesMacros
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macroSpecs: [String: MacroSpec] = [
  "OptimizedFunction": MacroSpec(type: OptimizedFunctionAttachedMacro.self)
]

private func assertExpansion(
  _ original: String,
  expandedSource expected: String,
  diagnostics: [DiagnosticSpec] = [],
  sourceLocation: Testing.SourceLocation = #_sourceLocation,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  line: UInt = #line,
  column: UInt = #column
) {
  assertMacroExpansion(
    original,
    expandedSource: expected,
    diagnostics: diagnostics,
    macroSpecs: macroSpecs,
    indentationWidth: .spaces(2),
    failureHandler: { spec in
      Issue.record(Comment(rawValue: spec.message), sourceLocation: sourceLocation)
    },
    fileID: fileID,
    filePath: filePath,
    line: line,
    column: column
  )
}

@Suite("@OptimizedFunction macro")
struct ExpoModulesMacrosTests {
  @Test
  func `Double, Double -> Double descriptor`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func addNumbers(a: Double, b: Double) -> Double {
        return a + b
      }
      """,
      expandedSource: """
        private func addNumbers(a: Double, b: Double) -> Double {
          return a + b
        }

        private func addNumbers() -> OptimizedFunctionDescriptor {
          return OptimizedSyncFunctionDefinition.createDescriptor(
            typeEncoding: "d@?dd",
            argsCount: 2,
            block: (addNumbers as @convention(block) (Double, Double) -> Double) as AnyObject
          )
        }
        """
    )
  }

  @Test
  func `Int, Int -> Int descriptor`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func addInts(a: Int, b: Int) -> Int {
        return a + b
      }
      """,
      expandedSource: """
        private func addInts(a: Int, b: Int) -> Int {
          return a + b
        }

        private func addInts() -> OptimizedFunctionDescriptor {
          return OptimizedSyncFunctionDefinition.createDescriptor(
            typeEncoding: "q@?qq",
            argsCount: 2,
            block: (addInts as @convention(block) (Int, Int) -> Int) as AnyObject
          )
        }
        """
    )
  }

  @Test
  func `single parameter descriptor`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func double(x: Double) -> Double {
        return x * 2
      }
      """,
      expandedSource: """
        private func double(x: Double) -> Double {
          return x * 2
        }

        private func double() -> OptimizedFunctionDescriptor {
          return OptimizedSyncFunctionDefinition.createDescriptor(
            typeEncoding: "d@?d",
            argsCount: 1,
            block: (double as @convention(block) (Double) -> Double) as AnyObject
          )
        }
        """
    )
  }

  @Test
  func `void return descriptor`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func doNothing() {
        print("nothing")
      }
      """,
      expandedSource: """
        private func doNothing() {
          print("nothing")
        }

        private func doNothing() -> OptimizedFunctionDescriptor {
          return OptimizedSyncFunctionDefinition.createDescriptor(
            typeEncoding: "v@?",
            argsCount: 0,
            block: (doNothing as @convention(block) () -> Void) as AnyObject
          )
        }
        """
    )
  }

  @Test
  func `String parameters descriptor`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func concat(a: String, b: String) -> String {
        return a + b
      }
      """,
      expandedSource: """
        private func concat(a: String, b: String) -> String {
          return a + b
        }

        private func concat() -> OptimizedFunctionDescriptor {
          return OptimizedSyncFunctionDefinition.createDescriptor(
            typeEncoding: "@@?@@",
            argsCount: 2,
            block: (concat as @convention(block) (String, String) -> String) as AnyObject
          )
        }
        """
    )
  }

  @Test
  func `Bool parameter descriptor`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func negate(value: Bool) -> Bool {
        return !value
      }
      """,
      expandedSource: """
        private func negate(value: Bool) -> Bool {
          return !value
        }

        private func negate() -> OptimizedFunctionDescriptor {
          return OptimizedSyncFunctionDefinition.createDescriptor(
            typeEncoding: "B@?B",
            argsCount: 1,
            block: (negate as @convention(block) (Bool) -> Bool) as AnyObject
          )
        }
        """
    )
  }

  @Test
  func `throwing function with void return descriptor`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func validateValue(value: Double) throws {
        if value < 0 {
          throw NSError(domain: "ValidationError", code: 1)
        }
      }
      """,
      expandedSource: """
        private func validateValue(value: Double) throws {
          if value < 0 {
            throw NSError(domain: "ValidationError", code: 1)
          }
        }

        private func validateValue() -> OptimizedFunctionDescriptor {
          let impl: (Double) throws -> Void = validateValue
          let wrapper: @convention(block) (Double) -> Void = { arg0 in
            do {
              try impl(arg0)
            } catch {
              let nsError: NSError
              if let expoError = error as? Exception {
                nsError = NSError(domain: "dev.expo.modules", code: 0, userInfo: [
                  "name": expoError.name,
                  "code": expoError.code,
                  "message": expoError.debugDescription,
                ])
              } else {
                nsError = error as NSError
              }
              let exception = NSException(
                name: NSExceptionName(nsError.userInfo["name"] as? String ?? "SwiftError"),
                reason: nsError.userInfo["message"] as? String ?? nsError.localizedDescription,
                userInfo: nsError.userInfo
              )
              exception.raise()
            }
          }
          return OptimizedSyncFunctionDefinition.createDescriptor(
            typeEncoding: "v@?d",
            argsCount: 1,
            block: wrapper as AnyObject
          )
        }
        """
    )
  }

  @Test
  func `throwing function with return value descriptor`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func divide(a: Double, b: Double) throws -> Double {
        if b == 0 {
          throw NSError(domain: "MathError", code: 1)
        }
        return a / b
      }
      """,
      expandedSource: """
        private func divide(a: Double, b: Double) throws -> Double {
          if b == 0 {
            throw NSError(domain: "MathError", code: 1)
          }
          return a / b
        }

        private func divide() -> OptimizedFunctionDescriptor {
          let impl: (Double, Double) throws -> Double = divide
          let wrapper: @convention(block) (Double, Double) -> Double = { arg0, arg1 in
            do {
              return try impl(arg0, arg1)
            } catch {
              let nsError: NSError
              if let expoError = error as? Exception {
                nsError = NSError(domain: "dev.expo.modules", code: 0, userInfo: [
                  "name": expoError.name,
                  "code": expoError.code,
                  "message": expoError.debugDescription,
                ])
              } else {
                nsError = error as NSError
              }
              let exception = NSException(
                name: NSExceptionName(nsError.userInfo["name"] as? String ?? "SwiftError"),
                reason: nsError.userInfo["message"] as? String ?? nsError.localizedDescription,
                userInfo: nsError.userInfo
              )
              exception.raise()
              fatalError("Unreachable")
            }
          }
          return OptimizedSyncFunctionDefinition.createDescriptor(
            typeEncoding: "d@?dd",
            argsCount: 2,
            block: wrapper as AnyObject
          )
        }
        """
    )
  }

  @Test
  func `throwing function with no parameters descriptor`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func getConfig() throws -> String {
        throw NSError(domain: "ConfigError", code: 404)
      }
      """,
      expandedSource: """
        private func getConfig() throws -> String {
          throw NSError(domain: "ConfigError", code: 404)
        }

        private func getConfig() -> OptimizedFunctionDescriptor {
          let impl: () throws -> String = getConfig
          let wrapper: @convention(block) () -> String = {
            do {
              return try impl()
            } catch {
              let nsError: NSError
              if let expoError = error as? Exception {
                nsError = NSError(domain: "dev.expo.modules", code: 0, userInfo: [
                  "name": expoError.name,
                  "code": expoError.code,
                  "message": expoError.debugDescription,
                ])
              } else {
                nsError = error as NSError
              }
              let exception = NSException(
                name: NSExceptionName(nsError.userInfo["name"] as? String ?? "SwiftError"),
                reason: nsError.userInfo["message"] as? String ?? nsError.localizedDescription,
                userInfo: nsError.userInfo
              )
              exception.raise()
              fatalError("Unreachable")
            }
          }
          return OptimizedSyncFunctionDefinition.createDescriptor(
            typeEncoding: "@@?",
            argsCount: 0,
            block: wrapper as AnyObject
          )
        }
        """
    )
  }

  @Test
  func `unsupported parameter type is a diagnostic`() {
    assertExpansion(
      """
      struct MyStruct {
        let value: Int
      }

      @OptimizedFunction
      private func processStruct(data: MyStruct) -> String {
        return "processed"
      }
      """,
      expandedSource: """
        struct MyStruct {
          let value: Int
        }
        private func processStruct(data: MyStruct) -> String {
          return "processed"
        }
        """,
      diagnostics: [
        DiagnosticSpec(message: "Unsupported parameter type: MyStruct", line: 5, column: 1)
      ]
    )
  }

  @Test
  func `unsupported return type is a diagnostic`() {
    assertExpansion(
      """
      struct MyStruct {
        let value: Int
      }

      @OptimizedFunction
      private func createStruct(value: Int) -> MyStruct {
        return MyStruct(value: value)
      }
      """,
      expandedSource: """
        struct MyStruct {
          let value: Int
        }
        private func createStruct(value: Int) -> MyStruct {
          return MyStruct(value: value)
        }
        """,
      diagnostics: [
        DiagnosticSpec(message: "Unsupported return type: MyStruct", line: 5, column: 1)
      ]
    )
  }

  @Test
  func `unsupported array parameter type is a diagnostic`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func processArray(items: [Int]) -> Int {
        return items.count
      }
      """,
      expandedSource: """
        private func processArray(items: [Int]) -> Int {
          return items.count
        }
        """,
      diagnostics: [
        DiagnosticSpec(message: "Unsupported parameter type: [Int]", line: 1, column: 1)
      ]
    )
  }

  @Test
  func `unsupported optional parameter type is a diagnostic`() {
    assertExpansion(
      """
      @OptimizedFunction
      private func processOptional(value: Int?) -> Bool {
        return value != nil
      }
      """,
      expandedSource: """
        private func processOptional(value: Int?) -> Bool {
          return value != nil
        }
        """,
      diagnostics: [
        DiagnosticSpec(message: "Unsupported parameter type: Int?", line: 1, column: 1)
      ]
    )
  }
}
