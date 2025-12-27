//
//  MTLGeneratorTests.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing
@testable import MTL
import AQL

@Suite("MTL Generator Tests")
struct MTLGeneratorTests {

    // MARK: - Helper to Create In-Memory Strategy

    @MainActor
    func createInMemoryStrategy() -> MTLInMemoryStrategy {
        return MTLInMemoryStrategy()
    }

    // MARK: - Basic Text Generation

    @Test("Simple text generation")
    @MainActor
    func testSimpleTextGeneration() async throws {
        // Create simple module with template that outputs text
        let template = MTLTemplate(
            name: "hello",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "Hello, World!")
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "HelloWorld",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["hello": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        // Generate with in-memory strategy
        let strategy = createInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "hello",
            arguments: [],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        let output = files["stdout"] ?? ""
        #expect(output == "Hello, World!")
    }

    @Test("Text generation with newlines")
    @MainActor
    func testTextWithNewlines() async throws {
        let template = MTLTemplate(
            name: "lines",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "Line 1"),
                MTLNewLineStatement(indentationNeeded: true),
                MTLTextStatement(value: "Line 2"),
                MTLNewLineStatement(indentationNeeded: true),
                MTLTextStatement(value: "Line 3")
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "Lines",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["lines": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = createInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "lines",
            arguments: [],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        let output = files["stdout"] ?? ""
        #expect(output == "Line 1\nLine 2\nLine 3")
    }

    // MARK: - Expression Statements

    @Test("Expression statement with literal")
    @MainActor
    func testExpressionStatement() async throws {
        let template = MTLTemplate(
            name: "expr",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLLiteralExpression(value: 42)
                    )
                )
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "Expression",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["expr": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = createInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "expr",
            arguments: [],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        let output = files["stdout"] ?? ""
        #expect(output == "42")
    }

    @Test("Expression statement with string concatenation")
    @MainActor
    func testStringConcatenation() async throws {
        let template = MTLTemplate(
            name: "concat",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLBinaryExpression(
                            left: AQLLiteralExpression(value: "Hello"),
                            op: .add,
                            right: AQLBinaryExpression(
                                left: AQLLiteralExpression(value: ", "),
                                op: .add,
                                right: AQLLiteralExpression(value: "World!")
                            )
                        )
                    )
                )
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "Concat",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["concat": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = createInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "concat",
            arguments: [],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        let output = files["stdout"] ?? ""
        #expect(output == "Hello, World!")
    }

    // MARK: - Conditional Statements

    @Test("If statement - true condition")
    @MainActor
    func testIfStatementTrue() async throws {
        let template = MTLTemplate(
            name: "iftest",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLIfStatement(
                    condition: MTLExpression(AQLLiteralExpression(value: true)),
                    thenBlock: MTLBlock(statements: [
                        MTLTextStatement(value: "Condition was true")
                    ], inlined: false),
                    elseIfBlocks: [],
                    elseBlock: nil
                )
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "IfTest",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["iftest": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = createInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "iftest",
            arguments: [],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        let output = files["stdout"] ?? ""
        #expect(output == "Condition was true")
    }

    @Test("If statement - false condition with else")
    @MainActor
    func testIfStatementFalse() async throws {
        let template = MTLTemplate(
            name: "iftest",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLIfStatement(
                    condition: MTLExpression(AQLLiteralExpression(value: false)),
                    thenBlock: MTLBlock(statements: [
                        MTLTextStatement(value: "Then branch")
                    ], inlined: false),
                    elseIfBlocks: [],
                    elseBlock: MTLBlock(statements: [
                        MTLTextStatement(value: "Else branch")
                    ], inlined: false)
                )
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "IfTest",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["iftest": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = createInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "iftest",
            arguments: [],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        let output = files["stdout"] ?? ""
        #expect(output == "Else branch")
    }

    // MARK: - Loop Statements

    @Test("For loop with collection")
    @MainActor
    func testForLoop() async throws {
        let template = MTLTemplate(
            name: "loop",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLForStatement(
                    binding: MTLBinding(
                        variable: MTLVariable(name: "item", type: "String"),
                        initExpression: MTLExpression(
                            AQLCollectionExpression(
                                source: AQLLiteralExpression(value: EcoreValueArray([
                                    "A" as EcoreValue,
                                    "B" as EcoreValue,
                                    "C" as EcoreValue
                                ])),
                                operation: .select,
                                iterator: "x",
                                body: AQLLiteralExpression(value: true)
                            )
                        )
                    ),
                    separator: MTLExpression(
                        AQLLiteralExpression(value: ", ")
                    ),
                    body: MTLBlock(statements: [
                        MTLExpressionStatement(
                            expression: MTLExpression(
                                AQLVariableExpression(name: "item")
                            )
                        )
                    ], inlined: false)
                )
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "Loop",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["loop": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = createInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "loop",
            arguments: [],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        let output = files["stdout"] ?? ""
        #expect(output == "A, B, C")
    }

    // MARK: - Let Statements

    @Test("Let statement with variable binding")
    @MainActor
    func testLetStatement() async throws {
        let template = MTLTemplate(
            name: "lettest",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLLetStatement(
                    variables: [
                        MTLBinding(
                            variable: MTLVariable(name: "greeting", type: "String"),
                            initExpression: MTLExpression(
                                AQLLiteralExpression(value: "Hello, World!")
                            )
                        )
                    ],
                    body: MTLBlock(statements: [
                        MTLExpressionStatement(
                            expression: MTLExpression(
                                AQLVariableExpression(name: "greeting")
                            )
                        )
                    ], inlined: false)
                )
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "LetTest",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["lettest": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = createInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)

        try await generator.generate(
            mainTemplate: "lettest",
            arguments: [],
            models: [:]
        )

        let files = await strategy.getGeneratedFiles()
        let output = files["stdout"] ?? ""
        #expect(output == "Hello, World!")
    }

    // MARK: - Statistics

    @Test("Generator tracks statistics")
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

        let strategy = createInMemoryStrategy()
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
    }
}
