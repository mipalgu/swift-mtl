//
//  MTLQuery.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - MTL Query

/// Represents an MTL query - a side-effect-free operation returning a value.
///
/// Queries provide reusable computation logic in MTL modules, extending
/// AQL with custom operations that can be invoked from templates and other
/// queries. Unlike templates, queries do not generate text output.
///
/// ## Overview
///
/// MTL queries serve multiple purposes:
/// - **Code reuse**: Complex expressions can be encapsulated and reused
/// - **Type extension**: New operations can be added to existing types
/// - **Modularity**: Complex templates can be broken down into manageable functions
/// - **Testing**: Individual query functions can be tested independently
///
/// ## Side-Effect Freedom
///
/// Queries must be side-effect-free, meaning they:
/// - Do not modify model elements
/// - Do not write to files or output
/// - Only compute and return values
/// - Can be safely cached and memoized
///
/// ## Example Usage
///
/// ```swift
/// // Simple query
/// let fullNameQuery = MTLQuery(
///     name: "fullName",
///     parameters: [
///         MTLVariable(name: "person", type: "Person")
///     ],
///     returnType: "String",
///     body: MTLExpression(AQLBinaryExpression(
///         left: AQLNavigationExpression(
///             source: AQLVariableExpression(name: "person"),
///             property: "firstName"
///         ),
///         right: AQLNavigationExpression(
///             source: AQLVariableExpression(name: "person"),
///             property: "lastName"
///         ),
///         op: .concat
///     ))
/// )
///
/// // Type-checking query
/// let isPublicQuery = MTLQuery(
///     name: "isPublic",
///     parameters: [MTLVariable(name: "element", type: "Element")],
///     returnType: "Boolean",
///     body: MTLExpression(AQLNavigationExpression(
///         source: AQLVariableExpression(name: "element"),
///         property: "visibility"
///     ))
/// )
/// ```
///
/// - Note: Queries are immutable value types designed for safe concurrent
///   access during template execution.
public struct MTLQuery: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the query.
    ///
    /// Query names must be valid identifiers and are used for query
    /// invocation from templates and other queries.
    public let name: String

    /// The visibility of this query.
    ///
    /// Visibility controls whether the query can be invoked from other
    /// modules or only within its defining module.
    public let visibility: MTLVisibility

    /// The parameters accepted by this query.
    ///
    /// Parameters define the query's interface and must be provided
    /// when invoking the query. Each parameter specifies a name and
    /// expected type.
    public let parameters: [MTLVariable]

    /// The return type of the query.
    ///
    /// The return type specifies what kind of value the query computes,
    /// using AQL type notation (e.g., "String", "Integer", "Boolean",
    /// "Collection(Element)").
    public let returnType: String

    /// The query body expression.
    ///
    /// The body expression is evaluated to compute the query's return value.
    /// It has access to all declared parameters through the execution context.
    public let body: MTLExpression

    /// Optional documentation string.
    ///
    /// Documentation provides usage information and is preserved in the AST
    /// for tool support and code generation.
    public let documentation: String?

    // MARK: - Initialisation

    /// Creates a new MTL query.
    ///
    /// - Parameters:
    ///   - name: The query name for invocation
    ///   - visibility: The visibility level (default: .public)
    ///   - parameters: The parameter list (default: empty)
    ///   - returnType: The return type specification
    ///   - body: The expression that computes the query's result
    ///   - documentation: Optional documentation (default: nil)
    ///
    /// - Precondition: The query name must be a non-empty string
    /// - Precondition: The return type must be a non-empty string
    public init(
        name: String,
        visibility: MTLVisibility = .public,
        parameters: [MTLVariable] = [],
        returnType: String,
        body: MTLExpression,
        documentation: String? = nil
    ) {
        precondition(!name.isEmpty, "Query name must not be empty")
        precondition(!returnType.isEmpty, "Return type must not be empty")

        self.name = name
        self.visibility = visibility
        self.parameters = parameters
        self.returnType = returnType
        self.body = body
        self.documentation = documentation
    }
}
