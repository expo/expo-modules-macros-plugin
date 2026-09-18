import Foundation

/// Fills in each `.ref`'s `refKind` once the whole scan is done.
///
/// A `TypeNode` is parsed from one `TypeSyntax` in isolation, so at parse time a name like `Status` is
/// just a name: the parser has no idea whether the scan will turn up an `@Record`, an `Enumerable`
/// enum, or nothing at all. Resolution is therefore a second pass over the collected surface, run once
/// every file has been walked.
///
/// Two things change on a resolved ref:
/// - `refKind` names which kind declares it, so a consumer doesn't repeat this lookup.
/// - the `typeof` category is corrected for an enum, which crosses as its raw value rather than as an
///   object. That correction is the reason this can't be left to the consumer: the scanner is the only
///   side that knows the enum's `rawType`.
///
/// A name the scan never declared keeps `refKind: nil` and its `object` category. Not an error: it is
/// a platform convertible (`CGPoint`, `URL`) or a type from another module, and the consumer's own
/// catalog decides.

/// The declared names of a scanned surface, each mapped to how it should be reported at a use site.
/// Built once per scan and used for every ref lookup.
struct RefIndex {
  /// `name` -> the kind declaring it, plus the JS category a ref to it crosses as.
  private var entries: [String: (kind: RefKind, jsType: JSType)] = [:]

  init(surface: ExportedSurface) {
    for record in surface.records {
      entries[record.name] = (.record, .object)
    }
    for sharedObject in surface.sharedObjects {
      entries[sharedObject.name] = (.sharedObject, .object)
    }
    for union in surface.unions {
      // A union crosses as whichever alternative matched, so its category is only meaningful per
      // member. `object` is the honest coarse answer; the consumer reads `members` for the real shape.
      entries[union.name] = (.union, .object)
    }
    for enumeration in surface.enums {
      entries[enumeration.name] = (.enum, jsType(ofRawType: enumeration.rawType))
    }
  }

  /// How a ref to `name` should be reported, or `nil` when the scan declares no such type.
  func lookup(_ name: String) -> (kind: RefKind, jsType: JSType)? {
    if let entry = entries[name] {
      return entry
    }
    // A qualified use site (`Media.Status`) names the same type a bare declaration did. Fall back to
    // the trailing component, which is how the conformance and raw-type checks already match names.
    guard let trailing = name.split(separator: ".").last.map(String.init), trailing != name else {
      return nil
    }
    return entries[trailing]
  }
}

/// The JS category a raw-value enum crosses as: its raw value's. A bare `Enumerable` conformance with
/// no raw type has nothing to go on, so it stays an object.
private func jsType(ofRawType rawType: TypeNode?) -> JSType {
  guard let rawType, let jsType = rawType.jsType else {
    return .object
  }
  return jsType
}

extension TypeNode {
  /// This node with every `.ref` in it resolved against `index`, recursively. Returns an unchanged
  /// node when nothing in it resolves.
  func resolvingRefs(using index: RefIndex) -> TypeNode {
    switch self {
    case .primitive, .unknown:
      return self
    case .ref(let name, _, _):
      guard let entry = index.lookup(name) else {
        return self
      }
      // Only an enum crosses as something other than an object, so only it carries an override.
      return .ref(
        name: name, refKind: entry.kind, jsTypeOverride: entry.jsType == .object ? nil : entry.jsType)
    case .optional(let wrapped):
      return .optional(wrapped: wrapped.resolvingRefs(using: index))
    case .array(let element):
      return .array(element: element.resolvingRefs(using: index))
    case .dictionary(let key, let value):
      return .dictionary(
        key: key.resolvingRefs(using: index), value: value.resolvingRefs(using: index))
    case .promise(let value):
      return .promise(value: value.resolvingRefs(using: index))
    case .function(let parameters, let returns, let isAsync, let isThrowing):
      return .function(
        parameters: parameters.map { $0.resolvingRefs(using: index) },
        returns: returns?.resolvingRefs(using: index),
        isAsync: isAsync,
        isThrowing: isThrowing
      )
    }
  }
}

extension ExportedSurface {
  /// This surface with every `.ref` in every reported type resolved against its own declarations. The
  /// second pass `scanExports` runs once the walk is done.
  ///
  /// Only the boundary types are rewritten; names, flags, and ordering are untouched. The declared
  /// types (a record's own name, a union's members) are not themselves refs, so they carry no
  /// `refKind`: it is the *use sites* that gain one.
  func resolvingRefs() -> ExportedSurface {
    let index = RefIndex(surface: self)
    return ExportedSurface(
      modules: modules.map { module in
        ExportedModule(
          name: module.name,
          jsName: module.jsName,
          functions: module.functions.map { $0.resolvingRefs(using: index) },
          properties: module.properties.map { $0.resolvingRefs(using: index) },
          events: module.events.map { $0.resolvingRefs(using: index) },
          file: module.file
        )
      },
      sharedObjects: sharedObjects.map { sharedObject in
        ExportedSharedObject(
          name: sharedObject.name,
          jsName: sharedObject.jsName,
          constructorParameters: sharedObject.constructorParameters?.map { $0.resolvingRefs(using: index) },
          functions: sharedObject.functions.map { $0.resolvingRefs(using: index) },
          properties: sharedObject.properties.map { $0.resolvingRefs(using: index) },
          events: sharedObject.events.map { $0.resolvingRefs(using: index) },
          file: sharedObject.file
        )
      },
      records: records.map { record in
        ExportedRecord(
          name: record.name,
          properties: record.properties.map { property in
            ExportedRecordProperty(
              name: property.name,
              type: property.type.resolvingRefs(using: index),
              isOptional: property.isOptional,
              hasDefault: property.hasDefault
            )
          },
          file: record.file
        )
      },
      // An enum's raw type is a primitive or an unscanned spelling, never a ref to another scanned
      // type, so there is nothing in one to resolve.
      enums: enums,
      unions: unions.map { union in
        ExportedUnion(
          name: union.name,
          members: union.members.map { member in
            ExportedUnionMember(name: member.name, type: member.type.resolvingRefs(using: index))
          },
          file: union.file
        )
      }
    )
  }
}

extension ExportedParameter {
  fileprivate func resolvingRefs(using index: RefIndex) -> ExportedParameter {
    return ExportedParameter(
      label: label, name: name, type: type.resolvingRefs(using: index), isOptional: isOptional)
  }
}

extension ExportedFunction {
  fileprivate func resolvingRefs(using index: RefIndex) -> ExportedFunction {
    return ExportedFunction(
      name: name,
      jsName: jsName,
      parameters: parameters.map { $0.resolvingRefs(using: index) },
      returns: returns?.resolvingRefs(using: index),
      isAsync: isAsync,
      isThrowing: isThrowing,
      isStatic: isStatic
    )
  }
}

extension ExportedProperty {
  fileprivate func resolvingRefs(using index: RefIndex) -> ExportedProperty {
    return ExportedProperty(
      name: name,
      jsName: jsName,
      type: type?.resolvingRefs(using: index),
      isSettable: isSettable,
      isStatic: isStatic
    )
  }
}

extension ExportedEvent {
  fileprivate func resolvingRefs(using index: RefIndex) -> ExportedEvent {
    return ExportedEvent(
      name: name, jsName: jsName, payload: payload?.resolvingRefs(using: index), isSync: isSync)
  }
}
