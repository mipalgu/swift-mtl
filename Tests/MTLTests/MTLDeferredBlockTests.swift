//
//  MTLDeferredBlockTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation
import Testing

@testable import MTL

/// Runs MTL source through the parser and generator with an in-memory strategy.
@MainActor
func generateFiles(
    _ source: String,
    strategy: MTLInMemoryStrategy = MTLInMemoryStrategy(),
    arguments: [(any EcoreValue)?] = []
) async throws -> [String: String] {
    let module = try await MTLParser().parse(source)
    let generator = MTLGenerator(module: module, generationStrategy: strategy)
    try await generator.generate(mainTemplate: "main", arguments: arguments, models: [:])
    return await strategy.getGeneratedFiles()
}

/// Sorts the `items` variable; stands in for a sorting operation of the expression language.
struct SortedItemsExpression: AQLExpression {
    @MainActor
    func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        let items = try await context.getVariable("items")
        let strings = (items as? EcoreValueArray)?.values.compactMap { $0 as? String } ?? []
        return EcoreValueArray(strings.sorted())
    }
}

@Suite("MTL Deferred Block Tests")
struct MTLDeferredBlockTests {

    private func module(_ body: String) -> String {
        "[module Test('http://example.com')]\n[template main()]\n\(body)\n[/template]"
    }

