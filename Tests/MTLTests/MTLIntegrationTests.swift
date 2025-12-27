//
//  MTLIntegrationTests.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Testing
@testable import MTL
import AQL

/// Integration tests that validate end-to-end MTL generation.
@Suite("MTL Integration Tests")
struct MTLIntegrationTests {

    @Test("Complete code generation workflow")
    @MainActor
    func testCompleteGeneration() async throws {
        // Create a simple class generator template
        let template = MTLTemplate(
            name: "generateClass",
            visibility: .public,
            parameters: [
                MTLVariable(name: "className", type: "String")
            ],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "public class "),
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLVariableExpression(name: "className")
                    )
                ),
                MTLTextStatement(value: " {"),
                MTLNewLineStatement(),
                MTLTextStatement(value: "}"),
                MTLNewLineStatement()
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: "Generates a simple class declaration"
        )

        let module = MTLModule(
            name: "ClassGenerator",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["generateClass": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "generateClass",
            arguments: ["MyClass"],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        #expect(files["stdout"]?.contains("public class MyClass") == true)
        #expect(generator.statistics.successful == true)
        #expect(generator.statistics.templatesExecuted == 1)
    }

    @Test("Text and expression statements")
    @MainActor
    func testBasicStatements() async throws {
        let template = MTLTemplate(
            name: "test",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "Hello, "),
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLLiteralExpression(value: "World")
                    )
                ),
                MTLTextStatement(value: "!")
            ], inlined: true),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "Test",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["test": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "test",
            arguments: [],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        #expect(files["stdout"] == "Hello, World!")
    }

    @Test("Module structure validation")
    func testModuleStructure() {
        let template = MTLTemplate(
            name: "template1",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [], inlined: false),
            isMain: false,
            overrides: nil,
            documentation: nil
        )

        let query = MTLQuery(
            name: "query1",
            visibility: .public,
            parameters: [],
            returnType: "String",
            body: MTLExpression(AQLLiteralExpression(value: "result")),
            documentation: nil
        )

        let macro = MTLMacro(
            name: "macro1",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [], inlined: false),
            documentation: nil
        )

        let module = MTLModule(
            name: "CompleteModule",
            metamodels: [:],
            extends: nil,
            imports: ["OtherModule"],
            templates: ["template1": template],
            queries: ["query1": query],
            macros: ["macro1": macro],
            encoding: "UTF-8"
        )

        #expect(module.name == "CompleteModule")
        #expect(module.templates.count == 1)
        #expect(module.queries.count == 1)
        #expect(module.macros.count == 1)
        #expect(module.imports.contains("OtherModule"))
    }

    @Test("Indentation management")
    func testIndentation() {
        let indent = MTLIndentation()
        #expect(indent.level == 0)
        #expect(indent.asString == "")

        let incremented = indent.increment()
        #expect(incremented.level == 1)
        #expect(incremented.asString == "    ")

        let twice = incremented.increment()
        #expect(twice.level == 2)
        #expect(twice.asString == "        ")

        let decreased = twice.decrement()
        #expect(decreased.level == 1)
    }

    @Test("Statistics tracking")
    @MainActor
    func testStatistics() async throws {
        let template = MTLTemplate(
            name: "stats",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "Test")
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "Stats",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["stats": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "stats",
            arguments: [],
            models: [:]
        )

        let stats = generator.statistics
        #expect(stats.successful == true)
        #expect(stats.templatesExecuted == 1)
        #expect(stats.executionTime > 0)
        #expect(stats.linesGenerated >= 0)
    }
}
