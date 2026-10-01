//
//  MTLGlobalVariableTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import MTL

/// Tests for global variables visible to every template and query.
@Suite("MTL Global Variables")
struct MTLGlobalVariableTests {

    /// Runs a source with the given globals set through ``MTLGenerator/setGlobalVariable(_:value:)``.
    @MainActor
    private func output(
        _ source: String, globals: [String: String], arguments: [(any EcoreValue)?] = []
    ) async throws -> String {
        let module = try await MTLTestSupport.parse(source)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        for (name, value) in globals { generator.setGlobalVariable(name, value: value) }
        try await generator.generate(mainTemplate: "main", arguments: arguments, models: [:])
        return await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? ""
    }

    @Test("A global is visible in the main template")
    @MainActor
    func visibleInTemplate() async throws {
        let text = try await output(
            "[module m('u')/]\n[template main()]Hello [who/][/template]",
            globals: ["who": "World"])
        #expect(text == "Hello World")
    }

    @Test("A global is visible in nested templates and queries")
    @MainActor
    func visibleInNestedTemplatesAndQueries() async throws {
        let text = try await output("""
            [module m('u')/]
            [query q() : String = who + '!'/]
            [template inner()]<[who/]>[/template]
            [template main()][inner()/][q()/][for (i : Integer | Sequence{1, 2})][who/][i/][/for][/template]
            """, globals: ["who": "W"])
        #expect(text == "<W>W!W1W2")
    }

    @Test("A template parameter shadows a global inside the template only")
    @MainActor
    func parameterShadows() async throws {
        let text = try await output("""
            [module m('u')/]
            [template inner(who : String)][who/][/template]
            [template main()][inner('local')/],[who/][/template]
            """, globals: ["who": "global"])
        #expect(text == "local,global")
    }

    @Test("A let variable shadows a global inside the block only")
    @MainActor
    func letShadows() async throws {
        let text = try await output("""
            [module m('u')/]
            [template main()][let who : String = 'local'][who/][/let],[who/][/template]
            """, globals: ["who": "global"])
        #expect(text == "local,global")
    }

    @Test("A query of the same name is not hidden by a global")
    @MainActor
    func queryNotHidden() async throws {
        let text = try await output("""
            [module m('u')/]
            [query who() : String = 'query'/]
            [template main()][who()/],[who/][/template]
            """, globals: ["who": "global"])
        #expect(text == "query,global")
    }

    @Test("Setting a global again replaces its value")
    @MainActor
    func replacesValue() async throws {
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[template main()][who/][/template]")
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        generator.setGlobalVariable("who", value: "first")
        generator.setGlobalVariable("who", value: "second")
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        #expect(await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] == "second")
    }

    @Test("Globals passed to the initialiser are visible")
    @MainActor
    func initialiserGlobals() async throws {
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[template main()][a/][b/][/template]")
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(
            module: module, generationStrategy: strategy, globals: ["a": "1", "b": 2])
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        #expect(await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] == "12")
    }

    @Test("A null global is a null value")
    @MainActor
    func nullGlobal() async throws {
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[template main()][if (x.oclIsUndefined())]undefined[/if][/template]")
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        generator.setGlobalVariable("x", value: nil)
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        #expect(await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] == "undefined")
    }

    @Test("The execution context keeps a global in the outermost scope")
    @MainActor
    func contextGlobalSurvivesScopes() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/]")
        let context = MTLExecutionContext(module: module, generationStrategy: MTLInMemoryStrategy())
        context.pushScope()
        context.setVariable("x", value: "inner")
        context.setGlobalVariable("x", value: "global")
        #expect(try await context.getVariable("x") as? String == "global")
        context.popScope()
        #expect(try await context.getVariable("x") as? String == "global")
    }
}
