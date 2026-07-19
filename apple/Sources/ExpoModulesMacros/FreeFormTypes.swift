/// Recognition of the free-form (`Any`-bearing) boundary types and the spellings the macros emit or
/// suggest for them. None of these types can conform to the JS codable protocols (`Any` can't conform
/// to a protocol, and the container conditional conformances require the element/value to conform), so
/// they can't cross the boundary through the usual `T.decode` / `T.encode` path. Instead they're
/// accepted **only** in decode position (function/constructor arguments), decoded through a dedicated
/// `JavaScriptValue.decodeAny…` entry point; a free-form return or getter is rejected, since there's
/// no free-form encode.
///
/// Shared across the macro pipeline: `TypeConformanceAssertion` skips them, `MacroHelpers.decodeCall`
/// reroutes their decode, and `JSMacro` uses them for the steering diagnostics.

/// The free-form boundary types: an untyped value (`Any`), an untyped array (`[Any]`), and an untyped
/// string-keyed dictionary (`[String: Any]`). Matched by whitespace-normalized spelling so
/// `[String: Any]` and `[String : Any]` both count.
private let freeFormBoundaryTypes: Set<String> = ["Any", "[Any]", "[String:Any]"]

/// The `JavaScriptValue.decodeAny…` method the binding calls to decode a free-form argument, keyed by
/// the free-form type's normalized spelling. `nil` for any non-free-form type.
private let freeFormDecodeMethods: [String: String] = [
  "Any": "decodeAny",
  "[Any]": "decodeAnyArray",
  "[String:Any]": "decodeAnyDictionary",
]

/// The type-safe alternative a free-form type's diagnostic steers to: the same shape with the `Any`
/// element replaced by `JavaScriptValue`, which conforms to the codable protocols. Keyed by the
/// free-form type's normalized spelling; spelled with conventional spacing for the message.
private let typedFreeFormReplacements: [String: String] = [
  "Any": "JavaScriptValue",
  "[Any]": "[JavaScriptValue]",
  "[String:Any]": "[String: JavaScriptValue]",
]

/// True when a boundary type (as written) is one of the free-form spellings, ignoring internal
/// whitespace so `[String: Any]` and `[String :Any]` both match. Optionals are not free-form here: a
/// trailing `?` would route through `Optional.decode`, which free-form can't satisfy, so an optional
/// free-form type isn't recognized and stays a normal (failing) assertion.
internal func isFreeFormBoundaryType(_ type: String) -> Bool {
  return freeFormBoundaryTypes.contains(normalizedTypeSpelling(type))
}

/// The `JavaScriptValue.decodeAny…` method name for a free-form boundary type, or `nil` when the type
/// isn't free-form. The binding emits `JavaScriptValue.<method>(arguments.unownedValue(at:), in:)` in
/// place of the type's own `.decode`.
internal func freeFormDecodeMethod(for type: String) -> String? {
  return freeFormDecodeMethods[normalizedTypeSpelling(type)]
}

/// The type-safe alternative to suggest in place of a free-form type (its `Any` element replaced by
/// `JavaScriptValue`), or `nil` when the type isn't free-form.
internal func typedFreeFormReplacement(for type: String) -> String? {
  return typedFreeFormReplacements[normalizedTypeSpelling(type)]
}

/// A type spelling with all whitespace removed, so spelling variations of the same type
/// (`[String: Any]` vs `[String :Any]`) compare equal.
private func normalizedTypeSpelling(_ type: String) -> String {
  return type.filter { !$0.isWhitespace }
}
