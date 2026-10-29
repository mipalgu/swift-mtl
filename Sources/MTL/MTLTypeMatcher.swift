//
//  MTLTypeMatcher.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation

// MARK: - Type Matcher

/// Decides whether a runtime value conforms to a declared parameter type.
///
/// Template and query overloads are told apart by the declared types of their
/// parameters. The matcher scores how specific a match is, so that the most
/// specific overload can be chosen: an exact match scores zero, each step up
/// the inheritance hierarchy adds one, and the catch-all types score highest.
///
/// A collection, including the value of a many-valued feature, conforms to a
/// collection type, such as `Sequence(T)`, `OrderedSet(T)` or `Collection(T)`,
/// if each of its elements conforms to the element type `T`. The match scores
/// the collection distance plus the score of the least specific element, so
/// that a collection prefers the overload whose element type fits all of its
/// elements most closely. A collection whose elements fit only `OclAny` still
/// prefers a collection type to `OclAny` itself. An empty collection conforms
/// to every collection type with the collection distance alone, so that it is
/// equally specific for every collection type and never prefers one element
/// type to another; equally specific overloads are told apart as usual. Null
/// cannot be an element of a collection value. A collection type without an
/// element type, such as `Sequence`, accepts every collection with the
/// collection distance, and nested collection types, such as
/// `Sequence(Sequence(String))`, are checked level by level.
///
/// A single model object also conforms to a collection type whose element type
/// it conforms to, as the only element of the collection, but less specifically
/// than to any other type, because a many-valued feature with just one element
/// may hold that element on its own. This does not apply to the elements of a
/// collection matched against a nested collection type.
enum MTLTypeMatcher {

    /// The score of a match against a type that every value conforms to.
    static let unspecificDistance = 1000

    /// The score of a match against a type that cannot be checked at run time.
    static let unverifiableDistance = 900

    /// The score of a collection matching a collection type, before its elements are scored.
    static let collectionDistance = 1

    /// The greatest score that the elements of a collection add to its collection distance.
    ///
    /// The limit keeps every match of a collection against a collection type, whatever
    /// its element type, more specific than a match against `OclAny`.
    static let elementDistanceLimit = unspecificDistance - collectionDistance - 1

    /// The score of a single model object matching a collection type, before it is scored as an element.
    static let singletonDistance = unspecificDistance + collectionDistance

    /// The aliases for the primitive types that Ecore data type names use.
    private static let primitiveAliases: [String: String] = [
        "EString": "String",
        "EInt": "Integer", "EIntegerObject": "Integer", "ELong": "Integer", "EShort": "Integer",
        "EBoolean": "Boolean", "EBooleanObject": "Boolean",
        "EDouble": "Real", "EFloat": "Real", "EDoubleObject": "Real"
    ]

    /// Scores how well a value matches a declared type.
    ///
    /// - Parameters:
    ///   - value: The runtime value; `nil` stands for null, which matches every type.
    ///   - declaredType: The declared type, such as `String`, `ecore::EClass`, or `Sequence(EClass)`.
    /// - Returns: The distance (lower is more specific), or `nil` if the value does not conform.
    static func distance(of value: (any EcoreValue)?, to declaredType: String) -> Int? {
        distance(of: value, toSimpleType: simpleName(of: declaredType), acceptingSingleton: true)
    }

    /// Scores how well a value matches a type without package qualification.
    ///
    /// - Parameters:
    ///   - value: The runtime value; `nil` stands for null, which matches every type.
    ///   - type: The type, with its package qualification removed.
    ///   - acceptingSingleton: Whether a single model object may stand for a collection of itself.
    /// - Returns: The distance, or `nil` if the value does not conform.
    private static func distance(
        of value: (any EcoreValue)?, toSimpleType type: String, acceptingSingleton: Bool
    ) -> Int? {
        if type == MTLSyntax.anyType { return unspecificDistance }
        guard let value = value else { return unspecificDistance }

        if let head = collectionHead(of: type) {
            guard MTLSyntax.collectionTypeNames.contains(head) else { return nil }
            return distance(
                ofCollection: value, elementType: elementType(of: type).map(simpleName(of:)),
                acceptingSingleton: acceptingSingleton)
        }

        let canonical = primitiveAliases[type] ?? type
        if let accepted = MTLSyntax.primitiveTypeNames[canonical] {
            let actual = String(describing: Swift.type(of: value))
            guard accepted.contains(actual) else { return nil }
            return canonical == "Real" && actual == "Int" ? 1 : 0
        }

        return objectDistance(of: value, to: type)
    }

    /// The type name without any package qualification.
    ///
    /// - Parameter declaredType: A possibly qualified type name.
    /// - Returns: The last segment of the name, keeping any parenthesised element type.
    static func simpleName(of declaredType: String) -> String {
        let head = declaredType.prefix(while: { $0 != "(" })
        let tail = declaredType.dropFirst(head.count)
        let simple = head.components(separatedBy: MTLSyntax.qualifiedNameSeparator).last ?? String(head)
        return simple + tail
    }

