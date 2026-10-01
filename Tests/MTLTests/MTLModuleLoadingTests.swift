//
//  MTLModuleLoadingTests.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import MTL

@Suite("MTL Module Loading, Imports and Extends")
struct MTLModuleLoadingTests {

    private static func fixture(_ name: String) -> URL {
        MTLTestSupport.resource("modules/\(name)")
    }

    private static func load(_ name: String, searchPaths: [URL] = []) async throws -> MTLModule {
        try await MTLParser(searchPaths: searchPaths).parse(fixture(name))
    }

    // MARK: - Resolver

    @Test("Qualified names map to relative file paths")
    func relativePath() {
        let resolver = MTLModuleResolver()
        #expect(resolver.relativePath(for: "a::b::c") == "a/b/c.mtl")
        #expect(resolver.relativePath(for: "single") == "single.mtl")
    }

    @Test("Candidates list the importing directory before the search paths")
    func candidateOrder() {
        let importing = URL(fileURLWithPath: "/work/src/main.mtl")
        let resolver = MTLModuleResolver(searchPaths: [
            URL(fileURLWithPath: "/lib/one"), URL(fileURLWithPath: "/lib/two")
        ])
        let paths = resolver.candidates(for: "pkg::mod", relativeTo: importing).map(\.path)
        #expect(paths == ["/work/src/pkg/mod.mtl", "/lib/one/pkg/mod.mtl", "/lib/two/pkg/mod.mtl"])
    }

    @Test("Without an importing file only the search paths are used")
    func candidatesWithoutImportingFile() {
        let resolver = MTLModuleResolver(searchPaths: [URL(fileURLWithPath: "/lib")])
        #expect(resolver.candidates(for: "m", relativeTo: nil).map(\.path) == ["/lib/m.mtl"])
        #expect(MTLModuleResolver().candidates(for: "m", relativeTo: nil).isEmpty)
    }

    @Test("A missing module lists everything that was searched")
    func missingModuleError() async {
        do {
            _ = try await Self.load("missing.mtl")
            Issue.record("Expected an error")
        } catch let error as MTLModuleResolutionError {
            guard case .notFound(let module, let searched, let requiredBy) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(module == "does::not::exist")
            #expect(requiredBy == "missing")
            #expect(searched.count == 1)
            #expect(searched[0].hasSuffix("does/not/exist.mtl"))
            #expect(error.errorDescription?.contains("does::not::exist") == true)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test("A missing parent module is reported too")
    func missingParentError() async {
        await #expect(throws: MTLModuleResolutionError.self) {
            _ = try await Self.load("extendsmissing.mtl")
        }
    }

    @Test("Cyclic imports are detected")
    func cycleDetection() async {
        do {
            _ = try await Self.load("cyclic/a.mtl")
            Issue.record("Expected an error")
        } catch let error as MTLModuleResolutionError {
            guard case .cycle(let path) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(path.count == 3)
            #expect(path.first == path.last)
            #expect(error.errorDescription?.contains("Cyclic") == true)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    // MARK: - Search Paths

    @Test("Configured search paths locate modules outside the importing directory")
    @MainActor
    func searchPaths() async throws {
        let root = Self.fixture("searchroot")
        let module = try await Self.load("importsvendor.mtl", searchPaths: [root])
        #expect(module.importedModules.map(\.name) == ["shared"])
        #expect(try await MTLTestSupport.output(module: module) == "search path")
    }

    @Test("Without the search path the import is not found")
    func searchPathRequired() async {
        await #expect(throws: MTLModuleResolutionError.self) {
            _ = try await Self.load("importsvendor.mtl")
        }
    }

    @Test("The importing directory wins over the search paths")
    @MainActor
    func relativeWins() async throws {
        let module = try await Self.load("dup/importer.mtl", searchPaths: [Self.fixture("searchroot")])
        #expect(try await MTLTestSupport.output(module: module) == "relative")
    }

    // MARK: - Imports

    @Test("Imported public templates and queries can be called")
    @MainActor
    func importedElements() async throws {
        let module = try await Self.load("main.mtl")
        #expect(module.imports == ["common::naming", "util"])
        #expect(module.importedModules.map(\.name) == ["naming", "util"])
        #expect(try await MTLTestSupport.output(module: module) == "<x> Y! zz hidden\n")
    }

    @Test("Private elements of an imported module are not visible")
    @MainActor
    func importedPrivate() async throws {
        let module = try await Self.load("main.mtl")
        await #expect(throws: (any Error).self) {
            _ = try await MTLTestSupport.output(module: module, main: "readsPrivate")
        }
    }

    @Test("Protected elements are not visible through an import")
    @MainActor
    func importedProtected() async throws {
        let module = try await Self.load("main.mtl")
        await #expect(throws: (any Error).self) {
            _ = try await MTLTestSupport.output(module: module, main: "readsProtected")
        }
    }

