//
//  MTLAQLIntegrationTests.swift
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

/// Services used to test registration.
private struct ShoutingServices: AQLServiceProvider {
    let suffix: String

    var services: [AQLService] {
        [
            AQLService("shout", receiver: .string) { call in
                try call.receiverString().uppercased() + suffix
            },
            AQLService("toUpperCase", receiver: .string) { _ in "service" },
            AQLService("twice", receiver: .standalone, arity: 1) { call in
                "\(try call.string(0))\(try call.string(0))"
            },
        ]
    }
}

@Suite("MTL Parser Emits AQL Nodes")
struct MTLAQLNodeTests {

    private static func expression(_ text: String) async throws -> any AQLExpression {
        let module = try await MTLTestSupport.parse("[module m('u')/]\n[query q() : OclAny = \(text)/]")
        return try #require(module.queries["q"]).body.aqlExpression
    }

    @Test("Integer division is the AQL div operator")
    func divOperator() async throws {
        let binary = try #require(try await Self.expression("7 div 2") as? AQLBinaryExpression)
        #expect(binary.op == .div)
    }

    @Test("A package qualified type is a type literal")
    func typeLiteral() async throws {
        let type = try #require(try await Self.expression("ecore::EClass") as? AQLTypeLiteralExpression)
        #expect(type.packageName == "ecore")
        #expect(type.typeName == "EClass")
    }

    @Test("A qualified enumeration literal is an enum literal")
    func enumLiteral() async throws {
        let literal = try #require(
            try await Self.expression("genmodel::GenProviderKind::Singleton") as? AQLEnumLiteralExpression)
        #expect(literal.packageName == "genmodel")
        #expect(literal.enumName == "GenProviderKind")
        #expect(literal.literal == "Singleton")
    }

    @Test("Qualified names in type operations are types")
    func typeOperationArguments() async throws {
        let call = try #require(try await Self.expression("self.oclIsKindOf(a::b::C)") as? AQLCallExpression)
        let type = try #require(call.arguments.first as? AQLTypeLiteralExpression)
        #expect(type.packageName == "a::b")
        #expect(type.typeName == "C")
    }

    @Test("Collection literals map to the AQL kinds", arguments: [
        ("Sequence", AQLCollectionLiteralExpression.Kind.sequence),
        ("OrderedSet", .orderedSet),
        ("Set", .set),
        ("Bag", .bag),
        ("Collection", .sequence),
    ])
    func collectionLiteral(name: String, kind: AQLCollectionLiteralExpression.Kind) async throws {
        let literal = try #require(try await Self.expression("\(name){1, 2}") as? AQLCollectionLiteralExpression)
        #expect(literal.kind == kind)
        #expect(literal.elements.count == 2)
    }

    @Test("Generic arrow operations use the arrow and lambdas are AQL lambdas")
    func arrowCall() async throws {
        let call = try #require(try await Self.expression("Sequence{1}->sortedBy(e | e)") as? AQLCallExpression)
        #expect(call.usesArrow)
        #expect(call.methodName == "sortedBy")
        let lambda = try #require(call.arguments.first as? AQLLambdaExpression)
        #expect(lambda.iterators == ["e"])
    }

    @Test("An iterating operation may omit the iterator")
    func implicitIterator() async throws {
        let call = try #require(try await Self.expression("Sequence{'a'}->sortedBy(size())") as? AQLCallExpression)
        let lambda = try #require(call.arguments.first as? AQLLambdaExpression)
        #expect(lambda.iterators == [MTLSyntax.selfVariable])
    }

    @Test("A dot call is not an arrow call")
    func dotCall() async throws {
        let invocation = try #require(try await Self.expression("'a'.size()") as? MTLInvocationExpression)
        #expect(!invocation.fallback.usesArrow)
    }
}

@Suite("MTL Evaluation Against The AQL Library")
struct MTLAQLEvaluationTests {

