//
//  MTLParseDiagnosingTests.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase
import Testing

@testable import MTL

@Suite("MTL diagnosing parser")
struct MTLParseDiagnosingTests {

    private let header = "[module m('u')/]\n"

    private func diagnose(_ source: String) async -> MTLParseResult {
        await MTLParser().parseDiagnosing(source, filename: "t.mtl")
    }

    private func text(_ range: SourceRange?, in source: String) -> String? {
        guard let range else { return nil }
        let bytes = Array(source.utf8)
        return String(decoding: bytes[range.start.utf8Offset..<range.end.utf8Offset], as: UTF8.self)
    }

    private func texts(_ block: MTLBlock) -> [String] {
        block.statements.compactMap { ($0 as? MTLTextStatement)?.value }
    }

    // MARK: Valid input

    @Test("A valid module has no diagnostics and equals the strict result")
    func valid() async throws {
        let source = header + "[template main(a : String)]hello [a/][/template]\n[query q() : Integer = 1/]\n"
        let result = await diagnose(source)
        #expect(result.diagnostics.isEmpty)
        let strict = try await MTLTestSupport.parse(source)
        #expect(result.module?.templates["main"]?.body == strict.templates["main"]?.body)
        #expect(result.module?.queries["q"] != nil)
    }

    @Test("The outline lists the module, imports, templates, queries and macros")
    func outline() async throws {
        let source = header
            + "[import other::lib/]\n"
            + "[extends base/]\n"
            + "[template private main(a : String, b : Integer)][/template]\n"
            + "[template public helper()]\n[/template]\n"
            + "[query q(x : Real) : Real = x/]\n"
            + "[macro m(y : String, body : Body)]x[/macro]\n"
        let result = await diagnose(source)
        #expect(result.diagnostics.isEmpty)
        let root = try #require(result.outline.first)
        #expect(result.outline.count == 1)
        #expect(root.kind == "module" && root.name == "m")
        #expect(text(root.selectionRange, in: source) == "m")
        #expect(root.children.map(\.kind) == ["import", "extends", "template", "template", "query", "macro"])
        #expect(root.children.map(\.name) == ["other::lib", "base", "main", "helper", "q", "m"])
        #expect(root.children[2].detail == "private(a : String, b : Integer)")
        #expect(root.children[4].detail == "public(x : Real) : Real")
        #expect(root.children[5].detail == "(y : String)")
        #expect(text(root.children[0].selectionRange, in: source) == "other::lib")
        #expect(text(root.children[2].selectionRange, in: source) == "main")
        #expect(text(root.children[2].range, in: source) == "[template private main(a : String, b : Integer)][/template]")
        let identifiers = root.children.map(\.id)
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test("A main template is marked in the outline")
    func mainTemplate() async throws {
        let source = header + "[** @main **/]\n[template main()][/template]"
        let result = await diagnose(source)
        #expect(result.outline.first?.children.first?.detail == "public main()")
    }

    // MARK: Directive recovery

    @Test("A bad directive is skipped and the text around it survives")
    func badDirective() async throws {
        let source = header + "[template main()]A[1 + )/]B[/template]"
        let result = await diagnose(source)
        let diagnostic = try #require(result.diagnostics.first)
        #expect(result.diagnostics.count == 1)
        #expect(diagnostic.code == MTLDiagnosticCode.unexpectedToken.rawValue)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.document == "t.mtl")
        #expect(text(diagnostic.range, in: source) == ")")
        #expect(diagnostic.range?.start.line == 2)
        let body = try #require(result.module?.templates["main"]?.body)
        #expect(texts(body) == ["A", "B"])
    }

    @Test("A bad block header skips to the matching closing tag")
    func badBlockHeader() async throws {
        let source = header + "[template main()]A[if (]x[if (b)]y[/if]z[/if]B[/template]"
        let result = await diagnose(source)
        #expect(result.diagnostics.count == 1)
        let body = try #require(result.module?.templates["main"]?.body)
        #expect(texts(body) == ["A", "B"])
    }

    @Test("Several problems are all reported in order")
    func several() async throws {
        let source = header + "[template main()][1 + )/]x[for (]y[/for][)/][/template]"
        let result = await diagnose(source)
        #expect(result.diagnostics.count == 3)
        let offsets = result.diagnostics.compactMap { $0.range?.start.utf8Offset }
        #expect(offsets == offsets.sorted())
        #expect(result.module?.templates["main"] != nil)
    }

    @Test("Problems in nested blocks keep the enclosing block")
    func nested() async throws {
        let source = header + "[template main()][if (a)]A[1 + )/]B[/if]C[/template]"
        let result = await diagnose(source)
        #expect(result.diagnostics.count == 1)
        let body = try #require(result.module?.templates["main"]?.body)
        let conditional = try #require(body.statements.first as? MTLIfStatement)
        #expect(texts(conditional.thenBlock) == ["A", "B"])
        #expect(texts(body) == ["C"])
    }

    // MARK: Declaration recovery

    @Test("A broken template header skips to its closing tag")
    func brokenTemplateHeader() async throws {
        let source = header + "[template bad(]x[/template]\n[template good()]ok[/template]"
        let result = await diagnose(source)
        #expect(result.diagnostics.count == 1)
        #expect(result.module?.templates["bad"] == nil)
        #expect(result.module?.templates["good"] != nil)
        #expect(result.outline.first?.children.map(\.name) == ["good"])
    }

    @Test("A broken query skips to the end of its directive")
    func brokenQuery() async throws {
        let source = header + "[query q( : Integer = 1/]\n[query ok() : Integer = 2/]"
        let result = await diagnose(source)
        #expect(result.diagnostics.count == 1)
        #expect(result.module?.queries["ok"] != nil)
        #expect(result.module?.queries["q"] == nil)
    }

    @Test("A broken macro skips to its closing tag")
    func brokenMacro() async throws {
        let source = header + "[macro bad(]x[/macro]\n[macro good()]y[/macro]"
        let result = await diagnose(source)
        #expect(result.diagnostics.count == 1)
        #expect(result.module?.macros["good"] != nil)
    }

    @Test("A duplicate template is reported at its name and kept in the outline")
    func duplicates() async throws {
        let source = header + "[template t()]a[/template]\n[template t()]b[/template]\n[query q() : Integer = 1/][query q() : Integer = 2/]"
        let result = await diagnose(source)
        #expect(result.diagnostics.map(\.code) == Array(repeating: MTLDiagnosticCode.duplicateDeclaration.rawValue, count: 2))
        #expect(text(result.diagnostics[0].range, in: source) == "t")
        #expect(result.outline.first?.children.count == 4)
        let identifiers = try #require(result.outline.first?.children.map(\.id))
        #expect(Set(identifiers).count == 4)
        #expect(texts(try #require(result.module?.templates["t"]?.body)) == ["a"])
    }

    @Test("An unterminated template keeps what was parsed")
    func unterminatedTemplate() async throws {
        let source = header + "[template main()]hello"
        let result = await diagnose(source)
        #expect(!result.diagnostics.isEmpty)
        #expect(result.diagnostics.allSatisfy { $0.code == MTLDiagnosticCode.unexpectedEnd.rawValue })
        #expect(result.diagnostics.count == 1)
        #expect(texts(try #require(result.module?.templates["main"]?.body)) == ["hello"])
    }

    @Test("An unterminated block reports the end of the text once")
    func unterminatedBlock() async throws {
        let source = header + "[template main()][if (a)][for (b)]x"
        let result = await diagnose(source)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics.first?.code == MTLDiagnosticCode.unexpectedEnd.rawValue)
        #expect(result.module?.templates["main"] != nil)
    }

