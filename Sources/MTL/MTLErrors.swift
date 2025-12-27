//
//  MTLErrors.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - MTL Execution Errors

/// Errors that can occur during MTL template execution.
///
/// These errors represent runtime issues encountered while generating text from
/// MTL templates, including missing templates, type mismatches, and file I/O problems.
public enum MTLExecutionError: Error, LocalizedError {

    /// The specified template was not found in the module.
    ///
    /// - Parameter String: The name of the template that could not be found.
    case templateNotFound(String)

    /// The specified query was not found in the module.
    ///
    /// - Parameter String: The name of the query that could not be found.
    case queryNotFound(String)

    /// The specified macro was not found in the module.
    ///
    /// - Parameter String: The name of the macro that could not be found.
    case macroNotFound(String)

    /// The specified variable was not found in the current scope.
    ///
    /// - Parameter String: The name of the variable that could not be found.
    case variableNotFound(String)

    /// A type error occurred during execution.
    ///
    /// - Parameter String: A description of the type error.
    case typeError(String)

    /// An invalid operation was attempted.
    ///
    /// - Parameter String: A description of the invalid operation.
    case invalidOperation(String)

    /// A file I/O error occurred.
    ///
    /// - Parameter String: A description of the file error.
    case fileError(String)

    /// A template guard condition failed.
    ///
    /// - Parameter String: The name of the template whose guard failed.
    case guardFailed(String)

    /// A template post-condition failed.
    ///
    /// - Parameter String: The name of the template whose post-condition failed.
    case postConditionFailed(String)

    /// A protected area ID conflict was detected.
    ///
    /// - Parameter String: A description of the conflict.
    case protectedAreaConflict(String)

    /// The specified module was not found.
    ///
    /// - Parameter String: The name of the module that could not be found.
    case moduleNotFound(String)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .templateNotFound(let name):
            return "Template '\(name)' not found in module"
        case .queryNotFound(let name):
            return "Query '\(name)' not found in module"
        case .macroNotFound(let name):
            return "Macro '\(name)' not found in module"
        case .variableNotFound(let name):
            return "Variable '\(name)' not found in current scope"
        case .typeError(let description):
            return "Type error: \(description)"
        case .invalidOperation(let description):
            return "Invalid operation: \(description)"
        case .fileError(let description):
            return "File error: \(description)"
        case .guardFailed(let templateName):
            return "Guard condition failed for template '\(templateName)'"
        case .postConditionFailed(let templateName):
            return "Post-condition failed for template '\(templateName)'"
        case .protectedAreaConflict(let description):
            return "Protected area conflict: \(description)"
        case .moduleNotFound(let name):
            return "Module '\(name)' not found"
        }
    }
}

// MARK: - MTL Parse Errors

/// Errors that can occur during MTL parsing and serialization.
///
/// These errors represent issues encountered while parsing MTL source files,
/// XMI documents, or serializing MTL modules.
public enum MTLParseError: Error, LocalizedError {

    /// Invalid MTL syntax was encountered.
    ///
    /// - Parameter String: A description of the syntax error.
    case invalidSyntax(String)

    /// An unknown statement type was encountered during parsing.
    ///
    /// - Parameter String: The unknown type identifier.
    case unknownStatementType(String)

    /// A malformed expression was encountered.
    ///
    /// - Parameter String: A description of the expression error.
    case malformedExpression(String)

    /// A malformed XMI structure was encountered.
    ///
    /// - Parameter String: A description of the XMI error.
    case malformedXMI(String)

    /// A required attribute was missing from an XMI element.
    ///
    /// - Parameters:
    ///   - attribute: The name of the missing attribute
    ///   - element: The name of the XMI element
    case missingAttribute(attribute: String, element: String)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidSyntax(let description):
            return "Invalid syntax: \(description)"
        case .unknownStatementType(let type):
            return "Unknown statement type: '\(type)'"
        case .malformedExpression(let description):
            return "Malformed expression: \(description)"
        case .malformedXMI(let description):
            return "Malformed XMI: \(description)"
        case .missingAttribute(let attribute, let element):
            return "Missing attribute '\(attribute)' in element '\(element)'"
        }
    }
}

// MARK: - MTL Resource Errors

/// Errors that can occur during MTL resource operations.
///
/// These errors represent issues with resource loading, saving, and management.
public enum MTLResourceError: Error, LocalizedError {

    /// No module is associated with the resource.
    case noModule

    /// The resource URI is invalid.
    ///
    /// - Parameter String: The invalid URI.
    case invalidURI(String)

    /// The resource could not be loaded.
    ///
    /// - Parameter String: A description of the load error.
    case loadError(String)

    /// The resource could not be saved.
    ///
    /// - Parameter String: A description of the save error.
    case saveError(String)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .noModule:
            return "No module associated with resource"
        case .invalidURI(let uri):
            return "Invalid resource URI: '\(uri)'"
        case .loadError(let description):
            return "Failed to load resource: \(description)"
        case .saveError(let description):
            return "Failed to save resource: \(description)"
        }
    }
}
