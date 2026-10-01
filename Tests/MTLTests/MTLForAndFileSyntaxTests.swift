//
//  MTLForAndFileSyntaxTests.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Testing

@testable import MTL

@Suite("MTL For and File Syntax")
struct MTLForAndFileSyntaxTests {

    /// Wraps a template body in a module with a main template.
    private static func module(_ body: String, header: String = "") -> String {
        "[module m('u')/]\n[template main()\(header)]\(body)[/template]"
    }

    // MARK: - For

    @Test("The pipe form binds the iterator like the in form")
    func forWithPipe() async throws {
        let parsed = try await MTLTestSupport.parse(Self.module(
            "[for (x : OclAny | Sequence{'a'})][x/][/for]"))
        let loop = try #require(parsed.templates["main"]?.body.statements.first as? MTLForStatement)
        #expect(loop.binding.variable.name == "x")
        #expect(loop.binding.variable.type == "OclAny")
    }

    @Test("The pipe form works without a type")
    @MainActor
    func forPipeWithoutType() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[for (x | Sequence{'a', 'b'})][x/][/for]"))
        #expect(output == "ab")
    }

    @Test("The in form still works")
    @MainActor
    func forInForm() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[for (x : OclAny in Sequence{'a', 'b'})][x/][/for]"))
        #expect(output == "ab")
    }

    @Test("Separator, before and after wrap non-empty iterations")
    @MainActor
    func forBeforeAfterSeparator() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[for (x | Sequence{'a', 'b', 'c'}) separator(', ') before('(') after(')')][x/][/for]"))
        #expect(output == "(a, b, c)")
    }

    @Test("The clauses may come in any order")
    @MainActor
    func forClausesInAnyOrder() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[for (x | Sequence{'a', 'b'}) after(']') before('[') separator('|')][x/][/for]"))
        #expect(output == "[a|b]")
    }

    @Test("Before and after are omitted for an empty collection")
    @MainActor
    func forEmptyCollection() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "x[for (e | Sequence{}) before('(') after(')')][e/][/for]y"))
        #expect(output == "xy")
    }

    @Test("The implicit counter starts at one")
    @MainActor
    func forCounter() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[for (x | Sequence{'a', 'b', 'c'}) separator(',')][i/]:[x/][/for]"))
        #expect(output == "1:a,2:b,3:c")
    }

    @Test("Nested loops have their own counter")
    @MainActor
    func nestedCounters() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[for (x | Sequence{'a', 'b'}) separator(';')][for (y | Sequence{'p', 'q'}) separator(',')][i/][x/][y/][/for][/for]"))
        #expect(output == "1ap,2aq;1bp,2bq")
    }

    @Test("The counter is restored after an inner loop")
    @MainActor
    func counterRestored() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[for (x | Sequence{'a', 'b'}) separator(';')][for (y | Sequence{'p'})][/for][i/][/for]"))
        #expect(output == "1;2")
    }

    @Test("A loop without a binding iterates over self")
    @MainActor
    func forImplicitIterator() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[for (Sequence{'a', 'b'})][self/][/for]"))
        #expect(output == "ab")
    }

    @Test("A missing 'in' or pipe is a syntax error")
    func forMissingSeparator() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse(Self.module("[for (x : OclAny Sequence{})]a[/for]"))
        }
    }

    @Test("The for loop type may be qualified")
    func forQualifiedType() async throws {
        let parsed = try await MTLTestSupport.parse(Self.module(
            "[for (c : ecore::EClass | Sequence{})]a[/for]"))
        let loop = try #require(parsed.templates["main"]?.body.statements.first as? MTLForStatement)
        #expect(loop.binding.variable.type == "ecore::EClass")
    }

    // MARK: - File

    @Test("Boolean modes select overwrite and append")
    func booleanModes() async throws {
        let module = try await MTLTestSupport.parse(Self.module("""
            [file ('a.txt', false)]x[/file][file ('b.txt', true)]y[/file]
            """))
        let files = module.templates["main"]!.body.statements.compactMap { $0 as? MTLFileStatement }
        #expect(files.map(\.mode) == [.overwrite, .append])
        #expect(files.allSatisfy { $0.modeExpression == nil })
    }

    @Test("String modes select overwrite, append and create")
    func stringModes() async throws {
        let module = try await MTLTestSupport.parse(Self.module("""
            [file ('a', 'overwrite')]x[/file][file ('b', 'append')]y[/file][file ('c', 'create')]z[/file]
            """))
        let files = module.templates["main"]!.body.statements.compactMap { $0 as? MTLFileStatement }
        #expect(files.map(\.mode) == [.overwrite, .append, .create])
    }

    @Test("Bare mode keywords are accepted")
    func keywordModes() async throws {
        let module = try await MTLTestSupport.parse(Self.module("""
            [file ('a', overwrite)]x[/file][file ('b', append)]y[/file][file ('c', create, 'UTF-8')]z[/file]
            """))
        let files = module.templates["main"]!.body.statements.compactMap { $0 as? MTLFileStatement }
        #expect(files.map(\.mode) == [.overwrite, .append, .create])
    }

    @Test("The file mode defaults to overwrite")
    func defaultMode() async throws {
        let module = try await MTLTestSupport.parse(Self.module("[file ('a')]x[/file]"))
        let file = try #require(module.templates["main"]?.body.statements.first as? MTLFileStatement)
        #expect(file.mode == .overwrite)
    }

    @Test("An unknown string mode is a syntax error")
    func invalidMode() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse(Self.module("[file ('a', 'clobber')]x[/file]"))
        }
    }

    @Test("The charset is recorded")
    func charsetRecorded() async throws {
        let module = try await MTLTestSupport.parse(Self.module("[file ('a', false, 'ISO-8859-1')]x[/file]"))
        let file = try #require(module.templates["main"]?.body.statements.first as? MTLFileStatement)
        #expect(file.charset != nil)
    }

    @Test("Append mode adds to the file written before")
    @MainActor
    func appendGeneration() async throws {
        let files = try await MTLTestSupport.run(Self.module("""
            [file ('log.txt', false)]first;[/file][file ('log.txt', true)]second;[/file]
            """))
        #expect(files["log.txt"] == "first;second;")
    }

    @Test("Overwrite mode replaces the file written before")
    @MainActor
    func overwriteGeneration() async throws {
        let files = try await MTLTestSupport.run(Self.module("""
            [file ('log.txt', 'overwrite')]first;[/file][file ('log.txt', 'overwrite')]second;[/file]
            """))
        #expect(files["log.txt"] == "second;")
    }

    @Test("Create mode fails if the file exists")
    @MainActor
    func createGeneration() async {
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.run(Self.module("""
                [file ('log.txt', false)]first;[/file][file ('log.txt', 'create')]second;[/file]
                """))
        }
    }

    @Test("A computed mode is evaluated when the file is opened")
    @MainActor
    func computedMode() async throws {
        let files = try await MTLTestSupport.run(Self.module("""
            [file ('log.txt', false)]first;[/file][file ('log.txt', 1 > 0)]second;[/file]
            """))
        #expect(files["log.txt"] == "first;second;")
    }

    @Test("A computed mode of the wrong type is an error")
    @MainActor
    func computedModeWrongType() async {
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.run(Self.module("[file ('log.txt', 1 + 1)]x[/file]"))
        }
    }
}