    @Test("A malformed module header yields no module but keeps the outline")
    func malformedHeader() async throws {
        let source = "[module ('u')/]\n[template main()]x[/template]"
        let result = await diagnose(source)
        #expect(result.module == nil)
        #expect(result.diagnostics.count == 1)
        #expect(result.outline.map(\.name) == ["main"])
    }

    @Test("Text without a module header is reported")
    func noHeader() async {
        let result = await diagnose("just text")
        #expect(result.module == nil)
        #expect(result.diagnostics.count == 1)
    }

    @Test("An unexpected directive at module level is skipped")
    func moduleLevel() async throws {
        let source = header + "[bogus/]\n[template main()]x[/template]"
        let result = await diagnose(source)
        #expect(result.diagnostics.count == 1)
        #expect(result.module?.templates["main"] != nil)
    }

    // MARK: Lexical problems

    @Test("An unterminated string is reported and parsing continues")
    func unterminatedString() async throws {
        let source = header + "[template main()]A[x 'oops\n]B[y/]C[/template]"
        let result = await diagnose(source)
        let codes = result.diagnostics.map(\.code)
        #expect(codes.contains(MTLDiagnosticCode.unterminatedString.rawValue))
        #expect(result.module?.templates["main"] != nil)
    }

    @Test("A malformed escape, a bad number and a stray character are reported")
    func lexicalCodes() async {
        let escape = await diagnose(header + "[template main()][x('\\u12')/][/template]")
        #expect(escape.diagnostics.map(\.code) == [MTLDiagnosticCode.malformedEscape.rawValue])
        let number = await diagnose(header + "[template main()][99999999999999999999/][/template]")
        #expect(number.diagnostics.map(\.code) == [MTLDiagnosticCode.invalidNumber.rawValue])
        let character = await diagnose(header + "[template main()][a # b/][/template]")
        #expect(character.diagnostics.map(\.code) == [MTLDiagnosticCode.invalidCharacter.rawValue])
        #expect(character.module?.templates["main"] != nil)
    }

