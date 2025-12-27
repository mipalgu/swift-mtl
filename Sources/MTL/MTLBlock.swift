//
//  MTLBlock.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - MTL Block

/// Represents a block of MTL statements.
///
/// Blocks group statements together for execution as a unit, supporting
/// both inlined blocks (no indentation) and standard blocks (with indentation).
/// They form the body of templates, loops, conditionals, and other control structures.
///
/// ## Overview
///
/// MTL blocks serve multiple purposes:
/// - **Template bodies**: The main content of a template
/// - **Control flow bodies**: Content within for loops, if statements, etc.
/// - **File blocks**: Content to be written to a specific file
/// - **Macro bodies**: Reusable content patterns
///
/// ## Example Usage
///
/// ```swift
/// // Simple text block
/// let textBlock = MTLBlock(statements: [
///     MTLTextStatement(value: "public class "),
///     MTLExpressionStatement(expression: nameExpr),
///     MTLTextStatement(value: " {"),
///     MTLNewLineStatement()
/// ])
///
/// // Inlined block (no indentation changes)
/// let inlinedBlock = MTLBlock(
///     statements: [
///         MTLTextStatement(value: "inline content")
///     ],
///     inlined: true
/// )
/// ```
///
/// - Note: MTL blocks use type erasure to store heterogeneous statement collections
///   while maintaining `Equatable` and `Hashable` conformance.
public struct MTLBlock: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The statements in this block.
    ///
    /// Statements are executed in order within the block's scope. The
    /// statement array may contain any combination of statement types.
    public let statements: [any MTLStatement]

    /// Whether this block is inlined (no indentation changes).
    ///
    /// Inlined blocks execute their statements without pushing/popping
    /// indentation levels, allowing inline content generation.
    public let inlined: Bool

    // MARK: - Initialisation

    /// Creates a new MTL block.
    ///
    /// - Parameters:
    ///   - statements: The statements to execute in this block
    ///   - inlined: Whether this block is inlined (default: false)
    public init(statements: [any MTLStatement], inlined: Bool = false) {
        self.statements = statements
        self.inlined = inlined
    }

    // MARK: - Execution

    /// Executes all statements in this block within the given context.
    ///
    /// If the block is not inlined, indentation is pushed before execution
    /// and popped afterward. Statements are executed sequentially.
    ///
    /// - Parameter context: The execution context
    /// - Throws: `MTLExecutionError` if any statement execution fails
    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        if !inlined {
            context.pushIndentation()
        }

        defer {
            if !inlined {
                context.popIndentation()
            }
        }

        for statement in statements {
            try await statement.execute(in: context)
        }
    }

    // MARK: - Equatable

    /// Compares two MTL blocks for equality.
    ///
    /// Two blocks are equal if they have the same inlined flag and their
    /// statement arrays are equal using type-erased comparison.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side block
    ///   - rhs: The right-hand side block
    /// - Returns: `true` if the blocks are equal, `false` otherwise
    public static func == (lhs: MTLBlock, rhs: MTLBlock) -> Bool {
        guard lhs.inlined == rhs.inlined else { return false }
        guard lhs.statements.count == rhs.statements.count else { return false }

        for (lhsStmt, rhsStmt) in zip(lhs.statements, rhs.statements) {
            if !areStatementsEqual(lhsStmt, rhsStmt) {
                return false
            }
        }

        return true
    }

    // MARK: - Hashable

    /// Hashes the essential components of the block into the given hasher.
    ///
    /// The hash value is computed from the inlined flag and all statements
    /// using type-erased hashing.
    ///
    /// - Parameter hasher: The hasher to use when combining the components
    ///   of this instance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(inlined)
        for statement in statements {
            hashStatement(statement, into: &hasher)
        }
    }
}

// MARK: - Type Erasure Helpers

/// Compares two type-erased MTL statements for equality.
///
/// This function enables equality comparison of heterogeneous statement
/// collections by using `AnyHashable` for type erasure.
///
/// - Parameters:
///   - lhs: The left-hand side statement
///   - rhs: The right-hand side statement
/// - Returns: `true` if the statements are equal, `false` otherwise
private func areStatementsEqual(_ lhs: any MTLStatement, _ rhs: any MTLStatement) -> Bool {
    return AnyHashable(lhs) == AnyHashable(rhs)
}

/// Hashes a type-erased MTL statement into the given hasher.
///
/// This function enables hashing of heterogeneous statement collections
/// by using `AnyHashable` for type erasure.
///
/// - Parameters:
///   - statement: The statement to hash
///   - hasher: The hasher to use
private func hashStatement(_ statement: any MTLStatement, into hasher: inout Hasher) {
    hasher.combine(AnyHashable(statement))
}
