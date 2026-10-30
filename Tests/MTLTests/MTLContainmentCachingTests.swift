//
//  MTLContainmentCachingTests.swift
//  MTL
//
//  Created by Rene Hexel on 29/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation
import Testing

@testable import AQL
@testable import MTL

/// A model with two parents, `first` holding `child` and `second` holding nothing.
@MainActor
private struct TwoParentModel {
    let resource: Resource
    let first: DynamicEObject
    let second: DynamicEObject
    let child: DynamicEObject

    init() async {
        let string = EDataType(name: "EString")
        var node = EClass(name: "Node")
        node.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        node.eStructuralFeatures.append(
            EReference(name: "children", eType: node, upperBound: -1, containment: true))
        func make(_ name: String) -> DynamicEObject {
            var object = DynamicEObject(eClass: node)
            object.eSet("name", value: name)
            return object
        }
        var root = make("root")
        var first = make("first")
        let second = make("second")
        let child = make("child")
        first.eSet("children", value: [child.id])
        root.eSet("children", value: [first.id, second.id])
        let resource = Resource()
        for object in [root, first, second, child] { await resource.add(object) }
        self.resource = resource
        self.first = first
        self.second = second
        self.child = child
    }

    /// Moves `child` from `first` to `second`.
    func moveChild() async {
        await resource.eSet(objectId: first.id, feature: "children", value: [EUUID]())
        await resource.eSet(objectId: second.id, feature: "children", value: [child.id])
    }
}

/// Services that let templates observe and change the containment structure.
private struct ContainmentProbeServices: AQLServiceProvider {
    let model: TwoParentModel

    var services: [AQLService] {
        let model = self.model
        return [
            AQLService("containerLookups", receiver: .standalone) { call in
                call.context.containerLookups
            },
            AQLService("cachesIndex", receiver: .standalone) { call in
                call.context.cachesContainmentIndex
            },
            AQLService("moveChild", receiver: .standalone, modifiesModels: true) { _ in
                await model.moveChild()
                return ""
            },
        ]
    }
}

@Suite("MTL containment caching")
@MainActor
struct MTLContainmentCachingTests {
    private func generate(
        _ source: String, model: TwoParentModel, generator existing: MTLGenerator? = nil,
        options: MTLOptions = .standard
    ) async throws -> (String, MTLGenerator) {
        let module = try await MTLTestSupport.parse(source)
        let strategy = MTLInMemoryStrategy()
        let generator = existing ?? MTLGenerator(
            module: module, generationStrategy: strategy, options: options,
            serviceProviders: [ContainmentProbeServices(model: model)])
        try await generator.generate(
            mainTemplate: "main", arguments: [model.child], models: ["m": model.resource])
        return (await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? "", generator)
    }

    @Test("Generation looks up each container once")
    func generationBuildsIndexOnce() async throws {
        let model = await TwoParentModel()
        let (output, _) = try await generate("""
            [module m('u')/]
            [template main(o : OclAny)][for (i : Integer | Sequence{1, 2, 3, 4, 5, 6, 7, 8, 9, 10})][o.eContainer().name/],[o.ancestors()->size()/],[o.siblings()->size()/];[/for][cachesIndex()/],[containerLookups()/][/template]
            """, model: model)
        // The containers of child, first and root are each looked up once.
        #expect(output == String(repeating: "first,2,0;", count: 10) + "true,3")
    }

    @Test("A model-changing service called during generation is seen by later queries")
    func modifyingServiceDuringGeneration() async throws {
        let model = await TwoParentModel()
        let (output, _) = try await generate("""
            [module m('u')/]
            [template main(o : OclAny)][o.eContainer().name/][moveChild()/],[o.eContainer().name/],[o.eContainer().siblings()->collect(s | s.name)/][/template]
            """, model: model)
        #expect(output == "first,second,first")
    }

    @Test("Each generation sees changes made to the model between runs")
    func changesBetweenRuns() async throws {
        let model = await TwoParentModel()
        let source = """
            [module m('u')/]
            [template main(o : OclAny)][o.eContainer().name/][/template]
            """
        let module = try await MTLTestSupport.parse(source)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy, options: .standard)
        try await generator.generate(mainTemplate: "main", arguments: [model.child], models: ["m": model.resource])
        #expect(await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] == "first")
        await model.moveChild()
        let second = MTLInMemoryStrategy()
        let rerun = MTLGenerator(module: module, generationStrategy: second, options: .standard)
        try await rerun.generate(mainTemplate: "main", arguments: [model.child], models: ["m": model.resource])
        #expect(await second.getGeneratedFiles()[MTLTestSupport.standardOutput] == "second")
        try await generator.generate(mainTemplate: "main", arguments: [model.child], models: ["m": model.resource])
        #expect(await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput]?.hasSuffix("second") == true)
    }

    @Test("Queries called outside generation see the current model")
    func queriesOutsideGeneration() async throws {
        let model = await TwoParentModel()
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template main(o : OclAny)][parentName(o)/][/template]
            [query public parentName(o : OclAny) : String = o.eContainer().name/]
            """)
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy(), options: .standard)
        try await generator.generate(mainTemplate: "main", arguments: [model.child], models: ["m": model.resource])
        await model.moveChild()
        let helpers = MTLQueryHelpers.helpers(for: module, generator: generator)
        let result = try await MTLQueryHelpers.call("parentName", arguments: [model.child], among: helpers)
        #expect(result as? String == "second")
    }

    @Test("Generation without container caching looks up containers afresh", arguments: [false, true])
    func generationWithoutCaching(legacy: Bool) async throws {
        let model = await TwoParentModel()
        var options = legacy ? MTLOptions.legacy : MTLOptions()
        options.cachesContainers = false
        let (output, _) = try await generate("""
            [module m('u')/]
            [template main(o : OclAny)][for (i : Integer | Sequence{1, 2})][o.eContainer().name/],[o.ancestors()->size()/];[/for][cachesIndex()/][/template]
            """, model: model, options: options)
        #expect(output == "first,2;first,2;false")
    }

    @Test("A model changed during generation without container caching is seen at once")
    func changesWithoutCaching() async throws {
        let model = await TwoParentModel()
        let (output, _) = try await generate("""
            [module m('u')/]
            [template main(o : OclAny)][o.eContainer().name/][moveChild()/],[o.eContainer().name/][/template]
            """, model: model, options: .legacy)
        #expect(output == "first,second")
    }
}
