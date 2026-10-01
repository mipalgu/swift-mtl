//
//  MTLTypeMatcher.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

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
enum MTLTypeMatcher {

    /// The score of a match against a type that every value conforms to.
    static let unspecificDistance = 1000

    /// The score of a match against a type that cannot be checked at run time.
    static let unverifiableDistance = 900

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
            return isCollection(value) ? 1 : nil
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

    /// Whether a value is a collection.
    private static func isCollection(_ value: any EcoreValue) -> Bool {
        value is EcoreValueArray || value is [any EcoreValue]
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
