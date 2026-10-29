//
//  MTLTypedLetTests.swift
//  MTL
//
//  Created by Rene Hexel on 29/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Testing

@testable import MTL

/// Tests for `let` blocks whose variables declare a type.
@Suite("MTL Typed Let")
struct MTLTypedLetTests {

    /// Wraps a template body in a module with a main template.
    private static func module(_ body: String) -> String {
        "[module m('u')/]\n[template main()]\(body)[/template]"
    }

    /// Parses a template body and returns its first statement as a let block.
    private static func letBlock(_ body: String) async throws -> MTLLetStatement {
        let parsed = try await MTLTestSupport.parse(module(body))
        return try #require(parsed.templates["main"]?.body.statements.first as? MTLLetStatement)
    }

    // MARK: - Parsing

    @Test(
        "A let variable keeps its declared type",
        arguments: [
            "String", "Integer", "Sequence(String)", "OrderedSet(ecore::EClass)",
            "ecore::EClass", "Set(Sequence(Integer))", "OclAny"
        ])
    func declaredType(type: String) async throws {
        let block = try await Self.letBlock("[let x : \(type) = null]x[/let]")
        #expect(block.variables.map(\.variable.name) == ["x"])
        #expect(block.variables.map(\.variable.type) == [type])
    }

    @Test("A let variable without a type accepts any value")
    func untyped() async throws {
        let block = try await Self.letBlock("[let x = 1]x[/let]")
        #expect(block.variables.first?.variable.type == MTLSyntax.anyType)
    }

    @Test("Several typed and untyped bindings are separated by commas")
    func severalBindings() async throws {
        let block = try await Self.letBlock(
            "[let a : Sequence(String) = Sequence{'x'}, b = 2, c : ecore::EClass = null]x[/let]")
        #expect(block.variables.map(\.variable.name) == ["a", "b", "c"])
        #expect(block.variables.map(\.variable.type) == ["Sequence(String)", MTLSyntax.anyType, "ecore::EClass"])
    }

    @Test("A typed let parses without diagnostics when recovering")
    func diagnosing() async {
        let result = await MTLParser().parseDiagnosing(
            Self.module("[let names : Sequence(String) = Sequence{'a'}][names/][/let]"), filename: "t.mtl")
        #expect(result.diagnostics.isEmpty)
    }

    @Test("A malformed type in a let is a parse error")
    func malformedType() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse(Self.module("[let x : Sequence( = 1]x[/let]"))
        }
    }

    // MARK: - Generation

    @Test("A typed let binds a collection for its body")
    @MainActor
    func generatesCollection() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[let names : Sequence(String) = Sequence{'a', 'b'}][for (n : String | names) separator(', ')][n/][/for][/let]"))
        #expect(output == "a, b")
    }

    @Test("Typed bindings may refer to earlier ones")
    @MainActor
    func generatesSeveral() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[let n : Integer = 2, r : Real = n, s : String = 'v' + n.toString()][n/] [r/] [s/][/let]"))
        #expect(output == "2 2 v2")
    }

    @Test("A null value conforms to every declared type")
    @MainActor
    func nullConforms() async throws {
        let output = try await MTLTestSupport.output(Self.module(
            "[let s : String = null][if (s = null)]none[/if][/let]"))
        #expect(output == "none")
    }

    // MARK: - Mismatches

    @Test(
        "A value that does not conform to the declared type is a type error",
        arguments: [
            ("Integer", "'text'"),
            ("String", "42"),
            ("Sequence(String)", "'text'"),
            ("Boolean", "Sequence{true}")
        ])
    @MainActor
    func mismatch(type: String, value: String) async {
        do {
            _ = try await MTLTestSupport.output(Self.module("[let x : \(type) = \(value)][x/][/let]"))
            Issue.record("Expected a type error for \(type) = \(value)")
        } catch let error as MTLExecutionError {
            guard case .typeError(let message) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(message.contains("'x'"))
            #expect(message.contains(type))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test("A mismatch produces no output from the let body")
    @MainActor
    func mismatchStopsBody() async throws {
        let module = try await MTLTestSupport.parse(Self.module("before[let x : Integer = 'a']inside[/let]"))
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        await #expect(throws: MTLExecutionError.self) {
            try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        }
        let text = await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? ""
        #expect(!text.contains("inside"))
    }

    // MARK: - Element Types

    @Test(
        "A collection conforms to a collection type whose element type all its elements conform to",
        arguments: [
            ("Sequence(Real)", "Sequence{1, 2.5}", "2"),
            ("OrderedSet(ecore::EString)", "OrderedSet{'a', 'b'}", "2"),
            ("Sequence(Sequence(Integer))", "Sequence{Sequence{1}, Sequence{2, 3}}", "2"),
            ("Sequence(Boolean)", "Sequence{}", "0"),
            ("Sequence(OclAny)", "Sequence{1, 'a', true}", "3"),
            ("Collection", "Sequence{1, 'a', true}", "3")
        ])
    @MainActor
    func elementTypesConform(type: String, value: String, size: String) async throws {
        let output = try await MTLTestSupport.output(Self.module("[let x : \(type) = \(value)][x->size()/][/let]"))
        #expect(output == size)
    }

    @Test(
        "A collection with an element that does not conform to the element type is a type error",
        arguments: [
            ("Sequence(String)", "Sequence{1}"),
            ("Sequence(Integer)", "Sequence{1, 'a'}"),
            ("OrderedSet(Integer)", "Sequence{1.5}"),
            ("Sequence(Sequence(String))", "Sequence{Sequence{'a'}, Sequence{1}}"),
            ("Sequence(Sequence(String))", "Sequence{'a'}")
        ])
    @MainActor
    func elementTypeMismatch(type: String, value: String) async {
        do {
            _ = try await MTLTestSupport.output(Self.module("[let x : \(type) = \(value)][x/][/let]"))
            Issue.record("Expected a type error for \(type) = \(value)")
        } catch let error as MTLExecutionError {
            guard case .typeError(let message) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(message.contains("'x'"))
            #expect(message.contains(type))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }
}