    @Test("Imports are not transitive")
    @MainActor
    func importsNotTransitive() async throws {
        let module = try await Self.load("transitive.mtl")
        #expect(try await MTLTestSupport.output(module: module, main: "viaMiddle") == "mm")
        await #expect(throws: (any Error).self) {
            _ = try await MTLTestSupport.output(module: module, main: "main")
        }
    }

    @Test("A module imported twice is loaded once and works from both places")
    @MainActor
    func diamondImports() async throws {
        let module = try await Self.load("diamond.mtl")
        #expect(module.importedModules.count == 2)
        #expect(try await MTLTestSupport.output(module: module) == "llrr")
    }

    @Test("Source text can be linked against a base location")
    @MainActor
    func linkingSource() async throws {
        let parser = MTLParser()
        let parsed = try await parser.parse("""
            [module adhoc('u')/]
            [import util/]
            [template main()][twice('q')/][/template]
            """)
        #expect(parsed.importedModules.isEmpty)
        let linked = try await parser.link(parsed, relativeTo: Self.fixture("adhoc.mtl"))
        #expect(try await MTLTestSupport.output(module: linked) == "qq")
    }

    @Test("Unlinked modules fail with a clear error when calling an import")
    @MainActor
    func unlinkedImport() async throws {
        let parsed = try await MTLTestSupport.parse("""
            [module adhoc('u')/]
            [import util/]
            [template main()][twice('q')/][/template]
            """)
        await #expect(throws: (any Error).self) {
            _ = try await MTLTestSupport.output(module: parsed)
        }
    }

    @Test("The loader loads a file with its dependencies")
    func loaderLoads() async throws {
        let loader = MTLModuleLoader(resolver: MTLModuleResolver())
        let module = try await loader.load(Self.fixture("main.mtl"))
        #expect(module.location?.lastPathComponent == "main.mtl")
        #expect(module.importedModules.allSatisfy { $0.location != nil })
    }

    @Test("Parsing without linking leaves the imports unloaded")
    func parseWithoutLinking() async throws {
        let module = try await MTLParser().parseWithoutLinking(Self.fixture("main.mtl"))
        #expect(module.importedModules.isEmpty)
        #expect(module.imports.count == 2)
        #expect(module.location != nil)
    }

    // MARK: - Extends and Overriding

    @Test("The parent module is loaded and attached")
    func parentLoaded() async throws {
        let module = try await Self.load("derived.mtl")
        #expect(module.extends == "base")
        #expect(module.extendedModule?.name == "base")
        #expect(module.inheritanceChain.map(\.name) == ["derived", "base"])
    }

    @Test("Inherited templates are callable and calls dispatch to the override")
    @MainActor
    func overrideDispatch() async throws {
        let module = try await Self.load("derived.mtl")
        #expect(try await MTLTestSupport.output(module: module) == "Howdy Pat! derived label")
    }

    @Test("The base module on its own uses its own templates")
    @MainActor
    func baseOnly() async throws {
        let module = try await Self.load("base.mtl")
        #expect(try await MTLTestSupport.output(module: module, main: "baseMain") == "Hello Sam!")
        #expect(try await MTLTestSupport.output(module: module, main: "describe") == "base")
    }

    @Test("A main template of the base module can run through the derived module")
    @MainActor
    func baseMainThroughDerived() async throws {
        let module = try await Self.load("derived.mtl")
        #expect(try await MTLTestSupport.output(module: module, main: "baseMain") == "Howdy Sam!")
    }

    @Test("Private elements of the parent module are not visible")
    @MainActor
    func parentPrivate() async throws {
        let module = try await Self.load("derived.mtl")
        await #expect(throws: (any Error).self) {
            _ = try await MTLTestSupport.output(module: module, main: "readsHidden")
        }
    }

    @Test("Overriding templates record what they override")
    func overridesRecorded() async throws {
        let module = try await Self.load("derived.mtl")
        #expect(module.templates["greet"]?.overrides == "greet")
    }
}

extension MTLTestSupport {

    /// Runs a template of a parsed module and returns the standard output.
    @MainActor
    static func output(module: MTLModule, main: String = "main") async throws -> String {
        try await run(module, main: main)[standardOutput] ?? ""
    }
}
