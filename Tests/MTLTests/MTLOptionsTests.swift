//
//  MTLOptionsTests.swift
//  MTL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import AQL
@testable import MTL

/// Tests for the options that select between the standard behaviour and that of version 0.6.
@Suite("MTL Options")
@MainActor
struct MTLOptionsTests {

    /// A template that writes a line ending in a line break for its argument.
    private static let lineTemplate = "[template line(s : String)]\nline [s/]\n[/template]\n"

    /// Wraps the lines of a main template in a module that also declares ``lineTemplate``.
    private static func module(_ lines: String) -> String {
        "[module m('u')/]\n[template main()]\n\(lines)\n[/template]\n" + lineTemplate
    }

    /// A metaclass `Node` for single model objects.
    private static let node = EClass(name: "Node")

    // MARK: - Presets

    @Test("Options created without arguments are the standard options")
    func defaults() {
        let options = MTLOptions()
        #expect(options == .standard)
        #expect(options.aql == .standard)
        #expect(options.blockLineBreaks == .acceleo)
        #expect(options.collectionParameters == .conforming)
        #expect(options.checksLetTypes)
        #expect(options.letTypeMismatches == .error)
        #expect(options.cachesContainers)
        #expect(options.unsetFeatureReads == .defaults)
    }

    @Test("The legacy options give the behaviour of version 0.6")
    func legacy() {
        let options = MTLOptions.legacy
        #expect(options != .standard)
        #expect(options.aql == .legacy)
        #expect(options.blockLineBreaks == .kept)
        #expect(options.collectionParameters == .exact)
        #expect(!options.checksLetTypes)
        #expect(options.letTypeMismatches == .error)
        #expect(!options.cachesContainers)
        #expect(options.unsetFeatureReads == .defaults)
    }

    @Test("Options are told apart by every property")
    func equality() {
        var options = MTLOptions()
        options.unsetFeatureReads = .undefined
        #expect(options != .standard)
        #expect(Set([options, .standard, .legacy, MTLOptions()]).count == 3)
    }

    @Test("The option values are spelt for the command line")
    func spellings() {
        #expect(MTLBlockLineBreaks.allCases.map(\.rawValue) == ["acceleo", "kept"])
        #expect(MTLCollectionParameters.allCases.map(\.rawValue) == ["conforming", "exact"])
        #expect(MTLBlockLineBreaks(rawValue: "kept") == .kept)
        #expect(MTLCollectionParameters(rawValue: "exact") == .exact)
        #expect(MTLCollectionParameters(rawValue: "strict") == nil)
    }

    // MARK: - Initialisers

    @Test("A generator created without options has the legacy options")
    func generatorWithoutOptions() async throws {
        let module = try await MTLTestSupport.parse(Self.module("a"))
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        #expect(generator.options == .legacy)
        #expect(generator.unsetFeatureReads == .defaults)
        let undefined = MTLGenerator(
            module: module, generationStrategy: MTLInMemoryStrategy(), unsetFeatureReads: .undefined)
        var expected = MTLOptions.legacy
        expected.unsetFeatureReads = .undefined
        #expect(undefined.options == expected)
        #expect(undefined.unsetFeatureReads == .undefined)
    }

