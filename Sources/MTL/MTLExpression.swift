//
//  MTLExpression.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import AQL
import EMFBase
import Foundation

// MARK: - MTL Expression

/// A thin wrapper around AQL expressions for MTL template evaluation.
///
/// MTL expressions delegate all evaluation to the Acceleo Query Language (AQL),
/// which provides a rich expression system for model navigation, collection operations,
/// and standard library functions.
///
/// ## Overview
///
/// MTL uses AQL for all expression evaluation, including:
/// - Model navigation (e.g., `object.property`, `object.reference`)
/// - Collection operations (e.g., `collection->select()`, `collection->collect()`)
/// - Arithmetic and logical operations
/// - String manipulation and interpolation
/// - Type checking and casting
///
/// ## Example Usage
///
/// ```swift
/// // Literal expression
/// let literalExpr = MTLExpression(AQLLiteralExpression(value: "Hello"))
///
/// // Variable reference
/// let varExpr = MTLExpression(AQLVariableExpression(name: "model"))
///
/// // Navigation
/// let sourceExpr = MTLExpression(AQLVariableExpression(name: "element"))
/// let navExpr = MTLExpression(AQLNavigationExpression(
///     source: sourceExpr.aqlExpression,
///     property: "name"
/// ))
///
/// // String interpolation
/// let interpolExpr = MTLExpression(AQLStringInterpolationExpression(
///     parts: [
///         AQLStringInterpolationExpression.Part(literal: "Name: "),
///         AQLStringInterpolationExpression.Part(literal: "", expression: navExpr.aqlExpression)
///     ]
/// ))
/// ```
///
/// - Note: MTL expressions are immutable value types designed for safe concurrent
///   access during parallel template execution.
public struct MTLExpression: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The underlying AQL expression that will be evaluated.
    ///
    /// All expression evaluation is delegated to AQL, which handles:
    /// - Variable resolution and scoping
    /// - Model navigation through ECore
    /// - Collection iteration and filtering
    /// - Standard library function invocation
    /// - Type checking and conversion
    public let aqlExpression: any AQLExpression

    // MARK: - Initialisation

    /// Creates a new MTL expression wrapping an AQL expression.
    ///
    /// - Parameter aqlExpression: The AQL expression to wrap
    ///
    /// - Note: The AQL expression must conform to the `AQLExpression` protocol
    ///   and must be `Sendable` for thread-safe concurrent access.
    public init(_ aqlExpression: any AQLExpression) {
        self.aqlExpression = aqlExpression
    }

    // MARK: - Evaluation

    /// Evaluates the expression within the specified MTL execution context.
    ///
    /// Evaluation is delegated to the underlying AQL expression, which is executed
    /// within the AQL execution context wrapped by the MTL execution context.
    ///
    /// - Parameter context: The MTL execution context providing variable bindings,
    ///   model access, and AQL integration
    /// - Returns: The result of evaluating the expression, or `nil` if the expression
    ///   evaluates to null
    /// - Throws: `MTLExecutionError` if evaluation fails due to undefined variables,
    ///   type errors, or other runtime issues
    ///
    /// - Note: This method must be called from a `@MainActor` context to ensure
    ///   thread-safe access to the execution context and model resources.
    @MainActor
    public func evaluate(in context: MTLExecutionContext) async throws -> (any EcoreValue)? {
        return try await context.evaluateExpression(self)
    }

    // MARK: - Equatable

    /// Compares two MTL expressions for equality.
    ///
    /// Two expressions are equal if their underlying AQL expressions are equal.
    /// Since AQL expressions use type erasure, equality is determined by comparing
    /// the type-erased expressions.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side expression
    ///   - rhs: The right-hand side expression
    /// - Returns: `true` if the expressions are equal, `false` otherwise
    public static func == (lhs: MTLExpression, rhs: MTLExpression) -> Bool {
        return areAQLExpressionsEqual(lhs.aqlExpression, rhs.aqlExpression)
    }

    // MARK: - Hashable

    /// Hashes the essential components of the expression into the given hasher.
    ///
    /// The hash value is computed from the underlying AQL expression using
    /// type-erased hashing to support heterogeneous expression collections.
    ///
    /// - Parameter hasher: The hasher to use when combining the components
    ///   of this instance
    public func hash(into hasher: inout Hasher) {
        hashAQLExpression(aqlExpression, into: &hasher)
    }
}

// MARK: - Type Erasure Helpers

/// Compares two type-erased AQL expressions for equality.
///
/// This function enables equality comparison of heterogeneous AQL expression
/// collections. Currently uses object identity as a placeholder.
///
/// - Parameters:
///   - lhs: The left-hand side AQL expression
///   - rhs: The right-hand side AQL expression
/// - Returns: `true` if the expressions are equal, `false` otherwise
///
/// - Note: This is a placeholder implementation. Full structural equality
///   will be implemented when AQL expressions gain Equatable conformance.
private func areAQLExpressionsEqual(_ lhs: any AQLExpression, _ rhs: any AQLExpression) -> Bool {
    // Placeholder: use object identity
    return ObjectIdentifier(type(of: lhs)) == ObjectIdentifier(type(of: rhs))
}

/// Hashes a type-erased AQL expression into the given hasher.
///
/// This function enables hashing of heterogeneous AQL expression collections.
/// Currently uses type identity as a placeholder.
///
/// - Parameters:
///   - expression: The AQL expression to hash
///   - hasher: The hasher to use
///
/// - Note: This is a placeholder implementation. Full structural hashing
///   will be implemented when AQL expressions gain Hashable conformance.
private func hashAQLExpression(_ expression: any AQLExpression, into hasher: inout Hasher) {
    // Placeholder: use type identity
    hasher.combine(ObjectIdentifier(type(of: expression)))
}
