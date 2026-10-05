//
//  AQLTreePrinter.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import EMFBase

/// Prints an AQL expression tree as one deterministic line for golden tests.
///
/// Every node prints as `kind(field, field, ...)` with children nested in the same form, so
/// two trees print identically exactly when they have the same shape, operators, names and
/// literal values. Host packages supply a hook for the node types that only they know.
struct AQLTreePrinter {

    /// Prints a node that the printer does not know itself.
    ///
    /// The hook receives the node and the printer (to print children) and returns `nil` for
    /// nodes it does not know either.
    typealias Hook = @Sendable (any AQLExpression, AQLTreePrinter) -> String?

    /// The hook for host-specific node types.
    let hook: Hook?

    /// Creates a printer.
    ///
    /// - Parameter hook: The hook for host-specific node types, if any.
    init(hook: Hook? = nil) {
        self.hook = hook
    }

    /// Prints an optional child, using `-` for none.
    func optional(_ expression: (any AQLExpression)?) -> String {
        expression.map { print($0) } ?? "-"
    }

    /// Prints a list of children.
    func list(_ expressions: [any AQLExpression]) -> String {
        "[" + expressions.map { print($0) }.joined(separator: ", ") + "]"
    }

    /// Quotes a string with the characters that would hide structure escaped.
    func quoted(_ text: String) -> String {
        var result = "\""
        for character in text {
            switch character {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            default: result.append(character)
            }
        }
        return result + "\""
    }

    /// Prints a literal value with its type.
    func literal(_ value: (any EcoreValue)?) -> String {
        switch value {
        case nil: return "null"
        case let text as String: return "string(\(quoted(text)))"
        case let flag as Bool: return "bool(\(flag))"
        case let number as Int: return "int(\(number))"
        case let number as Double: return "real(\(number))"
        case let other?: return "value(\(type(of: other)), \(other))"
        }
    }

    /// Prints an expression tree.
    ///
    /// - Parameter expression: The root of the tree.
    /// - Returns: The tree on one line.
    func print(_ expression: any AQLExpression) -> String {
        switch expression {
        case let node as AQLVariableExpression:
            return "var(\(node.name))"
        case let node as AQLNavigationExpression:
            return "nav(\(print(node.source)), \(node.property), nullSafe: \(node.isNullSafe))"
        case let node as AQLLiteralExpression:
            return "lit(\(literal(node.value)))"
        case let node as AQLStringInterpolationExpression:
            return "interpolation(parts: \(node.parts.count))"
        case let node as AQLCallExpression:
            return "call(\(optional(node.source)), \(node.methodName), arrow: \(node.usesArrow), "
                + "args: \(list(node.arguments)))"
        case let node as AQLCollectionExpression:
            return "collection(\(node.operation.rawValue), \(print(node.source)), "
                + "iterator: \(node.iterator ?? "-"), body: \(optional(node.body)))"
        case let node as AQLBinaryExpression:
            return "binary(\(node.op.rawValue), \(print(node.left)), \(print(node.right)))"
        case let node as AQLUnaryExpression:
            return "unary(\(node.op.rawValue), \(print(node.operand)))"
        case let node as AQLConditionalExpression:
            return "if(\(print(node.condition)), \(print(node.thenExpression)), "
                + "\(print(node.elseExpression)))"
        case let node as AQLLetExpression:
            let bindings = node.bindings.map { "\($0.0)=\(print($0.1))" }.joined(separator: ", ")
            return "let([\(bindings)], \(print(node.body)))"
        case let node as AQLLambdaExpression:
            return "lambda(\(node.iterators.joined(separator: ",")), \(print(node.body)))"
        case let node as AQLCollectionLiteralExpression:
            return "literalCollection(\(node.kind.rawValue), \(list(node.elements)))"
        case let node as AQLEnumLiteralExpression:
            return "enum(\(node.packageName ?? "-"), \(node.enumName), \(node.literal))"
        case let node as AQLTypeLiteralExpression:
            return "type(\(node.packageName ?? "-"), \(node.typeName))"
        default:
            return hook?(expression, self) ?? "unknown(\(type(of: expression)))"
        }
    }
}
