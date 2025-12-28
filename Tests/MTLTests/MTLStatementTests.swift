//
//  MTLStatementTests.swift
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

@Suite("MTL Statement Tests")
struct MTLStatementTests {

    // MARK: - Helpers

    @MainActor
    func createContext(module: MTLModule) -> MTLExecutionContext {
        let strategy = MTLInMemoryStrategy()
        return MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )
    }

    func createSimpleModule() -> MTLModule {
        return MTLModule(
            name: "Test",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )
    }

    // MARK: - Text Statement

    @Test("Text statement generates literal text")
    @MainActor
    func testTextStatement() async throws {
        let stmt = MTLTextStatement(value: "Hello, World!")
        let context = createContext(module: createSimpleModule())

        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "Hello, World!")
    }

    @Test("Multiple text statements concatenate")
    @MainActor
    func testMultipleTextStatements() async throws {
        let stmt1 = MTLTextStatement(value: "Hello")
        let stmt2 = MTLTextStatement(value: ", ")
        let stmt3 = MTLTextStatement(value: "World!")

        let context = createContext(module: createSimpleModule())

        try await stmt1.execute(in: context)
        try await stmt2.execute(in: context)
        try await stmt3.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "Hello, World!")
    }

    // MARK: - NewLine Statement

    @Test("NewLine statement adds newline")
    @MainActor
    func testNewLineStatement() async throws {
        let stmt = MTLNewLineStatement(indentationNeeded: false)
        let context = createContext(module: createSimpleModule())

        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "\n")
    }

    @Test("NewLine with indentation")
    @MainActor
    func testNewLineWithIndentation() async throws {
        let context = createContext(module: createSimpleModule())

        // Push one level of indentation
        context.pushIndentation()

        let stmt = MTLNewLineStatement(indentationNeeded: true)
        try await stmt.execute(in: context)

        let textStmt = MTLTextStatement(value: "Indented")
        try await textStmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "\n    Indented")
    }

    // MARK: - Expression Statement

    @Test("Expression statement evaluates and outputs")
    @MainActor
    func testExpressionStatement() async throws {
        let stmt = MTLExpressionStatement(
            expression: MTLExpression(
                AQLLiteralExpression(value: 42)
            )
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "42")
    }

    @Test("Expression statement with string")
    @MainActor
    func testExpressionStatementString() async throws {
        let stmt = MTLExpressionStatement(
            expression: MTLExpression(
                AQLLiteralExpression(value: "test string")
            )
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "test string")
    }

    // MARK: - Comment Statement

    @Test("Comment statement produces no output")
    @MainActor
    func testCommentStatement() async throws {
        let stmt = MTLComment(
            value: "This is a comment",
            multiLines: false
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "")
    }

    // MARK: - If Statement

    @Test("If statement with true condition executes then block")
    @MainActor
    func testIfStatementTrue() async throws {
        let stmt = MTLIfStatement(
            condition: MTLExpression(AQLLiteralExpression(value: true)),
            thenBlock: MTLBlock(statements: [
                MTLTextStatement(value: "then")
            ], inlined: false),
            elseIfBlocks: [],
            elseBlock: MTLBlock(statements: [
                MTLTextStatement(value: "else")
            ], inlined: false)
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "then")
    }

    @Test("If statement with false condition executes else block")
    @MainActor
    func testIfStatementFalse() async throws {
        let stmt = MTLIfStatement(
            condition: MTLExpression(AQLLiteralExpression(value: false)),
            thenBlock: MTLBlock(statements: [
                MTLTextStatement(value: "then")
            ], inlined: false),
            elseIfBlocks: [],
            elseBlock: MTLBlock(statements: [
                MTLTextStatement(value: "else")
            ], inlined: false)
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "else")
    }

    @Test("If statement with elseif")
    @MainActor
    func testIfStatementElseIf() async throws {
        let stmt = MTLIfStatement(
            condition: MTLExpression(AQLLiteralExpression(value: false)),
            thenBlock: MTLBlock(statements: [
                MTLTextStatement(value: "then")
            ], inlined: false),
            elseIfBlocks: [
                (
                    condition: MTLExpression(AQLLiteralExpression(value: true)),
                    block: MTLBlock(statements: [
                        MTLTextStatement(value: "elseif")
                    ], inlined: false)
                )
            ],
            elseBlock: MTLBlock(statements: [
                MTLTextStatement(value: "else")
            ], inlined: false)
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "elseif")
    }

    // MARK: - Let Statement

    @Test("Let statement binds variable")
    @MainActor
    func testLetStatement() async throws {
        let stmt = MTLLetStatement(
            variables: [
                MTLBinding(
                    variable: MTLVariable(name: "x", type: "Integer"),
                    initExpression: MTLExpression(
                        AQLLiteralExpression(value: 100)
                    )
                )
            ],
            body: MTLBlock(statements: [
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLVariableExpression(name: "x")
                    )
                )
            ], inlined: false)
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "100")
    }

    @Test("Let statement with multiple bindings")
    @MainActor
    func testLetStatementMultiple() async throws {
        let stmt = MTLLetStatement(
            variables: [
                MTLBinding(
                    variable: MTLVariable(name: "a", type: "String"),
                    initExpression: MTLExpression(
                        AQLLiteralExpression(value: "Hello")
                    )
                ),
                MTLBinding(
                    variable: MTLVariable(name: "b", type: "String"),
                    initExpression: MTLExpression(
                        AQLLiteralExpression(value: " World")
                    )
                )
            ],
            body: MTLBlock(statements: [
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLBinaryExpression(
                            left: AQLVariableExpression(name: "a"),
                            op: .add,
                            right: AQLVariableExpression(name: "b")
                        )
                    )
                )
            ], inlined: false)
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "Hello World")
    }

    @Test("Let statement scoping")
    @MainActor
    func testLetStatementScoping() async throws {
        let context = createContext(module: createSimpleModule())

        // Set outer variable
        context.setVariable("x", value: 42)

        // Let should shadow outer variable
        let stmt = MTLLetStatement(
            variables: [
                MTLBinding(
                    variable: MTLVariable(name: "x", type: "Integer"),
                    initExpression: MTLExpression(
                        AQLLiteralExpression(value: 100)
                    )
                )
            ],
            body: MTLBlock(statements: [
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLVariableExpression(name: "x")
                    )
                )
            ], inlined: false)
        )

        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "100")

        // After let, outer variable should be visible again
        let outerValue = try await context.getVariable("x") as? Int
        #expect(outerValue == 42)
    }

    // MARK: - For Statement

    @Test("For statement iterates over collection")
    @MainActor
    func testForStatement() async throws {
        let stmt = MTLForStatement(
            binding: MTLBinding(
                variable: MTLVariable(name: "item", type: "String"),
                initExpression: MTLExpression(
                    AQLLiteralExpression(value: EcoreValueArray([
                        "A" as any EcoreValue,
                        "B" as any EcoreValue,
                        "C" as any EcoreValue
                    ]))
                )
            ),
            separator: nil,
            body: MTLBlock(statements: [
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLVariableExpression(name: "item")
                    )
                )
            ], inlined: false)
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "ABC")
    }

    @Test("For statement with separator")
    @MainActor
    func testForStatementWithSeparator() async throws {
        let stmt = MTLForStatement(
            binding: MTLBinding(
                variable: MTLVariable(name: "item", type: "String"),
                initExpression: MTLExpression(
                    AQLLiteralExpression(value: EcoreValueArray([
                        "A" as any EcoreValue,
                        "B" as any EcoreValue,
                        "C" as any EcoreValue
                    ]))
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

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "A, B, C")
    }

    @Test("For statement with single item")
    @MainActor
    func testForStatementSingleItem() async throws {
        let stmt = MTLForStatement(
            binding: MTLBinding(
                variable: MTLVariable(name: "item", type: "String"),
                initExpression: MTLExpression(
                    AQLLiteralExpression(value: EcoreValueArray([
                        "X" as any EcoreValue
                    ]))
                )
            ),
            separator: nil,
            body: MTLBlock(statements: [
                MTLExpressionStatement(
                    expression: MTLExpression(
                        AQLVariableExpression(name: "item")
                    )
                )
            ], inlined: false)
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "X")
    }

    @Test("For statement with empty collection")
    @MainActor
    func testForStatementEmpty() async throws {
        let stmt = MTLForStatement(
            binding: MTLBinding(
                variable: MTLVariable(name: "item", type: "String"),
                initExpression: MTLExpression(
                    AQLLiteralExpression(value: EcoreValueArray([]))
                )
            ),
            separator: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "X")
            ], inlined: false)
        )

        let context = createContext(module: createSimpleModule())
        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output == "")
    }
}
