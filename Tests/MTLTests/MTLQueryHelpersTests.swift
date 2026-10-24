//
// MTLQueryHelpersTests.swift
// MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation
import Testing

@testable import MTL

/// Tests for exposing module queries to other hosts.
@Suite("MTL Query Helpers")
struct MTLQueryHelpersTests {

    /// Creates a temporary directory holding module files.
    private static func makeDirectory(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtl-helpers-\(UUID().uuidString)")
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        }
        return root
    }

    private static let libraries = [
        "lib/names.mtl": """
            [module names('u')/]
            [query public label(e : EObject) : String = 'item'/]
            [query private hidden(e : EObject) : String = 'secret'/]
            """,
        "main.mtl": """
            [module main('u')/]
            [import lib::names/]
            [query public render(e : EObject, lang : String) : String = e.name() + ':' + lang/]
            [query public name(e : EObject) : String = e.label() + '!'/]
            [query public twice(s : String) : String = s + s/]
            [query public twice(i : Integer) : Integer = i + i/]
            """,
    ]

    private static func element() -> DynamicEObject {
        DynamicEObject(eClass: EClass(name: "Thing"))
    }

    @Test("Queries of a module and its imports are listed")
    @MainActor
    func listing() async throws {
        let root = try Self.makeDirectory(Self.libraries)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try await MTLParser().parse(root.appendingPathComponent("main.mtl"))
        let helpers = MTLQueryHelpers.helpers(for: module)
        #expect(helpers.map(\.name) == ["render", "name", "twice", "twice", "label"])
        let render = try #require(helpers.first { $0.name == "render" })
        #expect(render.parameterTypes == ["EObject", "String"])
        #expect(render.returnType == "String")
        #expect(render.arity == 2)
    }

    @Test("Queries call each other and imported queries")
    @MainActor
    func calling() async throws {
        let root = try Self.makeDirectory(Self.libraries)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try await MTLParser().parse(root.appendingPathComponent("main.mtl"))
        let helpers = MTLQueryHelpers.helpers(for: module)
        let thing = Self.element()
        let result = try await MTLQueryHelpers.call("render", arguments: [thing, "c"], among: helpers)
        #expect(result as? String == "item!:c")
        let direct = try #require(helpers.first { $0.name == "label" })
        #expect(try await direct.call([thing]) as? String == "item")
    }

    @Test("Overloads are chosen by argument type")
    @MainActor
    func overloads() async throws {
        let root = try Self.makeDirectory(Self.libraries)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try await MTLParser().parse(root.appendingPathComponent("main.mtl"))
        let helpers = MTLQueryHelpers.helpers(for: module)
        #expect(try await MTLQueryHelpers.call("twice", arguments: ["ab"], among: helpers) as? String == "abab")
        #expect(try await MTLQueryHelpers.call("twice", arguments: [21], among: helpers) as? Int == 42)
        await #expect(throws: MTLExecutionError.self) {
            _ = try await MTLQueryHelpers.call("twice", arguments: [true], among: helpers)
        }
    }

    @Test("Private queries of an import are not listed")
    @MainActor
    func privateHidden() async throws {
        let root = try Self.makeDirectory(Self.libraries)
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try await MTLParser().parse(root.appendingPathComponent("main.mtl"))
        #expect(!MTLQueryHelpers.helpers(for: module).contains { $0.name == "hidden" })
    }

    @Test("Unknown queries and wrong arities are errors")
    @MainActor
    func errors() async throws {
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[query q(a : String, b : String) : String = a + b/]")
        let helpers = MTLQueryHelpers.helpers(for: module)
        await #expect(throws: MTLExecutionError.self) {
            _ = try await MTLQueryHelpers.call("nope", arguments: [], among: helpers)
        }
        await #expect(throws: MTLExecutionError.self) {
            _ = try await MTLQueryHelpers.call("q", arguments: ["a"], among: helpers)
        }
        let helper = try #require(helpers.first)
        await #expect(throws: MTLExecutionError.self) { _ = try await helper.call([]) }
    }

    @Test("A supplied generator shares its global variables")
    @MainActor
    func suppliedGenerator() async throws {
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[query q(a : String) : String = a + who/]")
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        generator.setGlobalVariable("who", value: "!")
        let helpers = MTLQueryHelpers.helpers(for: module, generator: generator)
        #expect(try await MTLQueryHelpers.call("q", arguments: ["x"], among: helpers) as? String == "x!")
    }

    @Test("Queries navigate the models registered with the supplied generator")
    @MainActor
    func registeredModels() async throws {
        let string = EDataType(name: "EString")
        var node = EClass(name: "Node")
        node.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        node.eStructuralFeatures.append(EReference(name: "next", eType: node))
        var first = DynamicEObject(eClass: node)
        var second = DynamicEObject(eClass: node)
        second.eSet("name", value: "second")
        first.eSet("next", value: second.id)
        let resource = Resource()
        await resource.add(first)
        await resource.add(second)
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[query follow(e : OclAny) : String = if e.next.oclIsUndefined() then '-' else e.next.name endif/]")
        let unregistered = MTLQueryHelpers.helpers(for: module)
        #expect(try await MTLQueryHelpers.call("follow", arguments: [first], among: unregistered) as? String == "-")
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        await generator.registerModel("IN", resource: resource)
        let helpers = MTLQueryHelpers.helpers(for: module, generator: generator)
        #expect(try await MTLQueryHelpers.call("follow", arguments: [first], among: helpers) as? String == "second")
    }

    @Test("Queries are callable as AQL services in both forms")
    @MainActor
    func services() async throws {
        let root = try Self.makeDirectory(Self.libraries)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try await MTLParser().parse(root.appendingPathComponent("main.mtl"))
        let host = try await MTLTestSupport.parse("""
            [module host('u')/]
            [template main(e : EObject)][e.render('c')/]|[render(e, 'd')/]|[twice(2)/][/template]
            """)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: host, generationStrategy: strategy)
        generator.register(MTLQueryServices(module: library))
        try await generator.generate(mainTemplate: "main", arguments: [Self.element()], models: [:])
        let text = await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? ""
        #expect(text == "item!:c|item!:d|4")
    }

    @Test("Imports resolve beside the importing file, then in the search paths")
    func importResolution() async throws {
        let root = try Self.makeDirectory([
            "app/main.mtl": "[module main('u')/]\n[import near/]\n[import shared::far/]",
            "app/near.mtl": "[module near('u')/]\n[query n() : String = 'n'/]",
            "app/shared/far.mtl": "[module far('u')/]\n[query f() : String = 'beside'/]",
            "libs/shared/far.mtl": "[module far('u')/]\n[query f() : String = 'path'/]",
            "libs/only.mtl": "[module only('u')/]",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try await MTLParser(searchPaths: [root.appendingPathComponent("libs")])
            .parse(root.appendingPathComponent("app/main.mtl"))
        let far = try #require(module.importedModules.first { $0.name == "far" })
        #expect(far.location?.path.hasSuffix("app/shared/far.mtl") == true)
        let fromPaths = try await MTLParser(searchPaths: [root.appendingPathComponent("libs")])
            .parse("[module x('u')/]\n[import only/]", filename: "x.mtl")
        #expect(fromPaths.name == "x")
    }
}
