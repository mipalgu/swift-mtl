//
//  MTLSourcePositionTests.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import EMFBase
import Testing

@testable import MTL

@Suite("MTL source positions")
struct MTLSourcePositionTests {

    private let header = "[module m('u')/]\n"

    /// The source text that a range covers.
    private func text(_ range: SourceRange?, in source: String) -> String? {
        guard let range else { return nil }
        let bytes = Array(source.utf8)
        return String(decoding: bytes[range.start.utf8Offset..<range.end.utf8Offset], as: UTF8.self)
    }

    private func tokens(_ source: String) throws -> [MTLToken] {
        try MTLLexer(source).tokenize()
    }

    @Test("Text tokens start where their text starts, even over several lines")
    func multiLineText() throws {
        let source = "one\ntwo\n[x/] three\nfour"
        let result = try tokens(source)
        let first = result[0]
        #expect(first.type == .text("one\ntwo\n"))
        #expect(first.line == 1 && first.column == 1 && first.offset == 0 && first.endOffset == 8)
        let trailing = try #require(result.last { $0.type == .text(" three\nfour") })
        #expect(trailing.line == 3 && trailing.column == 5)
        #expect(trailing.offset == 12 && trailing.endOffset == source.utf8.count)
    }

    @Test("Offsets count UTF-8 bytes while columns count characters")
    func multibyte() throws {
        let source = "é😀[x/]"
        let result = try tokens(source)
        #expect(result[0].offset == 0 && result[0].endOffset == 6)
        #expect(result[1].type == .leftBracket)
        #expect(result[1].offset == 6 && result[1].column == 3)
        #expect(result[2].type == .identifier("x") && result[2].offset == 7 && result[2].endOffset == 8)
    }

    @Test("Every directive token knows where it ends")
    func ends() throws {
        let source = "[a -> b <> 'str' 1.5 -- note\n]"
        let spans = try tokens(source).dropLast().map { text(SourceRange(
            start: SourcePosition(utf8Offset: $0.offset, line: $0.line, column: $0.column),
            end: SourcePosition(utf8Offset: $0.endOffset, line: $0.line, column: $0.column)), in: source) ?? "" }
        #expect(spans == ["[", "a", "->", "b", "<>", "'str'", "1.5", "-- note", "]"])
    }

    @Test("A line break of any style starts a new line")
    func lineBreaks() throws {
        let source = "a\r\n[x/]"
        let result = try tokens(source)
        let bracket = try #require(result.first { $0.type == .leftBracket })
        #expect(bracket.line == 2 && bracket.column == 1 && bracket.offset == 3)
    }

    @Test("Comment directives and documentation keep their offsets")
    func comments() throws {
        let source = "x[comment hello /]y[** doc **/]z"
        let result = try tokens(source)
        let comment = try #require(result.first { $0.type == .commentDirective("hello") })
        #expect(comment.offset == 1 && comment.endOffset == 18)
        let documentation = try #require(result.first { $0.type == .documentation(" doc ") })
        #expect(documentation.offset == 19 && documentation.endOffset == 31)
    }

    @Test("The end of file token sits at the end of the text")
    func endToken() throws {
        let source = "ab\ncd"
        let end = try #require(try tokens(source).last)
        #expect(end.type == .eof && end.offset == 5 && end.endOffset == 5 && end.line == 2 && end.column == 3)
    }

    @Test("Tokens reach the AQL parser with real offsets")
    func aqlTokens() throws {
        let source = "[a + b/]"
        let table = LineTable(source)
        let converted = try tokens(source).map { $0.aqlToken(using: table) }
        #expect(converted[2].range.start.utf8Offset == 3)
        #expect(converted[2].range.end.utf8Offset == 4)
    }

    // MARK: Origins

    @Test("Modules, templates, queries and macros know their source range")
    func declarationOrigins() async throws {
        let source = header
            + "[query q(a : String) : String = a/]\n"
            + "[macro m()]x[/macro]\n"
            + "[template public main(p : String)]hi[/template]\n"
        let module = try await MTLTestSupport.parse(source)
        let moduleText = try #require(text(module.origin.range, in: source))
        #expect(moduleText.hasPrefix("[module m('u')/]") && moduleText.hasSuffix("[/template]\n"))
        let query = try #require(module.queries["q"])
        #expect(text(query.origin.range, in: source) == "[query q(a : String) : String = a/]")
        let macro = try #require(module.macros["m"])
        #expect(text(macro.origin.range, in: source) == "[macro m()]x[/macro]")
        let template = try #require(module.templates["main"])
        #expect(text(template.origin.range, in: source) == "[template public main(p : String)]hi[/template]")
    }

