//
//  MTLModuleSourceTests.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import MTL

/// A module source that serves modules from a dictionary and records its requests.
private actor DictionarySource: MTLModuleSource {
    struct Request: Equatable {
        let module: String
        let importedFrom: String?
    }

    private let modules: [String: String]
    private(set) var requests: [Request] = []

    init(_ modules: [String: String]) {
        self.modules = modules
    }

    func source(forModule module: String, importedFrom: String?) async throws -> (text: String, location: String)? {
        requests.append(Request(module: module, importedFrom: importedFrom))
        guard let text = modules[module] else { return nil }
        return (text, "memory:\(module)")
    }
}

/// A module source that always fails.
private struct FailingSource: MTLModuleSource {
    struct Failure: Error {}

    func source(forModule module: String, importedFrom: String?) async throws -> (text: String, location: String)? {
        throw Failure()
    }
}

@Suite("MTL module sources")
struct MTLModuleSourceTests {

    private func module(_ name: String, _ body: String = "", imports: [String] = [], extends: String? = nil) -> String {
        let parent = extends.map { " extends \($0)" } ?? ""
        let declarations = imports.map { "[import \($0)/]\n" }.joined()
        return "[module \(name)('u')\(parent)/]\n\(declarations)\(body)"
    }

    private func link(
        _ text: String, source: any MTLModuleSource, searchPaths: [URL] = []
    ) async throws -> MTLModule {
        let parser = MTLParser(searchPaths: searchPaths, moduleSource: source)
        let parsed = try await parser.parse(text, filename: "main.mtl")
        return try await parser.link(parsed)
    }

    @Test("Imports resolve entirely in memory")
    func imports() async throws {
        let source = DictionarySource([
            "lib": module("lib", "[template public greet()]hello[/template]\n")
        ])
        let linked = try await link(module("main", imports: ["lib"]), source: source)
        let imported = try #require(linked.importedModules.first)
        #expect(imported.name == "lib")
        #expect(imported.templates["greet"] != nil)
    }

    @Test("A parent module resolves in memory")
    func extends() async throws {
        let source = DictionarySource(["base": module("base", "[template public t()]b[/template]\n")])
        let linked = try await link(module("main", extends: "base"), source: source)
        #expect(linked.extendedModule?.name == "base")
    }

    @Test("Nested imports report where they were imported from")
    func nested() async throws {
        let source = DictionarySource([
            "a": module("a", imports: ["b"]),
            "b": module("b"),
        ])
        let linked = try await link(module("main", imports: ["a"]), source: source)
        #expect(linked.importedModules.first?.importedModules.first?.name == "b")
        let requests = await source.requests
        #expect(requests == [
            .init(module: "a", importedFrom: nil),
            .init(module: "b", importedFrom: "memory:a"),
        ])
    }

    @Test("A module imported twice is linked once for each importer")
    func caching() async throws {
        let source = DictionarySource([
            "a": module("a", imports: ["c"]),
            "b": module("b", imports: ["c"]),
            "c": module("c"),
        ])
        let linked = try await link(module("main", imports: ["a", "b"]), source: source)
        #expect(linked.importedModules.compactMap { $0.importedModules.first?.name } == ["c", "c"])
    }

    @Test("Cycles between source modules are reported")
    func cycles() async throws {
        let source = DictionarySource([
            "a": module("a", imports: ["b"]),
            "b": module("b", imports: ["a"]),
        ])
        do {
            _ = try await link(module("main", imports: ["a"]), source: source)
            Issue.record("Expected a cycle")
        } catch let error as MTLModuleResolutionError {
            guard case .cycle(let path) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(path.first == path.last)
        }
    }

    @Test("A module the source does not know is reported as missing")
    func missing() async {
        let source = DictionarySource([:])
        await #expect(throws: MTLModuleResolutionError.self) {
            _ = try await link(module("main", imports: ["nowhere"]), source: source)
        }
    }

    @Test("Modules the source does not know are found in the search paths")
    func fallsBackToFiles() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtl-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try module("onDisk", "[template public t()]d[/template]\n")
            .write(to: directory.appendingPathComponent("onDisk.mtl"), atomically: testWritesAtomically, encoding: .utf8)

        let source = DictionarySource(["lib": module("lib")])
        let linked = try await link(
            module("main", imports: ["lib", "onDisk"]), source: source, searchPaths: [directory])
        #expect(linked.importedModules.map(\.name) == ["lib", "onDisk"])
    }

    @Test("The source takes precedence over files")
    func precedence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtl-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try module("lib", "[template public fromDisk()]d[/template]\n")
            .write(to: directory.appendingPathComponent("lib.mtl"), atomically: testWritesAtomically, encoding: .utf8)

        let source = DictionarySource(["lib": module("lib", "[template public fromMemory()]m[/template]\n")])
        let linked = try await link(module("main", imports: ["lib"]), source: source, searchPaths: [directory])
        #expect(linked.importedModules.first?.templates["fromMemory"] != nil)
    }

    @Test("Errors thrown by the source propagate")
    func failures() async {
        await #expect(throws: FailingSource.Failure.self) {
            _ = try await link(module("main", imports: ["x"]), source: FailingSource())
        }
    }

    @Test("Syntax errors in a source module are reported")
    func syntaxErrors() async {
        let source = DictionarySource(["bad": module("bad", "[template (]")])
        await #expect(throws: MTLParseError.self) {
            _ = try await link(module("main", imports: ["bad"]), source: source)
        }
    }

    @Test("The loader accepts a source directly")
    func loader() async throws {
        let source = DictionarySource(["lib": module("lib")])
        let loader = MTLModuleLoader(moduleSource: source)
        let parsed = try await MTLParser().parse(module("main", imports: ["lib"]), filename: "m.mtl")
        let linked = try await loader.link(parsed)
        #expect(linked.importedModules.count == 1)
    }

    @Test("Generation can use templates imported from memory")
    @MainActor
    func generation() async throws {
        let source = DictionarySource([
            "lib": module("lib", "[template public greet()]hello[/template]\n")
        ])
        let linked = try await link(
            module("main", "[template main()][greet()/][/template]", imports: ["lib"]), source: source)
        let files = try await MTLTestSupport.run(linked)
        #expect(files[MTLTestSupport.standardOutput] == "hello")
    }
}