    @Test("A generator keeps the options it is created with")
    func generatorWithOptions() async throws {
        let module = try await MTLTestSupport.parse(Self.module("a"))
        var options = MTLOptions()
        options.unsetFeatureReads = .undefined
        options.letTypeMismatches = .skip
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy(), options: options)
        #expect(generator.options == options)
        #expect(generator.unsetFeatureReads == .undefined)
    }

    @Test("An execution context created without options has the legacy options")
    func contextWithoutOptions() async throws {
        let module = try await MTLTestSupport.parse(Self.module("a"))
        let context = MTLExecutionContext(module: module, generationStrategy: MTLInMemoryStrategy())
        #expect(context.options == .legacy)
        let undefined = MTLExecutionContext(
            module: module, generationStrategy: MTLInMemoryStrategy(), unsetFeatureReads: .undefined)
        #expect(undefined.options.unsetFeatureReads == .undefined)
        #expect(undefined.options.blockLineBreaks == .kept)
    }

    @Test("An execution context keeps the options it is created with")
    func contextWithOptions() async throws {
        let module = try await MTLTestSupport.parse(Self.module("a"))
        let context = MTLExecutionContext(
            module: module, generationStrategy: MTLInMemoryStrategy(), options: .standard)
        #expect(context.options == .standard)
        #expect(context.aqlContext.options == .standard)
    }

    @Test("Execution contexts evaluate expressions with the options of the expression language")
    func contextExpressionOptions() async throws {
        let module = try await MTLTestSupport.parse(Self.module("a"))
        let legacy = MTLExecutionContext(module: module, generationStrategy: MTLInMemoryStrategy())
        #expect(legacy.aqlContext.options == .legacy)
        var options = MTLOptions.standard
        options.aql.collectionArguments = .firstElement
        let mixed = MTLExecutionContext(module: module, generationStrategy: MTLInMemoryStrategy(), options: options)
        #expect(mixed.aqlContext.options.collectionArguments == .firstElement)
        #expect(mixed.aqlContext.options.collectionKinds == .distinguished)
    }

    @Test("A supplied expression context keeps its own options")
    func suppliedExpressionContext() async throws {
        let module = try await MTLTestSupport.parse(Self.module("a"))
        let aqlContext = AQLExecutionContext(
            executionEngine: ECoreExecutionEngine(models: [:]), options: .legacy)
        let context = MTLExecutionContext(
            module: module, generationStrategy: MTLInMemoryStrategy(), options: .standard, aqlContext: aqlContext)
        #expect(context.aqlContext.options == .legacy)
    }

    // MARK: - Expression Language

    @Test(
        "Templates evaluate expressions with the options of the expression language",
        arguments: [
            ("[Sequence{'a'}->append(Sequence{'b', 'c'})->size()/]", "2", "2"),
            ("[OrderedSet{'a', 'b', 'c'}->append('b')/]", "acb", "abcb"),
            ("['a'->including('a')->size()/]", "1", "2"),
        ])
    func expressionOptions(expression: String, standard: String, legacy: String) async throws {
        let source = Self.module(expression)
        #expect(try await MTLTestSupport.output(source, options: .standard) == standard + "\n")
        #expect(try await MTLTestSupport.output(source, options: MTLOptions(aql: .legacy)) == legacy + "\n")
        #expect(try await MTLTestSupport.output(source) == legacy + "\n")
    }

    // MARK: - Block Line Breaks

    @Test(
        "One-line blocks drop or keep the line break after their closing tag",
        arguments: [
            ("a\n[if (true)][line('x')/][/if]\nb", "a\nline x\nb\n", "a\nline x\n\nb\n"),
            ("a\n[if (false)]x[/if]\nb", "a\nb\n", "a\n\nb\n"),
            ("a\n[for (s | Sequence{'x', 'y'})][line(s)/][/for]\nb", "a\nline x\nline y\nb\n", "a\nline x\nline y\n\nb\n"),
            ("a\n [if (false)]x[/if]\nb", "a\n \nb\n", "a\n \nb\n"),
        ])
    func blockLineBreaks(lines: String, acceleo: String, kept: String) async throws {
        let source = Self.module(lines)
        #expect(try await MTLTestSupport.output(source, options: MTLOptions(blockLineBreaks: .acceleo)) == acceleo)
        #expect(try await MTLTestSupport.output(source, options: MTLOptions(blockLineBreaks: .kept)) == kept)
        #expect(try await MTLTestSupport.output(source) == kept)
    }

    // MARK: - Collection Parameters

    @Test(
        "Overloads by element type are told apart only when collections conform",
        arguments: [
            ("[template t(s : Sequence(String))]strings[/template]\n[template t(s : Sequence(Integer))]integers[/template]", "strings"),
            ("[template t(s : Sequence(Integer))]integers[/template]\n[template t(s : Sequence(String))]strings[/template]", "integers"),
        ])
    func overloadsByElementType(overloads: String, exact: String) async throws {
        let source = "[module m('u')/]\n[template main()][t(Sequence{1, 2})/][/template]\n" + overloads + "\n"
        #expect(try await MTLTestSupport.output(source, options: MTLOptions(collectionParameters: .conforming)) == "integers")
        #expect(try await MTLTestSupport.output(source, options: MTLOptions(collectionParameters: .exact)) == exact)
        #expect(try await MTLTestSupport.output(source) == exact)
    }

    @Test("A collection whose elements do not conform is accepted only in the exact mode")
    func mismatchedElements() async throws {
        let source = """
            [module m('u')/]
            [template main()][t(Sequence{1, 2})/][/template]
            [template t(s : OrderedSet(String))][s->size()/][/template]
            """
        #expect(try await MTLTestSupport.output(source, options: MTLOptions(collectionParameters: .exact)) == "2")
        await #expect(throws: (any Error).self) {
            try await MTLTestSupport.output(source, options: MTLOptions(collectionParameters: .conforming))
        }
    }

    @Test("A single model object stands for a collection only when collections conform")
    func singleObject() async throws {
        let source = """
            [module m('u')/]
            [template main(o : Node)][t(o)/][/template]
            [template t(s : Sequence(Node))][s->size()/][/template]
            """
        let object = DynamicEObject(eClass: Self.node)
        let conforming = MTLOptions(collectionParameters: .conforming)
        #expect(try await MTLTestSupport.output(source, arguments: [object], options: conforming) == "1")
        await #expect(throws: (any Error).self) {
            try await MTLTestSupport.output(source, arguments: [object], options: MTLOptions(collectionParameters: .exact))
        }
    }

    @Test("A typed let holds a collection only when collections conform")
    func typedLetBinding() async throws {
        let source = """
            [module m('u')/]
            [template main(o : Node)][let s : Sequence(Node) = o][s->size()/][/let][/template]
            """
        let object = DynamicEObject(eClass: Self.node)
        let conforming = MTLOptions(collectionParameters: .conforming)
        #expect(try await MTLTestSupport.output(source, arguments: [object], options: conforming) == "1")
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.output(source, arguments: [object], options: MTLOptions(collectionParameters: .exact))
        }
    }

    @Test("The matcher scores collections by their elements only when collections conform")
    func matcher() {
        let sequence = EcoreValueArray([1, 2])
        let object = DynamicEObject(eClass: Self.node)
        #expect(MTLTypeMatcher.distance(of: sequence, to: "OrderedSet(ecore::EClass)", collectionParameters: .exact) == 1)
        #expect(MTLTypeMatcher.distance(of: sequence, to: "OrderedSet(ecore::EClass)", collectionParameters: .conforming) == nil)
        #expect(MTLTypeMatcher.distance(of: [1, 2], to: "Sequence(Integer)", collectionParameters: .exact) == nil)
        #expect(MTLTypeMatcher.distance(of: [1, 2], to: "Sequence(Integer)", collectionParameters: .conforming) == 1)
        #expect(MTLTypeMatcher.distance(of: object, to: "Sequence(Node)", collectionParameters: .exact) == nil)
        #expect(MTLTypeMatcher.distance(of: object, to: "Sequence(Node)", collectionParameters: .conforming) != nil)
        #expect(MTLTypeMatcher.distance(of: object, to: "Node", collectionParameters: .exact) == 0)
        #expect(MTLTypeMatcher.distance(of: "a", to: "String", collectionParameters: .exact) == 0)
    }

    @Test("Bound values become collections only when collections conform")
    func boundValues() throws {
        let object = DynamicEObject(eClass: Self.node)
        #expect(MTLTypeMatcher.boundValue(of: object, to: "Sequence(Node)", collectionParameters: .exact) is DynamicEObject)
        #expect(MTLTypeMatcher.boundValue(of: ["a"], to: "Sequence(String)", collectionParameters: .exact) is [String])
        #expect(
            MTLTypeMatcher.boundValue(of: object, to: "Sequence(Node)", collectionParameters: .conforming)
                is EcoreValueArray)
    }

    @Test("Query helpers match collections as the options of their generator say")
    func queryHelpers() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [query count(xs : Sequence(String)) : Integer = xs->size()/]
            """)
        let standard = MTLQueryHelpers.helpers(for: module, options: .standard)
        #expect(standard.allSatisfy { $0.collectionParameters == .conforming })
        #expect(try await MTLQueryHelpers.call("count", arguments: [["a", "b"]], among: standard) as? Int == 2)
        await #expect(throws: MTLExecutionError.self) {
            try await MTLQueryHelpers.call("count", arguments: [EcoreValueArray([1, 2])], among: standard)
        }

        let legacy = MTLQueryHelpers.helpers(for: module)
        #expect(legacy.allSatisfy { $0.collectionParameters == .exact })
        #expect(try await MTLQueryHelpers.call("count", arguments: [EcoreValueArray([1, 2])], among: legacy) as? Int == 2)
        await #expect(throws: MTLExecutionError.self) {
            try await MTLQueryHelpers.call("count", arguments: [["a", "b"]], among: legacy)
        }

        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy(), options: .standard)
        let shared = MTLQueryHelpers.helpers(for: module, generator: generator)
        #expect(shared.allSatisfy { $0.collectionParameters == .conforming })
        let services = MTLQueryServices(module: module, options: .standard)
        #expect(services.helpers.allSatisfy { $0.collectionParameters == .conforming })
        #expect(MTLQueryServices(module: module).helpers.allSatisfy { $0.collectionParameters == .exact })
    }

    @Test("A query helper created without a matching mode matches collections exactly")
    func queryHelperInitialisers() {
        let legacy = MTLQueryHelper(name: "q", parameterTypes: [], returnType: "String") { _ in nil }
        #expect(legacy.collectionParameters == .exact)
        let standard = MTLQueryHelper(
            name: "q", parameterTypes: [], returnType: "String", collectionParameters: .conforming
        ) { _ in nil }
        #expect(standard.collectionParameters == .conforming)
    }

    // MARK: - Let Types

    @Test("A let checks the declared types of its variables only if asked to")
    func checksLetTypes() async throws {
        let source = Self.module("[let x : Integer = 'a'][x/][/let]")
        #expect(try await MTLTestSupport.output(source, options: MTLOptions(checksLetTypes: false)) == "a\n")
        #expect(try await MTLTestSupport.output(source) == "a\n")
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.output(source, options: MTLOptions(checksLetTypes: true))
        }
        let skipping = MTLOptions(checksLetTypes: true, letTypeMismatches: .skip)
        #expect(try await MTLTestSupport.output(source, options: skipping) == "")
    }

    @Test("An unchecked let records no warning in the skip mode")
    func uncheckedLetHasNoWarnings() async throws {
        let module = try await MTLTestSupport.parse(Self.module("[let x : Integer = 'a'][x/][/let]"))
        let strategy = MTLInMemoryStrategy()
        let options = MTLOptions(checksLetTypes: false, letTypeMismatches: .skip)
        let generator = MTLGenerator(module: module, generationStrategy: strategy, options: options)
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        #expect(generator.statistics.warnings.isEmpty)
        #expect(await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] == "a\n")
    }
}