    @Test("Statements know their source range")
    func statementOrigins() async throws {
        let source = header + "[template main()]a[b/][if (c)]d[/if][for (e in f)]g[/for][let x = 1]h[/let][/template]"
        let module = try await MTLTestSupport.parse(source)
        let statements = try #require(module.templates["main"]).body.statements
        let texts = statements.map { text($0.origin.range, in: source) }
        #expect(texts == ["a", "[b/]", "[if (c)]d[/if]", "[for (e in f)]g[/for]", "[let x = 1]h[/let]"])
    }

    @Test("Expressions inside statements know their source range")
    func expressionOrigins() async throws {
        let source = header + "[template main()][a.b + f(1)/][/template]"
        let module = try await MTLTestSupport.parse(source)
        let statement = try #require(module.templates["main"]?.body.statements.first as? MTLExpressionStatement)
        #expect(text(statement.expression.aqlExpression.origin.range, in: source) == "a.b + f(1)")
        let binary = try #require(statement.expression.aqlExpression as? AQLBinaryExpression)
        #expect(text(binary.right.origin.range, in: source) == "f(1)")
        #expect(binary.right is MTLInvocationExpression)
    }

    @Test("Origins do not affect equality of parsed modules")
    func equality() async throws {
        let first = try await MTLTestSupport.parse(header + "[template main()]x[/template]")
        let second = try await MTLTestSupport.parse("\n\n" + header + "\n[template main()]x[/template]")
        #expect(first.templates["main"]?.body == second.templates["main"]?.body)
    }

    @Test("Strict parse errors keep their line and column format")
    func strictMessage() async {
        do {
            _ = try await MTLTestSupport.parse(header + "text\nmore\n[template main()][1 + )/][/template]")
            Issue.record("Expected a parse error")
        } catch let error as MTLParseError {
            guard case .invalidSyntax(let message) = error else {
                Issue.record("Unexpected error")
                return
            }
            #expect(message.hasPrefix("Line 4, column "))
        } catch {
            Issue.record("Expected an MTL parse error")
        }
    }

    // MARK: Highlighting

    @Test("Highlighting covers template text, directives and expressions")
    func highlighting() {
        let source = "text [if (a = 'x')]\n[b.c(1, true) -- no\n/]\n[/if]"
        let kinds = MTLSyntax.tokens(in: source).map(\.kind)
        #expect(kinds.first == .text)
        #expect(kinds.contains(.directive))
        #expect(kinds.contains(.keyword))
        #expect(kinds.contains(.identifier))
        #expect(kinds.contains(.string))
        #expect(kinds.contains(.number))
        #expect(kinds.contains(.boolean))
        #expect(kinds.contains(.operator))
        #expect(kinds.contains(.punctuation))
        #expect(kinds.contains(.comment))
    }

    @Test("Highlighting covers every non-blank byte exactly once")
    func coverage() {
        let sources = [
            "a [x/] b\n[if (c)]\n  [d.e('s')/]\n[/if]",
            "[module m('u')/]\n[template t()][** doc **/][comment c /][/template]",
            "x [1 + # + 'oops\n] y",
        ]
        for source in sources {
            let tokens = MTLSyntax.tokens(in: source)
            let bytes = Array(source.utf8)
            var covered = Array(repeating: false, count: bytes.count)
            for token in tokens {
                for index in token.range.start.utf8Offset..<token.range.end.utf8Offset {
                    #expect(!covered[index], "overlap at \(index) in \(source)")
                    covered[index] = true
                }
            }
            // Blanks inside directives belong to no token; text keeps its blanks.
            let directiveText = Set(tokens.filter { $0.kind == .text }.flatMap {
                Array($0.range.start.utf8Offset..<$0.range.end.utf8Offset)
            })
            for (index, byte) in bytes.enumerated() where !Set(" \n".utf8).contains(byte) || directiveText.contains(index) {
                #expect(covered[index], "byte \(index) is not covered in \(source)")
            }
        }
    }

    @Test("Highlighting reports invalid text and never fails")
    func invalid() {
        #expect(MTLSyntax.tokens(in: "[#]").map(\.kind) == [.directive, .invalid, .directive])
        for source in ["", "[", "]", "[**", "[comment", "[x 'abc", "[\\u12]", "[99999999999999999999/]"] {
            _ = MTLSyntax.tokens(in: source)
        }
        #expect(MTLSyntax.tokens(in: "").isEmpty)
    }

    @Test("Token ranges carry lines and columns")
    func ranges() {
        let tokens = MTLSyntax.tokens(in: "ab\n[x/]")
        let bracket = tokens[1]
        #expect(bracket.range.start.line == 2 && bracket.range.start.column == 1)
    }
}