    private func trimmed(_ text: String?) -> String {
        (text ?? "<missing>").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test("Collected values are de-duplicated and emitted in insertion order")
    @MainActor
    func dedupAndOrder() async throws {
        let files = try await generateFiles(
            module(
                """
                [file ('A.txt', 'overwrite', 'UTF-8')]
                [collect ('imports', 'b.B')/][collect ('imports', 'a.A')/][collect ('imports', 'b.B')/]
                [emit ('imports') separator('\n')]import [item/];[/emit]
                [/file]
                """))
        #expect(trimmed(files["A.txt"]) == "import b.B;\nimport a.A;")
    }

    @Test("Emit before collect still includes later collects")
    @MainActor
    func emitBeforeCollect() async throws {
        let files = try await generateFiles(
            module(
                """
                [file ('A.txt', 'overwrite', 'UTF-8')]
                [emit ('imports') separator(', ')][item/][/emit]
                body
                [collect ('imports', 'late')/]
                [/file]
                """))
        #expect(trimmed(files["A.txt"]) == "late\nbody")
    }

    @Test("Sets are scoped per file")
    @MainActor
    func scopedPerFile() async throws {
        let files = try await generateFiles(
            module(
                """
                [file ('A.txt', 'overwrite', 'UTF-8')]
                [collect ('s', 'a')/][emit ('s')][item/][/emit]
                [/file]
                [file ('B.txt', 'overwrite', 'UTF-8')]
                [collect ('s', 'b')/][emit ('s')][item/][/emit]
                [/file]
                """))
        #expect(trimmed(files["A.txt"]) == "a")
        #expect(trimmed(files["B.txt"]) == "b")
    }

    @Test("Several sets are independent")
    @MainActor
    func multipleSets() async throws {
        let files = try await generateFiles(
            module(
                """
                [file ('A.txt', 'overwrite', 'UTF-8')]
                [collect ('imports', 'x')/][collect ('includes', 'y')/]
                [emit ('imports')]I:[item/][/emit]
                [emit ('includes')]C:[item/][/emit]
                [/file]
                """))
        #expect(trimmed(files["A.txt"]) == "I:x\nC:y")
    }

    @Test("Collections are flattened and nothing is collected for null")
    @MainActor
    func collectionValues() async throws {
        let source = """
            [module Test('http://example.com')]
            [template main(names : String)]
            [file ('A.txt', 'overwrite', 'UTF-8')]
            [collect ('s', names)/][collect ('s', null)/][collect ('s', 'x')/]
            [emit ('s') separator(',')][item/][/emit]
            [/file]
            [/template]
            """
        let names = EcoreValueArray(["x", "y", EcoreValueArray(["z", "y"])])
        let files = try await generateFiles(source, arguments: [names])
        #expect(trimmed(files["A.txt"]) == "x,y,z")
    }

    @Test("Emitted blocks see the variables of their position")
    @MainActor
    func variablesAtEmitPosition() async throws {
        let strategy = MTLInMemoryStrategy()
        let source = """
            [module Test('http://example.com')]
            [template main(prefix : String)]
            [file ('A.txt', 'overwrite', 'UTF-8')]
            [collect ('s', 'one')/][emit ('s')][prefix/][item/][/emit]
            [/file]
            [/template]
            """
        let files = try await generateFiles(source, strategy: strategy, arguments: ["P:"])
        #expect(trimmed(files["A.txt"]) == "P:one")
    }

    @Test("The items variable carries the whole collection")
    @MainActor
    func itemsVariable() async throws {
        let files = try await generateFiles(
            module(
                """
                [file ('A.txt', 'overwrite', 'UTF-8')]
                [collect ('s', 'a')/][collect ('s', 'b')/]
                [emit ('s') separator(' ')][item/]/[items->size()/][/emit]
                [/file]
                """))
        #expect(trimmed(files["A.txt"]) == "a/2 b/2")
    }

    @Test("The collected expression reads the current set")
    @MainActor
    func collectedExpression() async throws {
        let files = try await generateFiles(
            module(
                """
                [file ('A.txt', 'overwrite', 'UTF-8')]
                [collected('s')->size()/],[collect ('s', 'a')/][collected('s')->size()/],[collect ('s', 'a')/][collect ('s', 'b')/][collected('s')->size()/]
                [/file]
                [file ('B.txt', 'overwrite', 'UTF-8')]
                [collected('s')->size()/]
                [/file]
                """))
        #expect(trimmed(files["A.txt"]) == "0,1,2")
        #expect(trimmed(files["B.txt"]) == "0")
    }

    @Test("Items can be sorted with the in clause")
    @MainActor
    func sortingViaOrder() async throws {
        let emit = MTLEmitStatement(
            setName: MTLExpression(AQLLiteralExpression(value: "s")),
            separator: MTLExpression(AQLLiteralExpression(value: ",")),
            order: MTLExpression(SortedItemsExpression()),
            body: MTLBlock(
                statements: [
                    MTLExpressionStatement(
                        expression: MTLExpression(AQLVariableExpression(name: "item")))
                ], inlined: true))
        let context = MTLExecutionContext(
            module: MTLModule(name: "T", metamodels: [:]),
            generationStrategy: MTLInMemoryStrategy())
        context.collect(["pear", "apple", "fig"], into: "s")
        try await emit.execute(in: context)
        #expect(await context.getGeneratedText() == "apple,fig,pear")
    }

    @Test("A once block iterates over the collection itself")
    @MainActor
    func onceBlock() async throws {
        let binding = MTLBinding(
            variable: MTLVariable(name: "i", type: "String"),
            initExpression: MTLExpression(SortedItemsExpression()))
        let emit = MTLEmitStatement(
            setName: MTLExpression(AQLLiteralExpression(value: "s")),
            rendersOnce: true,
            body: MTLBlock(
                statements: [
                    MTLForStatement(
                        binding: binding,
                        separator: MTLExpression(AQLLiteralExpression(value: "|")),
                        body: MTLBlock(
                            statements: [
                                MTLExpressionStatement(
                                    expression: MTLExpression(AQLVariableExpression(name: "i")))
                            ], inlined: true))
                ], inlined: true))
        let context = MTLExecutionContext(
            module: MTLModule(name: "T", metamodels: [:]),
            generationStrategy: MTLInMemoryStrategy())
        context.collect(["b", "c", "a"], into: "s")
        try await emit.execute(in: context)
        #expect(await context.getGeneratedText() == "a|b|c")
    }

    @Test("Continuation lines keep the indentation of the emit position")
    @MainActor
    func indentation() async throws {
        let files = try await generateFiles(
            module(
                """
                [file ('A.txt', 'overwrite', 'UTF-8')]
                [collect ('s', 'a')/][collect ('s', 'b')/]
                    [emit ('s') separator('\n\n')]- [item/][/emit]
                end
                [/file]
                """))
        #expect(files["A.txt"]?.contains("    - a\n\n    - b\nend") == true)
    }

    @Test("Emit blocks cannot be nested")
    @MainActor
    func nestedEmitFails() async throws {
        await #expect(throws: MTLExecutionError.self) {
            _ = try await generateFiles(
                module(
                    """
                    [file ('A.txt', 'overwrite', 'UTF-8')]
                    [collect ('s', 'a')/][emit ('s')][emit ('s')][item/][/emit][/emit]
                    [/file]
                    """))
        }
    }

    @Test("Set names must be strings")
    @MainActor
    func nameMustBeString() async throws {
        let statement = MTLCollectStatement(
            setName: MTLExpression(AQLLiteralExpression(value: 5)),
            value: MTLExpression(AQLLiteralExpression(value: "x")))
        let context = MTLExecutionContext(
            module: MTLModule(name: "T", metamodels: [:]),
            generationStrategy: MTLInMemoryStrategy())
        await #expect(throws: MTLExecutionError.self) {
            try await statement.execute(in: context)
        }
    }

    @Test("Collect and emit parse into statements")
    func parsing() async throws {
        let module = try await MTLParser().parse(
            "[module T('u')]\n[template main()][collect ('s', 'x')/][emit ('s') in(items) separator(',') once][item/][/emit][/template]"
        )
        let statements = try #require(module.templates["main"]?.body.statements)
        #expect(statements[0] is MTLCollectStatement)
        let emit = try #require(statements[1] as? MTLEmitStatement)
        #expect(emit.rendersOnce)
        #expect(emit.order != nil)
        #expect(emit.separator != nil)
        #expect(emit.body.inlined)
    }
}