    /// The collection kind of a type such as `Sequence(EClass)`.
    private static func collectionHead(of type: String) -> String? {
        guard let open = type.firstIndex(of: "(") else {
            return MTLSyntax.collectionTypeNames.contains(type) ? type : nil
        }
        return String(type[..<open])
    }

    /// The element type of a collection type such as `Sequence(EClass)`.
    ///
    /// - Parameter type: A collection type, with or without an element type.
    /// - Returns: The element type, or `nil` if none is given.
    private static func elementType(of type: String) -> String? {
        guard let open = type.firstIndex(of: "("), let close = type.lastIndex(of: ")"), open < close else {
            return nil
        }
        let element = type[type.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return element.isEmpty ? nil : element
    }

    /// Scores a value against a collection type.
    ///
    /// A collection matches if each of its elements conforms to the element type, and
    /// scores the collection distance plus the least specific element score, up to
    /// ``elementDistanceLimit``. A single model object matches only if it conforms to the
    /// element type, and then scores worse than any other match.
    ///
    /// - Parameters:
    ///   - value: The value, a collection or a single model object.
    ///   - elementType: The declared element type without package qualification, or `nil` for any element.
    ///   - acceptingSingleton: Whether a single model object may stand for a collection of itself.
    /// - Returns: The distance, or `nil` if the value is neither a collection of conforming
    ///   elements nor an accepted model object conforming to the element type.
    private static func distance(
        ofCollection value: any EcoreValue, elementType: String?, acceptingSingleton: Bool
    ) -> Int? {
        guard let elements = AQLValues.elements(of: value) else {
            guard acceptingSingleton, value is any EObject,
                  let distance = distance(
                    of: value, toSimpleType: elementType ?? MTLSyntax.anyType, acceptingSingleton: false)
            else { return nil }
            return singletonDistance + distance
        }
        guard let elementType else { return collectionDistance }
        guard let distance = distance(ofElements: elements, to: elementType) else { return nil }
        return collectionDistance + min(distance, elementDistanceLimit)
    }

    /// Scores the elements of a collection against an element type.
    ///
    /// The walk stops at the first element that does not conform. Model objects of a
    /// metaclass that has already been scored are not scored again.
    ///
    /// - Parameters:
    ///   - elements: The elements of the collection.
    ///   - elementType: The element type without package qualification.
    /// - Returns: The score of the least specific element, zero if there are no elements,
    ///   or `nil` if an element does not conform.
    private static func distance(ofElements elements: [any EcoreValue], to elementType: String) -> Int? {
        if elementType == MTLSyntax.anyType { return elements.isEmpty ? 0 : unspecificDistance }
        var greatest = 0
        var scoredMetaclasses: Set<EUUID> = []
        for element in elements {
            let metaclass = (element as? DynamicEObject)?.eClass.id
            if let metaclass, scoredMetaclasses.contains(metaclass) { continue }
            guard let distance = distance(of: element, toSimpleType: elementType, acceptingSingleton: false) else {
                return nil
            }
            if let metaclass { scoredMetaclasses.insert(metaclass) }
            greatest = max(greatest, distance)
        }
        return greatest
    }

    /// The value that a parameter of a declared type holds for an argument.
    ///
    /// For a collection type, a collection becomes a collection value and a single value
    /// becomes the only element of one. Other values are held unchanged.
    ///
    /// - Parameters:
    ///   - value: The argument, which conforms to the declared type.
    ///   - declaredType: The declared type of the parameter.
    /// - Returns: The value of the parameter, or `nil` for null.
    static func boundValue(of value: (any EcoreValue)?, to declaredType: String) -> (any EcoreValue)? {
        guard let value, !(value is EcoreValueArray),
              let head = collectionHead(of: simpleName(of: declaredType)),
              MTLSyntax.collectionTypeNames.contains(head) else { return value }
        return AQLValues.collection(AQLValues.coerceToCollection(value))
    }

    /// The name of the type of a value, as a template would declare it.
    ///
    /// A model object is named by its metaclass, a collection as ``MTLSyntax/collectionType``,
    /// and a primitive value by its primitive type, such as `Integer`. Any other value is
    /// named by the type that implements it.
    ///
    /// - Parameter value: The value.
    /// - Returns: The name of the type of the value.
    static func typeName(of value: any EcoreValue) -> String {
        if let object = value as? any EObject { return object.eClass.name }
        if AQLValues.elements(of: value) != nil { return MTLSyntax.collectionType }
        let primitive = MTLSyntax.primitiveTypeNames.keys.sorted().first { distance(of: value, to: $0) == 0 }
        return primitive ?? String(describing: Swift.type(of: value))
    }

    /// Scores a model object against a metaclass name.
    private static func objectDistance(of value: any EcoreValue, to type: String) -> Int? {
        guard let object = value as? any EObject else { return nil }

        if let dynamic = object as? DynamicEObject {
            if dynamic.eClass.name == type { return 0 }
            if let index = dynamic.eClass.allSuperTypes.firstIndex(where: { $0.name == type }) {
                return index + 1
            }
            return type == "EObject" ? unverifiableDistance : nil
        }

        if object.eClass.name == type || String(describing: Swift.type(of: object)) == type {
            return 0
        }
        return unverifiableDistance
    }
}
