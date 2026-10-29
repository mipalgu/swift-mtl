//
//  MTLUnterminatedDirectiveTests.swift
//  MTL
//
//  Created by Rene Hexel on 29/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase
import Testing

@testable import MTL

/// Tests for directives whose closing `]` is missing.
@Suite("MTL unterminated directives")
struct MTLUnterminatedDirectiveTests {

    /// A directive header without its closing bracket, followed by more text and directives.
    struct Case: Sendable, CustomTestStringConvertible {
        /// The module text after the module header.
        let body: String

        /// The keyword of the unterminated directive, if it starts with one.
        let keyword: String?

        /// The line of the `[` that opens the unterminated directive.
        let line: Int

        /// The column of the `[` that opens the unterminated directive.
        let column: Int

        /// The text the diagnostic covers.
        let covered: String

        var testDescription: String { keyword ?? "expression" }
    }

    private static let header = "[module m('u')/]\n"

    private static let cases: [Case] = [
        Case(
            body: "[template public main(x : String)\nhello world\n[x/]\n[/template]\n",
            keyword: "template", line: 2, column: 1, covered: "[template public main(x : String)"),
        Case(
            body: "[query public q(x : String) : String = x\n[template main()]a[/template]\n",
            keyword: "query", line: 2, column: 1, covered: "[query public q(x : String) : String = x"),
        Case(
            body: "[macro m(x : String)\nhello [x/]\n[/macro]\n",
            keyword: "macro", line: 2, column: 1, covered: "[macro m(x : String)"),
        Case(
            body: "[template main(x : String)]\n  [for (c : String | x)\nhello [c/]\n[/for]\n[/template]\n",
            keyword: "for", line: 3, column: 3, covered: "[for (c : String | x)"),
        Case(
            body: "[template main(x : String)]\n[if (x = 'a')\nhello [x/]\n[/if]\n[/template]\n",
            keyword: "if", line: 3, column: 1, covered: "[if (x = 'a')"),
        Case(
            body: "[template main(x : String)]\n[let y : String = x\nhello [y/]\n[/let]\n[/template]\n",
            keyword: "let", line: 3, column: 1, covered: "[let y : String = x"),
        Case(
            body: "[template main()]\n[file ('a.txt', 'overwrite')\nhello\n[/file]\n[/template]\n",
            keyword: "file", line: 3, column: 1, covered: "[file ('a.txt', 'overwrite')"),
        Case(
            body: "[template main()]\n[protected ('id')\nhello\n[/protected]\n[/template]\n",
            keyword: "protected", line: 3, column: 1, covered: "[protected ('id')"),
        Case(
            body: "[template main(x : String)]\n[x.toUpper()\n[/template]\n",
            keyword: nil, line: 3, column: 1, covered: "[x.toUpper()"),
    ]

    /// The source text that a range covers.
    private func text(_ range: SourceRange?, in source: String) -> String? {
        guard let range else { return nil }
        let bytes = Array(source.utf8)
        return String(decoding: bytes[range.start.utf8Offset..<range.end.utf8Offset], as: UTF8.self)
    }

    /// The message of the strict parse error for a source.
    private func strictMessage(_ source: String) async -> String? {
        do {
            _ = try await MTLTestSupport.parse(source)
            Issue.record("Expected a parse error")
        } catch let error as MTLParseError {
            guard case .invalidSyntax(let message) = error else {
                Issue.record("Expected an invalid syntax error")
                return nil
            }
            return message
        } catch {
            Issue.record("Expected an MTL parse error")
        }
        return nil
    }

    // MARK: Strict parsing

    @Test("The strict parser reports a missing ']' where the directive opens", arguments: cases)
    func strict(example: Case) async throws {
        let message = try #require(await strictMessage(Self.header + example.body))
        #expect(message.hasPrefix("Line \(example.line), column \(example.column): "), "\(message)")
        #expect(message.contains("expected ']'"), "\(message)")
        if let keyword = example.keyword {
            #expect(message.contains("'[\(keyword)'"), "\(message)")
        }
    }

