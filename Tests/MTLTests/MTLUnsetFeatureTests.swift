//
//  MTLUnsetFeatureTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import MTL

/// Tests for how templates read structural features that have not been set.
@Suite("MTL Unset Features")
struct MTLUnsetFeatureTests {

    /// Creates a resource holding one instance of a class whose features are all unset.
    @MainActor
    private static func makeResource() async -> (Resource, DynamicEObject) {
        let boolean = EDataType(name: EcoreDataType.eBoolean.rawValue)
        let integer = EDataType(name: EcoreDataType.eInt.rawValue)
        let string = EDataType(name: EcoreDataType.eString.rawValue)
        var thing = EClass(name: "Thing")
        thing.eStructuralFeatures.append(EAttribute(name: "flag", eType: boolean))
        thing.eStructuralFeatures.append(EAttribute(name: "count", eType: integer))
        thing.eStructuralFeatures.append(
            EAttribute(name: "limit", eType: integer, defaultValueLiteral: "42"))
        thing.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        thing.eStructuralFeatures.append(
            EAttribute(name: "items", eType: string, upperBound: -1))
        let instance = DynamicEObject(eClass: thing)
        let resource = Resource()
        await resource.add(instance)
        return (resource, instance)
    }

    /// Runs a template body against an unset instance and returns the text produced.
    @MainActor
    private func output(
        _ body: String, unsetFeatureReads: UnsetFeatureReads? = nil
    ) async throws -> String {
        let (resource, instance) = await Self.makeResource()
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[template main(x : OclAny)]\(body)[/template]")
        let strategy = MTLInMemoryStrategy()
        let generator =
            if let unsetFeatureReads {
                MTLGenerator(
                    module: module, generationStrategy: strategy,
                    unsetFeatureReads: unsetFeatureReads)
            } else {
                MTLGenerator(module: module, generationStrategy: strategy)
            }
        try await generator.generate(
            mainTemplate: "main", arguments: [instance], models: ["m": resource])
        return await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? ""
    }

    @Test("The generator defaults to EMF semantics")
    @MainActor
    func generatorDefault() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/]")
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        #expect(generator.unsetFeatureReads == .defaults)
    }

    @Test("The generator reports the requested mode")
    @MainActor
    func generatorMode() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/]")
        let generator = MTLGenerator(
            module: module, generationStrategy: MTLInMemoryStrategy(), unsetFeatureReads: .undefined)
        #expect(generator.unsetFeatureReads == .undefined)
    }

    @Test("The execution context passes the mode to the engine it builds", arguments: UnsetFeatureReads.allCases)
    @MainActor
    func contextMode(_ mode: UnsetFeatureReads) async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/]")
        let context = MTLExecutionContext(
            module: module, generationStrategy: MTLInMemoryStrategy(), unsetFeatureReads: mode)
        #expect(await context.aqlContext.executionEngine.unsetFeatureReads == mode)
    }

    @Test("An unset integer prints as zero by default")
    @MainActor
    func unsetIntegerPrintsZero() async throws {
        #expect(try await output("[x.count/]") == "0")
    }

    @Test("An unset attribute with a declared default prints that default")
    @MainActor
    func declaredDefaultPrints() async throws {
        #expect(try await output("[x.limit/]") == "42")
    }

    @Test("An unset boolean is false by default")
    @MainActor
    func unsetBooleanIsFalse() async throws {
        #expect(try await output("[if (not x.flag)]no flag[/if]") == "no flag")
    }

    @Test("An unset string prints nothing by default")
    @MainActor
    func unsetStringPrintsNothing() async throws {
        #expect(try await output("[x.name/]") == "")
    }

    @Test("An unset many-valued attribute is empty by default")
    @MainActor
    func unsetManyValuedIsEmpty() async throws {
        #expect(try await output("[x.items->size()/]") == "0")
    }

    @Test("An unset integer prints nothing in undefined mode")
    @MainActor
    func undefinedIntegerPrintsNothing() async throws {
        #expect(try await output("[x.count/]", unsetFeatureReads: .undefined) == "")
    }

    @Test("An unset boolean does not satisfy a negated test in undefined mode")
    @MainActor
    func undefinedBooleanSkipsNegatedTest() async throws {
        #expect(
            try await output("[if (not x.flag)]no flag[/if]", unsetFeatureReads: .undefined) == "")
    }
}
