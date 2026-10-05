//
//  MTLParserDelegate.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL

/// The hooks through which MTL shapes the expressions that the AQL parser builds.
///
/// Calls become ``MTLInvocationExpression`` nodes (except the OCL type operations), so that
/// they resolve against the templates, queries, and macros of the module before the AQL
/// library. The `collected('set')` function of the generation facilities is a primary
/// expression.
struct MTLParserDelegate: AQLParserDelegate {

    /// Whether a token ends the expression that the AQL parser is reading.
    ///
    /// A `/` directly before `]` closes a directive such as `[expression/]` instead of dividing.
    ///
    /// - Parameters:
    ///   - token: The current token.
    ///   - next: The token after it.
    /// - Returns: `true` for a slash before a closing bracket.
    @Sendable
    static func endsExpression(_ token: AQLToken, _ next: AQLToken?) -> Bool {
        token.kind == .slash && next?.kind == .rightBracket
    }

    /// Builds the node for `receiver.name(arguments)` or `name(arguments)`.
    ///
    /// OCL type operations become plain AQL calls. Every other name becomes an invocation that
    /// is resolved against the module's templates, queries, and macros at run time before
    /// falling back to the AQL library.
    ///
    /// - Parameters:
    ///   - name: The name of the operation.
    ///   - receiver: The receiver, if any.
    ///   - arguments: The argument expressions.
    /// - Returns: The node for the call.
    mutating func makeCall(
        name: String, receiver: (any AQLExpression)?, arguments: [any AQLExpression]
    ) -> any AQLExpression {
        let call = AQLCallExpression(source: receiver, methodName: name, arguments: arguments)
        if MTLSyntax.typeOperationNames.contains(name) {
            return call
        }
        return MTLInvocationExpression(name: name, receiver: receiver, arguments: arguments, fallback: call)
    }

    /// Parses `collected('set')` when the name is the collected function.
    ///
    /// - Parameters:
    ///   - name: The text of the current identifier or keyword token.
    ///   - cursor: The cursor, positioned on the name token.
    /// - Returns: The collected expression, or `nil` (with nothing consumed) for any other
    ///   construct.
    /// - Throws: A syntax error if the argument is malformed.
    mutating func parsePrimary(named name: String, cursor: inout AQLTokenCursor) throws
        -> (any AQLExpression)?
    {
        guard name == MTLDeferredBlockNames.collectedFunction, cursor.peekKind() == .leftParen else {
            return nil
        }
        cursor.advance()  // Consume the name
        cursor.advance()  // Consume '('
        let setName = try AQLParser.parseExpression(&cursor, delegate: &self)
        try cursor.expect(.rightParen)
        return MTLCollectedExpression(setName: setName)
    }
}

extension MTLToken {

    /// The token as the AQL parser reads it.
    ///
    /// Text and directive-level tokens that AQL does not interpret become
    /// ``AQLTokenKind/other``. The position carries line and column only.
    var aqlToken: AQLToken {
        AQLToken(kind: type.aqlKind, span: AQLSourceSpan(line: line, column: column))
    }
}

extension MTLTokenType {

    /// The kind of AQL token that this token stands for.
    var aqlKind: AQLTokenKind {
        switch self {
        case .leftBracket: return .leftBracket
        case .rightBracket: return .rightBracket
        case .slash: return .slash
        case .leftParen: return .leftParen
        case .rightParen: return .rightParen
        case .comma: return .comma
        case .colon: return .colon
        case .dot: return .dot
        case .pipe: return .pipe
        case .questionMark: return .questionMark
        case .doubleColon: return .doubleColon
        case .leftBrace: return .leftBrace
        case .rightBrace: return .rightBrace
        case .keyword(let word): return .keyword(word)
        case .identifier(let name): return .identifier(name)
        case .stringLiteral(let value): return .stringLiteral(value)
        case .integerLiteral(let value): return .integerLiteral(value)
        case .realLiteral(let value): return .realLiteral(value)
        case .booleanLiteral(let value): return .booleanLiteral(value)
        case .operator(let text): return .operator(text)
        case .comment(let text): return .comment(text)
        case .eof: return .eof
        case .text, .commentDirective, .documentation, .whitespace, .newline: return .other
        }
    }
}