    @Test("A missing ']' at the end of the text is reported where the directive opens")
    func strictAtEnd() async throws {
        let message = try #require(await strictMessage(Self.header + "[template main(x : String)\nhello"))
        #expect(message.hasPrefix("Line 2, column 1: "), "\(message)")
        #expect(message.contains("'[template'"), "\(message)")
    }

    @Test("A '[' on the line of an unterminated directive is reported at the directive")
    func strictSameLine() async throws {
        let message = try #require(await strictMessage(Self.header + "[template test()[if (true)]text[/if][/template]"))
        #expect(message.hasPrefix("Line 2, column 1: "), "\(message)")
    }

    // MARK: Diagnosing

    @Test("The diagnosing parser reports one problem covering the directive header", arguments: cases)
    func diagnosing(example: Case) async throws {
        let source = Self.header + example.body
        let result = await MTLParser().parseDiagnosing(source, filename: "t.mtl")
        #expect(result.diagnostics.count == 1, "\(result.diagnostics)")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.code == MTLDiagnosticCode.unterminatedDirective.rawValue)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.range?.start.line == example.line)
        #expect(diagnostic.range?.start.column == example.column)
        #expect(text(diagnostic.range, in: source) == example.covered)
        #expect(diagnostic.message.contains("expected ']'"))
        #expect(result.module != nil)
    }

    @Test("The text after an unterminated template header stays in its body")
    func diagnosingKeepsBody() async throws {
        let source = Self.header + "[template public main(x : String)\nhello world\n[x/]\n[/template]\n"
        let result = await MTLParser().parseDiagnosing(source, filename: "t.mtl")
        let template = try #require(result.module?.templates["main"])
        #expect(template.parameters.map(\.name) == ["x"])
        let texts = template.body.statements.compactMap { ($0 as? MTLTextStatement)?.value }
        #expect(texts.joined().contains("hello world"))
        #expect(template.body.statements.contains { $0 is MTLExpressionStatement })
    }

    @Test("A directive left open at the end of the text is reported where it opens")
    func diagnosingAtEnd() async throws {
        let source = Self.header + "[template main(x : String)\nhello"
        let result = await MTLParser().parseDiagnosing(source, filename: "t.mtl")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.code == MTLDiagnosticCode.unterminatedDirective.rawValue)
        #expect(diagnostic.range?.start.line == 2 && diagnostic.range?.start.column == 1)
        #expect(text(diagnostic.range, in: source) == "[template main(x : String)")
    }

    @Test("A '[' on the line of an unterminated directive starts the next directive")
    func diagnosingSameLine() async throws {
        let source = Self.header + "[template test()[if (true)]text[/if][/template]"
        let result = await MTLParser().parseDiagnosing(source, filename: "t.mtl")
        #expect(result.diagnostics.map(\.code) == [MTLDiagnosticCode.unterminatedDirective.rawValue])
        #expect(text(result.diagnostics.first?.range, in: source) == "[template test()")
        let body = try #require(result.module?.templates["test"]?.body)
        #expect(body.statements.first is MTLIfStatement)
    }

    // MARK: Highlighting

    @Test("Highlighting treats the text after an unterminated header as template text")
    func highlighting() {
        let source = "[template main(x : String)\nhello world\n[x/]\n"
        let tokens = MTLSyntax.tokens(in: source)
        let texts = tokens.filter { $0.kind == .text }.map { text($0.range, in: source) }
        #expect(texts.contains("\nhello world\n"))
        #expect(tokens.allSatisfy { $0.range.start.utf8Offset < $0.range.end.utf8Offset })
        var covered = Set<Int>()
        for token in tokens {
            for index in token.range.start.utf8Offset..<token.range.end.utf8Offset {
                #expect(covered.insert(index).inserted, "overlap at \(index)")
            }
        }
    }
}
