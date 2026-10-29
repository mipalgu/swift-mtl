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
/// A collection conforms to every collection type, such as `Sequence(T)`,
/// `OrderedSet(T)` or `Collection(T)`. The element types of collection
/// arguments are not checked. Collections include the values of many-valued
/// features, which may be held as plain arrays. A single model object also
/// conforms to a collection type whose element type it conforms to, as the
/// only element of the collection, but less specifically than to any other
/// type, because a many-valued feature with just one element may hold that
/// element on its own.
enum MTLTypeMatcher {

    /// The score of a match against a type that every value conforms to.
    static let unspecificDistance = 1000

    /// The score of a match against a type that cannot be checked at run time.
    static let unverifiableDistance = 900

    /// The score of a collection matching a collection type.
    static let collectionDistance = 1

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
        let type = simpleName(of: declaredType)
        if type == MTLSyntax.anyType { return unspecificDistance }
        guard let value = value else { return unspecificDistance }

        if let head = collectionHead(of: type) {
            guard MTLSyntax.collectionTypeNames.contains(head) else { return nil }
            return distance(ofCollection: value, elementType: elementType(of: type))
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
    /// A collection matches without its elements being checked. A single model object
    /// matches only if it conforms to the element type, and then scores worse than any
    /// other match.
    ///
    /// - Parameters:
    ///   - value: The value, a collection or a single model object.
    ///   - elementType: The declared element type of the collection type, or `nil` for any element.
    /// - Returns: The distance, or `nil` if the value is neither a collection nor a model object
    ///   conforming to the element type.
    private static func distance(ofCollection value: any EcoreValue, elementType: String?) -> Int? {
        if AQLValues.elements(of: value) != nil { return collectionDistance }
        guard value is any EObject,
              let distance = distance(of: value, to: elementType ?? MTLSyntax.anyType) else { return nil }
        return singletonDistance + distance
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
