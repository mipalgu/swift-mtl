//
// MTLParameterServices.swift
// MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation

// MARK: - Service Names

/// The names of the services that give templates access to named parameters.
public enum MTLParameterServiceName {
    /// The service `parameter('name')`, which returns the value of a parameter.
    public static let parameter = "parameter"

    /// The service `hasParameter('name')`, which tells whether a parameter was given.
    public static let hasParameter = "hasParameter"

    /// The character that separates a parameter name from its value in `name=value` text.
    public static let assignment: Character = "="
}

// MARK: - Errors

/// The problems found when reading template parameters.
///
/// Each case carries the offending text and describes how to correct it.
public enum MTLParameterError: Error, LocalizedError, Equatable, Sendable {
    /// The text is not of the form `name=value`.
    case invalidParameter(String)

    /// The name is not an identifier.
    case invalidParameterName(String)

    /// The name is a word that the MTL or AQL syntax reserves.
    case reservedParameterName(String)

    public var errorDescription: String? {
        switch self {
        case .invalidParameter(let text):
            return "Invalid parameter '\(text)': expected name=value"
        case .invalidParameterName(let name):
            return "Invalid parameter name '\(name)': a name must be an identifier "
                + "(a letter or underscore followed by letters, digits or underscores)"
        case .reservedParameterName(let name):
            return "Invalid parameter name '\(name)': the word is reserved by the template syntax"
        }
    }
}

// MARK: - Parameter Services

/// Gives templates access to named parameters such as command line options.
///
/// Each parameter is also bound as a global variable, so that `[package/]` reads the parameter
/// `package` in any template or query; see ``bind(to:)``. A parameter name must be an identifier
/// (a letter or underscore followed by letters, digits or underscores) and must not be a word
/// that the MTL or AQL syntax reserves, see ``MTLSyntax/reservedWords``.
///
/// The values are also offered through two standalone services once the instance is registered
/// with ``MTLGenerator/register(_:)``:
/// - `parameter('name')` returns the value of the parameter, or `null` if it was not given.
/// - `hasParameter('name')` returns `true` if the parameter was given.
///
/// Text values are typed by ``value(of:)``: a boolean when the text is `true` or `false`, an
/// integer when it is a whole number in canonical form, and a string otherwise. In a template,
/// `[parameter('package')/]` writes the value and `[if (parameter('verbose'))]` tests a flag.
///
/// ## Example
///
/// ```swift
/// let parameters = try MTLParameterServices(arguments: ["package=org.example", "verbose=true"])
/// parameters.bind(to: generator)
/// generator.register(parameters)
/// ```
public struct MTLParameterServices: AQLServiceProvider {
    /// The parameter values by name.
    public let values: [String: any EcoreValue]

    /// Creates the services from text parameters.
    ///
    /// - Parameter parameters: The values by name; each text is typed by ``value(of:)``.
    /// - Throws: ``MTLParameterError/invalidParameterName(_:)`` if a name is not an identifier and
    ///   ``MTLParameterError/reservedParameterName(_:)`` if a name is a reserved word.
    public init(parameters: [String: String]) throws {
        try self.init(values: parameters.mapValues { Self.value(of: $0) })
    }

    /// Creates the services from typed values.
    ///
    /// - Parameter values: The values by name, which are used as given.
    /// - Throws: ``MTLParameterError/invalidParameterName(_:)`` if a name is not an identifier and
    ///   ``MTLParameterError/reservedParameterName(_:)`` if a name is a reserved word.
    public init(values: [String: any EcoreValue]) throws {
        for name in values.keys { try Self.validate(name: name) }
        self.values = values
    }

    /// Creates the services from `name=value` arguments.
    ///
    /// - Parameter arguments: The arguments as `name=value`; the value is everything after the
    ///   first `=`, and a later argument replaces an earlier one of the same name.
    /// - Throws: ``MTLParameterError`` if an argument has no name or no `=`, or has an invalid
    ///   or reserved name.
    public init(arguments: [String]) throws {
        var values: [String: any EcoreValue] = [:]
        for argument in arguments {
            let (name, value) = try Self.parse(argument)
            values[name] = value
        }
        self.values = values
    }

    /// Reads one parameter from `name=value` text.
    ///
    /// - Parameter text: The text; the value is everything after the first `=`.
    /// - Returns: The parameter name and its typed value.
    /// - Throws: ``MTLParameterError/invalidParameter(_:)`` if the text has no name or no `=`,
    ///   ``MTLParameterError/invalidParameterName(_:)`` if the name is not an identifier, and
    ///   ``MTLParameterError/reservedParameterName(_:)`` if the name is a reserved word.
    public static func parse(_ text: String) throws -> (name: String, value: any EcoreValue) {
        guard let separator = text.firstIndex(of: MTLParameterServiceName.assignment),
            separator != text.startIndex
        else {
            throw MTLParameterError.invalidParameter(text)
        }
        let name = String(text[..<separator])
        try validate(name: name)
        return (name, value(of: String(text[text.index(after: separator)...])))
    }

    /// Checks that a parameter name can be read back as a variable.
    ///
    /// - Parameter name: The parameter name.
    /// - Throws: ``MTLParameterError/invalidParameterName(_:)`` if the name is not an identifier,
    ///   and ``MTLParameterError/reservedParameterName(_:)`` if it is a reserved word.
    public static func validate(name: String) throws {
        guard let first = name.unicodeScalars.first,
            isIdentifierStart(first),
            name.unicodeScalars.allSatisfy({ isIdentifierStart($0) || ("0"..."9").contains($0) })
        else {
            throw MTLParameterError.invalidParameterName(name)
        }
        guard !MTLSyntax.reservedWords.contains(name) else {
            throw MTLParameterError.reservedParameterName(name)
        }
    }

    /// Reports whether a character may start an identifier.
    private static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || scalar == "_"
    }

    /// Binds every parameter as a global variable of a generator.
    ///
    /// - Parameter generator: The generator whose templates and queries can then read each
    ///   parameter as a bare variable.
    @MainActor
    public func bind(to generator: MTLGenerator) {
        for (name, value) in values {
            generator.setGlobalVariable(name, value: value)
        }
    }

    /// Converts parameter text to a boolean, an integer or a string.
    ///
    /// - Parameter text: The text of the value.
    /// - Returns: `true` or `false` for those words, an `Int` for a whole number in canonical
    ///   form, and the text itself otherwise.
    public static func value(of text: String) -> any EcoreValue {
        switch text {
        case "true": return true
        case "false": return false
        default:
            if let integer = Int(text), String(integer) == text { return integer }
            return text
        }
    }

    /// The services offered to templates: `parameter` and `hasParameter`.
    public var services: [AQLService] {
        let values = self.values
        return [
            AQLService(MTLParameterServiceName.parameter, receiver: .standalone, arity: 1) { call in
                values[try call.string(0)]
            },
            AQLService(MTLParameterServiceName.hasParameter, receiver: .standalone, arity: 1) { call in
                values[try call.string(0)] != nil
            },
        ]
    }
}
