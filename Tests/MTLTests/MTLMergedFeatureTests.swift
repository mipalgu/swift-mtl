//
//  MTLMergedFeatureTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Testing

@testable import MTL

/// Tests that the generation facilities work together with the Acceleo syntax.
@Suite("MTL Generation Facilities With Acceleo Syntax")
struct MTLMergedFeatureTests {

    @Test("Collect and emit work inside loops, invocations and queries")
    @MainActor
    func collectAndEmitWithInvocations() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query names() : Sequence(String) = Sequence{'b.B', 'a.A'}/]
            [template register(name : String)]
            [collect ('imports', name)/]
            [/template]
            [template main()]
            [for (n : String | names())][register(n)/][/for]
            [emit ('imports')]
            import [item/];
            [/emit]
            [/template]
            """)
        #expect(output == "\nimport b.B;\nimport a.A;\n")
    }

    @Test("Emitted blocks inherit the indentation of their line")
    @MainActor
    func emitIndentation() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            [collect ('items', Sequence{'x', 'y'})/]
            class A {
                [emit ('items')]
                int [item/];
                [/emit]
            }
            [/template]
            """)
        #expect(output == "class A {\n    int x;\n    int y;\n}\n")
    }

    @Test("The collected function sees values in a let and if context")
    @MainActor
    func collectedInConditions() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            [collect ('s', 'one')/]
            [let n = collected('s')->size()]
            [if (n = 1)]
            single
            [else]
            many
            [/if]
            [/let]
            [/template]
            """)
        #expect(output == "single\n")
    }

    @Test("Protected area clauses preserve user code when a file is regenerated")
    @MainActor
    func protectedAreaClausesPreserved() async throws {
        let source = """
            [module m('u')/]
            [template main()]
            [file ('A.txt', 'overwrite', 'UTF-8')]
            head
            [protected ('body') startTagPrefix('// ') endTagPrefix('// ')]
            default
            [/protected]
            [/file]
            [/template]
            """
        let strategy = MTLInMemoryStrategy()
        await strategy.setFile(
            "head\n// START PROTECTED REGION body\nuser code\n// END PROTECTED REGION body\n",
            at: "A.txt")
        let module = try await MTLTestSupport.parse(source)
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        let files = await strategy.getGeneratedFiles()
        let result = try #require(files["A.txt"])
        #expect(result.contains("user code"))
        #expect(!result.contains("default"))
    }

    @Test("A merge declaration works with imports collected in new syntax")
    @MainActor
    func mergeWithNewSyntax() async throws {
        let source = """
            [module m('u')/]
            [merge ('/**', '*/', '@generated', '@generated NOT', 'braces')/]
            [template main()]
            [file ('A.java', 'overwrite', 'UTF-8')]
            [collect ('imports', 'java.util.List')/]
            [emit ('imports')]import [item/];[/emit]

            /** @generated */
            class A {
                /** @generated */
                int a() { return 1; }
            }
            [/file]
            [/template]
            """
        let strategy = MTLInMemoryStrategy()
        await strategy.setFile(
            "import java.util.Set;\n\n/** @generated */\nclass A {\n    /** @generated NOT */\n    int a() { return 7; }\n}\n",
            at: "A.java")
        let module = try await MTLTestSupport.parse(source)
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        let result = try #require(await strategy.getGeneratedFiles()["A.java"])
        #expect(result.contains("return 7"))
        #expect(result.contains("import java.util.List;"))
        #expect(result.contains("import java.util.Set;"))
    }
}
