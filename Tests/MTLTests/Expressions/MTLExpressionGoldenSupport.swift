//
//  MTLExpressionGoldenSupport.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import Testing

@testable import MTL

/// Parses corpus expressions with the MTL parser and prints their trees.
enum MTLExpressionGoldenSupport {

    /// The printer for trees that contain MTL nodes.
    static let printer = AQLTreePrinter { expression, printer in
        switch expression {
        case let node as MTLInvocationExpression:
            return "invoke(\(printer.optional(node.receiver)), \(node.name), "
                + "args: \(printer.list(node.arguments)))"
        case let node as MTLCollectedExpression:
            return "collected(\(printer.print(node.setName)))"
        default:
            return nil
        }
    }

    /// Parses an expression written as the only statement of a one-line template.
    ///
    /// - Parameter source: The expression text.
    /// - Returns: The parsed expression.
    /// - Throws: The parse error, if any.
    static func parse(_ source: String) async throws -> any AQLExpression {
        let module = try await MTLTestSupport.parse(
            "[module m('u')/][template main()][\(source)/][/template]")
        let statement = try #require(module.templates["main"]?.body.statements.first as? MTLExpressionStatement)
        return statement.expression.aqlExpression
    }

    /// Parses an expression and prints its tree.
    ///
    /// - Parameter source: The expression text.
    /// - Returns: The printed tree.
    /// - Throws: The parse error, if any.
    static func tree(_ source: String) async throws -> String {
        printer.print(try await parse(source))
    }
}