    @Test("Lambdas, sorting and the AQL string library work in templates")
    @MainActor
    func library() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()][Sequence{'ccc', 'a', 'bb'}->sortedBy(s | s.size())->sep(',')/][/template]
            """)
        #expect(output == "a,bb,ccc")
    }

    @Test("Strings are indexed from one")
    @MainActor
    func oneBasedStrings() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]['hello'.substring(1, 2)/],['hello'.at(1)/],[Sequence{'x', 'y'}->at(2)/][/template]
            """)
        #expect(output == "he,h,y")
    }

    @Test("Emit blocks can sort their elements with lambdas")
    @MainActor
    func emitSorting() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            [collect ('imports', Sequence{'b.B', 'a.A'})/]
            [emit ('imports') in(items->sortedBy(s | s))]
            import [item/];
            [/emit]
            [/template]
            """)
        #expect(output == "import a.A;\nimport b.B;\n")
    }

    @Test("Integer division and enumeration literals evaluate")
    @MainActor
    func divisionAndLiterals() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()][7 div 2/],[p::E::lit/][/template]
            """)
        #expect(output == "3,lit")
    }
}

@Suite("MTL Service Registration")
struct MTLServiceRegistrationTests {

    @MainActor
    private static func generate(
        _ source: String, configure: (MTLGenerator) -> Void = { _ in },
        providers: [any AQLServiceProvider] = []
    ) async throws -> String {
        let module = try await MTLTestSupport.parse(source)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(
            module: module, generationStrategy: strategy, serviceProviders: providers)
        configure(generator)
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        return await strategy.getGeneratedFiles()["stdout"] ?? ""
    }

    @Test("Providers passed to the generator are available to templates")
    @MainActor
    func providersInInitialiser() async throws {
        let source = """
            [module m('u')/]
            [template main()][twice('ab')/],['x'.shout()/][/template]
            """
        let output = try await Self.generate(source, providers: [ShoutingServices(suffix: "!")])
        #expect(output == "abab,X!")
    }

    @Test("Providers can be registered after creation, later ones first")
    @MainActor
    func laterRegistrationWins() async throws {
        let source = """
            [module m('u')/]
            [template main()]['x'.shout()/][/template]
            """
        let output = try await Self.generate(source) { generator in
            generator.register(ShoutingServices(suffix: "1"))
            generator.register(ShoutingServices(suffix: "2"))
        }
        #expect(output == "X2")
    }

    @Test("Services take precedence over the standard library")
    @MainActor
    func servicesOverrideLibrary() async throws {
        let source = """
            [module m('u')/]
            [template main()]['x'.toUpperCase()/][/template]
            """
        #expect(try await Self.generate(source, providers: [ShoutingServices(suffix: "")]) == "service")
        #expect(try await Self.generate(source) == "X")
    }

    @Test("Queries and templates of the module take precedence over services")
    @MainActor
    func moduleWins() async throws {
        let source = """
            [module m('u')/]
            [query shout(s : String) : String = 'query'/]
            [template toUpperCase(s : String)]template[/template]
            [template main()]['x'.shout()/],['x'.toUpperCase()/][/template]
            """
        let output = try await Self.generate(source, providers: [ShoutingServices(suffix: "")])
        #expect(output == "query,template")
    }

    @Test("Providers can be registered on the execution context")
    @MainActor
    func executionContextRegistration() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/]\n[template main()]['x'.shout()/][/template]")
        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module, generationStrategy: strategy, serviceProviders: [ShoutingServices(suffix: "a")])
        context.register(ShoutingServices(suffix: "b"))
        let template = try #require(module.templates["main"])
        try await template.body.execute(in: context)
        #expect(await context.getGeneratedText() == "Xb")
    }
}

@Suite("MTL Model Resources")
struct MTLModelResourceTests {

    /// A small containment tree: parent > child.
    @MainActor
    private static func makeResource() async -> (Resource, DynamicEObject, DynamicEObject) {
        let string = EDataType(name: "EString")
        var node = EClass(name: "Node")
        node.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        node.eStructuralFeatures.append(
            EReference(name: "children", eType: node, upperBound: -1, containment: true))
        var parent = DynamicEObject(eClass: node)
        parent.eSet("name", value: "parent")
        var child = DynamicEObject(eClass: node)
        child.eSet("name", value: "child")
        parent.eSet("children", value: [child.id])
        let resource = Resource()
        await resource.add(parent)
        await resource.add(child)
        return (resource, parent, child)
    }

