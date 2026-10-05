//
//  MTLParserDelegateTests.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import EMFBase
import Testing

@testable import MTL

@Suite("MTL parser delegate")
struct MTLParserDelegateTests {

    @Test("Tokens map to the AQL token with the same meaning")
    func tokenMapping() {
        let pairs: [(MTLTokenType, AQLTokenKind)] = [
            (.leftBracket, .leftBracket), (.rightBracket, .rightBracket), (.slash, .slash),
            (.leftParen, .leftParen), (.rightParen, .rightParen), (.comma, .comma),
            (.colon, .colon), (.dot, .dot), (.pipe, .pipe), (.questionMark, .questionMark),
            (.doubleColon, .doubleColon), (.leftBrace, .leftBrace), (.rightBrace, .rightBrace),
            (.keyword("if"), .keyword("if")), (.identifier("x"), .identifier("x")),
            (.stringLiteral("s"), .stringLiteral("s")), (.integerLiteral(1), .integerLiteral(1)),
            (.realLiteral(1.5), .realLiteral(1.5)), (.booleanLiteral(true), .booleanLiteral(true)),
            (.operator("+"), .operator("+")), (.comment("c"), .comment("c")), (.eof, .eof),
            (.text("t"), .other), (.commentDirective("c"), .other), (.documentation("d"), .other),
            (.whitespace, .other), (.newline, .other),
        ]
        let table = LineTable("ab\ncdef")
        let range = table.range(fromUTF8Offset: 4, to: 6)
        for (mtl, aql) in pairs {
            let token = MTLToken(type: mtl, line: 2, column: 2, offset: 4, endOffset: 6)
            #expect(token.aqlToken(using: table) == AQLToken(kind: aql, range: range))
        }
    }

    @Test("Only a slash before a closing bracket ends an expression")
    func terminator() {
        let range = SourceRange(start: .start, end: .start)
        let slash = AQLToken(kind: .slash, range: range)
        let bracket = AQLToken(kind: .rightBracket, range: range)
        let name = AQLToken(kind: .identifier("x"), range: range)
        #expect(MTLParserDelegate.endsExpression(slash, bracket))
        #expect(!MTLParserDelegate.endsExpression(slash, name))
        #expect(!MTLParserDelegate.endsExpression(slash, nil))
        #expect(!MTLParserDelegate.endsExpression(bracket, bracket))
    }

    @Test("A slash inside a directive divides")
    func divisionInsideDirective() async throws {
        let tree = try await MTLExpressionGoldenSupport.tree("8 / 2")
        #expect(tree == "binary(/, lit(int(8)), lit(int(2)))")
    }

    @Test("A syntax error in an expression names its line and column")
    func errorPosition() async {
        do {
            _ = try await MTLTestSupport.parse("[module m('u')/]\n[template main()]\n[1 + )/][/template]")
            Issue.record("Expected a parse error")
        } catch let error as MTLParseError {
            guard case .invalidSyntax(let message) = error else {
                Issue.record("Expected an invalid syntax error")
                return
            }
            #expect(message.hasPrefix("Line 3, column 6: "))
        } catch {
            Issue.record("Expected an MTL parse error")
        }
    }

    @Test("Calls other than type operations are invocations that fall back to a call")
    func invocations() async throws {
        let invocation = try #require(try await MTLExpressionGoldenSupport.parse("a.f(1)") as? MTLInvocationExpression)
        #expect(invocation.name == "f")
        #expect(invocation.fallback.methodName == "f")
        #expect(try await MTLExpressionGoldenSupport.parse("a.oclIsKindOf(T)") is AQLCallExpression)
    }
}
