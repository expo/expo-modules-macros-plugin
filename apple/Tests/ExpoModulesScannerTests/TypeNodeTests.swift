@testable import ExpoModulesScanner
import SwiftParser
import SwiftSyntax
import Testing

/// Parses a Swift type spelling into a `TypeNode`, the way the surface visitor does for a boundary
/// type. Wraps the spelling in a throwaway declaration so the parser yields a `TypeSyntax`.
private func node(_ spelling: String) -> TypeNode {
  let tree = Parser.parse(source: "let _: \(spelling)")
  guard let varDecl = tree.statements.first?.item.as(VariableDeclSyntax.self),
    let type = varDecl.bindings.first?.typeAnnotation?.type else {
    return .unknown(text: spelling)
  }
  return typeNode(from: type)
}

@Suite("Type node parsing")
struct TypeNodeTests {
  @Test
  func `Maps the JS primitives`() {
    #expect(node("Int") == .primitive(name: "Int", jsType: .number))
    #expect(node("Double") == .primitive(name: "Double", jsType: .number))
    #expect(node("String") == .primitive(name: "String", jsType: .string))
    #expect(node("Bool") == .primitive(name: "Bool", jsType: .boolean))
  }

  @Test
  func `A non-primitive nominal type is a ref`() {
    #expect(node("Point") == .ref(name: "Point"))
    // A qualified name keeps its full spelling.
    #expect(node("Foo.Bar") == .ref(name: "Foo.Bar"))
  }

  @Test
  func `Optionals: sugar, IUO, and the explicit generic all collapse to .optional`() {
    #expect(node("Point?") == .optional(wrapped: .ref(name: "Point")))
    #expect(node("Int!") == .optional(wrapped: .primitive(name: "Int", jsType: .number)))
    #expect(node("Optional<String>") == .optional(wrapped: .primitive(name: "String", jsType: .string)))
  }

  @Test
  func `Arrays: sugar and the explicit generic`() {
    #expect(node("[String]") == .array(element: .primitive(name: "String", jsType: .string)))
    #expect(node("Array<Point>") == .array(element: .ref(name: "Point")))
  }

  @Test
  func `Dictionaries: sugar and the explicit generic`() {
    #expect(node("[String: Int]") == .dictionary(key: .primitive(name: "String", jsType: .string), value: .primitive(name: "Int", jsType: .number)))
    #expect(
      node("Dictionary<String, Point>") == .dictionary(key: .primitive(name: "String", jsType: .string), value: .ref(name: "Point")))
  }

  @Test
  func `Promise wraps its value`() {
    #expect(node("Promise<Int>") == .promise(value: .primitive(name: "Int", jsType: .number)))
    #expect(node("Promise<[Point]>") == .promise(value: .array(element: .ref(name: "Point"))))
  }

  @Test
  func `Closures: parameters and a Void result collapsed to nil`() {
    #expect(
      node("(String) -> Void")
        == .function(
          parameters: [.primitive(name: "String", jsType: .string)], returns: nil, isAsync: false, isThrowing: false))
    #expect(
      node("(Int, Point) -> String")
        == .function(
          parameters: [.primitive(name: "Int", jsType: .number), .ref(name: "Point")],
          returns: .primitive(name: "String", jsType: .string), isAsync: false, isThrowing: false))
  }

  @Test
  func `Closure async and throws effects are captured`() {
    #expect(
      node("() async -> Int")
        == .function(parameters: [], returns: .primitive(name: "Int", jsType: .number), isAsync: true, isThrowing: false))
    #expect(
      node("() throws -> Int")
        == .function(parameters: [], returns: .primitive(name: "Int", jsType: .number), isAsync: false, isThrowing: true))
    #expect(
      node("() async throws -> Void")
        == .function(parameters: [], returns: nil, isAsync: true, isThrowing: true))
  }

  @Test
  func `An @escaping attribute is stripped to the underlying type`() {
    #expect(
      node("@escaping (Int) -> Void")
        == .function(parameters: [.primitive(name: "Int", jsType: .number)], returns: nil, isAsync: false, isThrowing: false))
  }

  @Test
  func `Composed types nest`() {
    // `[Point]?`, an optional array of refs.
    #expect(node("[Point]?") == .optional(wrapped: .array(element: .ref(name: "Point"))))
    // A dictionary whose value is an array of optionals.
    #expect(
      node("[String: [Int?]]")
        == .dictionary(
          key: .primitive(name: "String", jsType: .string),
          value: .array(element: .optional(wrapped: .primitive(name: "Int", jsType: .number)))))
  }

  @Test
  func `An unmodeled generic keeps its name and arguments as a ref`() {
    #expect(node("Set<Int>") == .ref(name: "Set<Int>"))
    #expect(node("Either<String, Point>") == .ref(name: "Either<String, Point>"))
  }

  @Test
  func `An unmodeled spelling is preserved as .unknown`() {
    // A bare identifier is syntactically indistinguishable from a nominal type, so a generic
    // parameter `T` reads as a ref, the generator resolves (or flags) it.
    #expect(node("T") == .ref(name: "T"))
    // A tuple isn't modeled; its verbatim text survives as .unknown rather than being dropped.
    #expect(node("(Int, Bool)") == .unknown(text: "(Int, Bool)"))
  }

  @Test
  func `Every node reports its typeof category`() {
    // Primitives map to their JS primitive.
    #expect(node("Int").jsType == .number)
    #expect(node("Double").jsType == .number)
    #expect(node("String").jsType == .string)
    #expect(node("Bool").jsType == .boolean)
    // Every structured object kind is `object`.
    #expect(node("[String]").jsType == .object)
    #expect(node("[String: Int]").jsType == .object)
    #expect(node("Promise<Int>").jsType == .object)
    #expect(node("Point").jsType == .object)
    // A closure is `function`.
    #expect(node("(Int) -> Void").jsType == .function)
    // An optional reports the category of its present value, not `undefined` (the absent case is
    // carried structurally by the wrapper).
    #expect(node("Int?").jsType == .number)
    #expect(node("Point?").jsType == .object)
    // An unmodeled spelling has no known category.
    #expect(node("(Int, Bool)").jsType == nil)
  }
}