    @Test("Generated models are visible to whole-model services")
    @MainActor
    func generatorRegistersResources() async throws {
        let (resource, _, child) = await Self.makeResource()
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template main(o : OclAny)][o.eContainer().eGet('name')/],[p::Node.allInstances()->size()/][/template]
            """)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.generate(mainTemplate: "main", arguments: [child], models: ["m": resource])
        #expect(await strategy.getGeneratedFiles()["stdout"] == "parent,2")
    }

    @Test("Registering a model on the execution context adds its resource")
    @MainActor
    func contextRegistersResources() async throws {
        let (resource, _, child) = await Self.makeResource()
        let module = try await MTLTestSupport.parse("[module m('u')/]")
        let context = MTLExecutionContext(module: module, generationStrategy: MTLInMemoryStrategy())
        await context.registerModel("m", resource: resource)
        context.setVariable("o", value: child)
        let expression = MTLExpression(
            AQLCallExpression(source: AQLVariableExpression(name: "o"), methodName: "eContainer"))
        let container = try await context.evaluateExpression(expression) as? DynamicEObject
        #expect(container?.eGet("name") as? String == "parent")
    }
}

@Suite("MTL Indentation")
struct MTLIndentationDeterminismTests {

    private static func template(blocks: Int) -> MTLTemplate {
        var statements: [any MTLStatement] = [
            MTLTextStatement(value: "a"), MTLNewLineStatement(indentationNeeded: true),
            MTLTextStatement(value: "b"),
        ]
        for _ in 0..<blocks {
            let text: any MTLStatement = MTLTextStatement(value: "x")
            let newLine: any MTLStatement = MTLNewLineStatement(indentationNeeded: true)
            let nested: any MTLStatement = MTLIfStatement(
                condition: MTLExpression(AQLLiteralExpression(value: true)),
                thenBlock: MTLBlock(statements: statements, inlined: false))
            statements = [text, newLine, nested]
        }
        return MTLTemplate(
            name: "main", visibility: .public, parameters: [], guard: nil, post: nil,
            body: MTLBlock(statements: statements, inlined: true), isMain: true, overrides: nil,
            documentation: nil)
    }

    @Test("Nested blocks indent every line by their depth, every time")
    @MainActor
    func nestedBlocksAreDeterministic() async throws {
        let module = MTLModule(name: "M", metamodels: [:], templates: ["main": Self.template(blocks: 2)])
        var outputs: Set<String> = []
        for _ in 0..<50 {
            let strategy = MTLInMemoryStrategy()
            let generator = MTLGenerator(module: module, generationStrategy: strategy)
            try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
            outputs.insert(await strategy.getGeneratedFiles()["stdout"] ?? "")
        }
        #expect(outputs == ["x\n    x\n        a\n        b"])
    }

    @Test("Blank lines carry no indentation")
    @MainActor
    func blankLines() async throws {
        let context = MTLExecutionContext(
            module: MTLModule(name: "M", metamodels: [:]), generationStrategy: MTLInMemoryStrategy())
        context.pushIndentation()
        await context.writeLine("a")
        await context.writeLine()
        await context.writeLine("b")
        #expect(await context.getGeneratedText() == "a\n\n    b\n")
    }

    @Test("Captured output is indented relative to where it starts")
    @MainActor
    func capturedOutput() async throws {
        let context = MTLExecutionContext(
            module: MTLModule(name: "M", metamodels: [:]), generationStrategy: MTLInMemoryStrategy())
        context.pushIndentation()
        context.pushIndentation()
        let captured = try await context.captureOutput {
            await context.writeLine("a")
            context.pushIndentation()
            await context.writeLine("b")
            context.popIndentation()
        }
        #expect(captured == "a\n    b\n")
    }
}
