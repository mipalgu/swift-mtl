//
//  MTLVariable.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - MTL Variable

/// Represents a variable or parameter declaration in MTL.
///
/// Variables are used to define template parameters, query parameters,
/// macro parameters, and loop iteration variables. They specify both
/// the variable name for binding and the expected type for validation.
///
/// ## Example Usage
///
/// ```swift
/// // Template parameter
/// let modelParam = MTLVariable(name: "model", type: "Model")
///
/// // Query parameter
/// let nameParam = MTLVariable(name: "name", type: "String")
///
/// // Loop variable
/// let itemVar = MTLVariable(name: "item", type: "Element")
/// ```
public struct MTLVariable: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the variable.
    ///
    /// Variable names are used for binding within the scope of templates,
    /// queries, and other MTL constructs.
    public let name: String

    /// The type of the variable.
    ///
    /// Variable types are specified using AQL type expressions, supporting
    /// both primitive types (String, Integer, Boolean) and metamodel element types.
    public let type: String

    // MARK: - Initialisation

    /// Creates a new MTL variable.
    ///
    /// - Parameters:
    ///   - name: The variable name for binding
    ///   - type: The variable type specification
    ///
    /// - Precondition: The variable name must be a non-empty string
    /// - Precondition: The variable type must be a non-empty string
    public init(name: String, type: String) {
        precondition(!name.isEmpty, "Variable name must not be empty")
        precondition(!type.isEmpty, "Variable type must not be empty")

        self.name = name
        self.type = type
    }
}

// MARK: - MTL Binding

/// Represents a variable binding with an initialization expression.
///
/// Bindings associate a variable with a value computed from an expression.
/// They are used in `let` statements and `for` loops to bind variables
/// in nested scopes.
///
/// ## Overview
///
/// MTL bindings serve multiple purposes:
/// - **For loops**: Bind iteration variables to collection elements
/// - **Let statements**: Bind temporary variables to computed values
/// - **Macro parameters**: Bind macro arguments to parameters
///
/// ## Example Usage
///
/// ```swift
/// // For loop binding
/// let loopVar = MTLVariable(name: "item", type: "Element")
/// let collectionExpr = MTLExpression(AQLNavigationExpression(...))
/// let forBinding = MTLBinding(
///     variable: loopVar,
///     initExpression: collectionExpr
/// )
///
/// // Let binding
/// let tempVar = MTLVariable(name: "fullName", type: "String")
/// let concatExpr = MTLExpression(AQLBinaryExpression(...))
/// let letBinding = MTLBinding(
///     variable: tempVar,
///     initExpression: concatExpr
/// )
/// ```
public struct MTLBinding: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The variable being bound.
    ///
    /// This variable will be available in the nested scope with the
    /// value computed from the initialization expression.
    public let variable: MTLVariable

    /// The expression that computes the variable's value.
    ///
    /// This expression is evaluated when the binding is established,
    /// and its result is assigned to the variable for the duration
    /// of the nested scope.
    public let initExpression: MTLExpression

    // MARK: - Initialisation

    /// Creates a new MTL variable binding.
    ///
    /// - Parameters:
    ///   - variable: The variable to bind
    ///   - initExpression: The expression that computes the variable's value
    public init(variable: MTLVariable, initExpression: MTLExpression) {
        self.variable = variable
        self.initExpression = initExpression
    }
}