@Suite("MTL file reads through the strategy")
struct MTLStrategyReadTests {

    private let area = """
        generated
        // START PROTECTED REGION keep
        user code
        // END PROTECTED REGION keep
        """

    @Test("The protected area manager scans a file through the strategy")
    @MainActor
    func scanThroughStrategy() async throws {
        let strategy = MTLInMemoryStrategy()
        await strategy.setFile(area, at: "src/File.swift")
        let manager = MTLProtectedAreaManager()
        try await manager.scanFile("src/File.swift", using: strategy)
        #expect(await manager.getContent("keep")?.contains("user code") == true)
    }

    @Test("A target the strategy does not know is skipped")
    @MainActor
    func missingTarget() async throws {
        let manager = MTLProtectedAreaManager()
        try await manager.scanFile("none.txt", using: MTLInMemoryStrategy())
        #expect(await manager.getAllContent().isEmpty)
    }

    @Test("The execution context scans files through its strategy")
    @MainActor
    func contextScan() async throws {
        let strategy = MTLInMemoryStrategy()
        await strategy.setFile(area, at: "src/File.swift")
        let module = try await MTLTestSupport.parse("[module m('u')/]\n[template main()]x[/template]")
        let context = MTLExecutionContext(module: module, generationStrategy: strategy)
        try await context.scanFileForProtectedAreas("src/File.swift")
        #expect(await context.protectedAreas.getContent("keep")?.contains("user code") == true)
    }

    @Test("Charsets decode the existing content of a strategy target")
    @MainActor
    func charsetThroughStrategy() async throws {
        let strategy = MTLInMemoryStrategy()
        await strategy.setFile("text", at: "a.txt")
        #expect(await MTLCharset.utf8.read(url: "a.txt", from: strategy) == "text")
        #expect(await MTLCharset.utf8.read(url: "b.txt", from: strategy) == nil)
        #expect(await MTLCharset.readDetecting(url: "a.txt", from: strategy) == "text")
    }

    @Test("Charsets decode bytes without touching the disk")
    func decodeDetecting() {
        #expect(MTLCharset.detectingDecode(Data([0xFE, 0xFF, 0x00, 0x41])) == "A")
        #expect(MTLCharset.detectingDecode(Data([0xFF, 0xFE, 0x41, 0x00])) == "A")
        #expect(MTLCharset.detectingDecode(Data("é".utf8)) == "é")
        #expect(MTLCharset.detectingDecode(Data([0xE9])) == "é")
    }
}