    @Test("Unterminated comments are reported")
    func comments() async {
        for source in ["[** doc", "[comment text", "[comment]text"] {
            let result = await diagnose(header + source)
            #expect(result.diagnostics.map(\.code) == [MTLDiagnosticCode.unterminatedComment.rawValue], "\(source)")
        }
    }

    @Test("Multi-line strings that terminate are not problems")
    func multilineString() async {
        let result = await diagnose(header + "[template main()][('a\nb')/][/template]")
        #expect(result.diagnostics.isEmpty)
    }

    // MARK: Consistency

    @Test("Everything the strict parser accepts is accepted without diagnostics")
    func agreesWithStrict() async throws {
        let sources = [
            header + "[template main()][for (i : Integer | Sequence{1, 2})][i/][/for][/template]",
            header + "[template main(x : String)][let y = x + 'a'][y/][/let][if (x = 'b')]t[else]f[/if][/template]",
            header + "[macro m(body : Body)][body/][/macro]\n[template main()][m()]x[/m][/template]",
            header + "[template main()][file ('a.txt')]x[/file][protected ('id')]y[/protected][/template]",
        ]
        for source in sources {
            _ = try await MTLTestSupport.parse(source)
            let result = await diagnose(source)
            #expect(result.diagnostics.isEmpty, "\(source)")
        }
    }

    @Test("The strict parser still fails where the diagnosing one recovers")
    func strictStillThrows() async {
        let source = header + "[template main()]A[1 + )/]B[/template]"
        await #expect(throws: MTLParseError.self) { try await MTLTestSupport.parse(source) }
    }

    @Test("Garbled input never hangs and always yields positions inside the text")
    func garbage() async {
        let pieces = ["[", "]", "/", "[template", "[/template]", "(", ")", "'", "x", "[if", "[/if]", " ", "\n", "[**", "[comment", "-", "->", "#", "[for (", "[macro", "[query"]
        var seed: UInt64 = 42
        func next() -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed >> 33)
        }
        for _ in 0..<300 {
            var source = next() % 3 == 0 ? header : ""
            for _ in 0..<(next() % 24) { source += pieces[next() % pieces.count] }
            let result = await diagnose(source)
            for diagnostic in result.diagnostics {
                let range = diagnostic.range
                #expect(range != nil)
                #expect((range?.end.utf8Offset ?? 0) <= source.utf8.count, "\(source.debugDescription)")
            }
            _ = MTLSyntax.tokens(in: source)
        }
    }
}
