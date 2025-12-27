//
//  MTLMacroTests.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Testing
@testable import MTL
import AQL

@Suite("MTL Macro Tests")
struct MTLMacroTests {

    // MARK: - Basic Macro

    @Test("Simple macro without parameters")
    @MainActor
    func testSimpleMacro() async throws {
        let macro = MTLMacro(
            name: "greeting",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "Hello, World!")
            ], inlined: false),
            documentation: nil
        )

        let module = MTLModule(
            name: "MacroTest",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: ["greeting": macro],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        // Invoke macro
        let invocation = MTLMacroInvocation(
            macroName: "greeting",
            arguments: [],
            bodyContent: nil
        )

        try await invocation.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "Hello, World!")
    }

    @Test("Macro with parameters")
    @MainActor
    func testMacroWithParameters() async throws {
        let macro = MTLMacro(
            name: "personalize",
            parameters: [
                MTLVariable(name: "name", type: "String")
            ],
            bodyParameter: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "Hello, "),
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLVariableExpression(name: "name")
                    )
                ),
                MTLTextStatement(value: "!")
            ], inlined: false),
            documentation: nil
        )

        let module = MTLModule(
            name: "MacroTest",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: ["personalize": macro],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        // Invoke macro with argument
        let invocation = MTLMacroInvocation(
            macroName: "personalize",
            arguments: [
                MTLExpression(AQLLiteralExpression(value: "Alice"))
            ],
            bodyContent: nil
        )

        try await invocation.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "Hello, Alice!")
    }

    @Test("Macro with body parameter")
    @MainActor
    func testMacroWithBodyParameter() async throws {
        let macro = MTLMacro(
            name: "wrap",
            parameters: [],
            bodyParameter: "content",
            body: MTLBlock(statements: [
                MTLTextStatement(value: "["),
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLVariableExpression(name: "content")
                    )
                ),
                MTLTextStatement(value: "]")
            ], inlined: false),
            documentation: nil
        )

        let module = MTLModule(
            name: "MacroTest",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: ["wrap": macro],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        // Invoke macro with body content
        let invocation = MTLMacroInvocation(
            macroName: "wrap",
            arguments: [],
            bodyContent: MTLBlock(statements: [
                MTLTextStatement(value: "BODY CONTENT")
            ], inlined: false)
        )

        try await invocation.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "[BODY CONTENT]")
    }

    @Test("Macro with parameters and body")
    @MainActor
    func testMacroWithParametersAndBody() async throws {
        let macro = MTLMacro(
            name: "labeled",
            parameters: [
                MTLVariable(name: "label", type: "String")
            ],
            bodyParameter: "content",
            body: MTLBlock(statements: [
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLVariableExpression(name: "label")
                    )
                ),
                MTLTextStatement(value: ": "),
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLVariableExpression(name: "content")
                    )
                )
            ], inlined: false),
            documentation: nil
        )

        let module = MTLModule(
            name: "MacroTest",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: ["labeled": macro],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        // Invoke macro
        let invocation = MTLMacroInvocation(
            macroName: "labeled",
            arguments: [
                MTLExpression(AQLLiteralExpression(value: "Title"))
            ],
            bodyContent: MTLBlock(statements: [
                MTLTextStatement(value: "Content Here")
            ], inlined: false)
        )

        try await invocation.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "Title: Content Here")
    }

    @Test("Macro invocation not found throws error")
    @MainActor
    func testMacroNotFound() async throws {
        let module = MTLModule(
            name: "MacroTest",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],  // No macros defined
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        let invocation = MTLMacroInvocation(
            macroName: "nonexistent",
            arguments: [],
            bodyContent: nil
        )

        await #expect(throws: MTLExecutionError.self) {
            try await invocation.execute(in: context)
        }
    }

    @Test("Nested macro invocations")
    @MainActor
    func testNestedMacros() async throws {
        let innerMacro = MTLMacro(
            name: "inner",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "INNER")
            ], inlined: false),
            documentation: nil
        )

        let outerMacro = MTLMacro(
            name: "outer",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "["),
                MTLMacroInvocation(
                    macroName: "inner",
                    arguments: [],
                    bodyContent: nil
                ),
                MTLTextStatement(value: "]")
            ], inlined: false),
            documentation: nil
        )

        let module = MTLModule(
            name: "MacroTest",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [
                "inner": innerMacro,
                "outer": outerMacro
            ],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        let invocation = MTLMacroInvocation(
            macroName: "outer",
            arguments: [],
            bodyContent: nil
        )

        try await invocation.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "[INNER]")
    }

    // MARK: - Macro Equality and Hashing

    @Test("Macro equality")
    func testMacroEquality() {
        let macro1 = MTLMacro(
            name: "test",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [], inlined: false),
            documentation: nil
        )

        let macro2 = MTLMacro(
            name: "test",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [], inlined: false),
            documentation: nil
        )

        let macro3 = MTLMacro(
            name: "different",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [], inlined: false),
            documentation: nil
        )

        #expect(macro1 == macro2)
        #expect(macro1 != macro3)
    }

    @Test("Macro hashable")
    func testMacroHashable() {
        let macro1 = MTLMacro(
            name: "test",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [], inlined: false),
            documentation: nil
        )

        let macro2 = MTLMacro(
            name: "test",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [], inlined: false),
            documentation: nil
        )

        var set: Set<MTLMacro> = []
        set.insert(macro1)
        set.insert(macro2)

        #expect(set.count == 1)
    }
}
