import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling.
// Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(ExpoModulesMacros)
  import ExpoModulesMacros

  let testMacros: [String: Macro.Type] = [
    "OptimizedFunction": OptimizedFunctionAttachedMacro.self
  ]
#endif

final class ExpoModulesMacrosTests: XCTestCase {
  func testAttachedMacroWithDoubleDoubleToDouble() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testAttachedMacroWithIntIntToInt() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testAttachedMacroWithSingleParameter() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testAttachedMacroWithVoidReturnType() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testAttachedMacroWithStringParameters() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testAttachedMacroWithBoolParameter() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testAttachedMacroWithThrowingFunctionVoidReturn() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testAttachedMacroWithThrowingFunctionWithReturn() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testAttachedMacroWithThrowingFunctionNoParams() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
          """,
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testErrorWithUnsupportedParameterType() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
        ],
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testErrorWithUnsupportedReturnType() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
        ],
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testErrorWithUnsupportedArrayType() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
        ],
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }

  func testErrorWithUnsupportedOptionalType() throws {
    #if canImport(ExpoModulesMacros)
      assertMacroExpansion(
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
        ],
        macros: testMacros
      )
    #else
      throw XCTSkip("macros are only supported when running tests for the host platform")
    #endif
  }
}
