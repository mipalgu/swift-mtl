//
// MTLResourceServicesTests.swift
// MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation
import Testing

@testable import MTL

/// Tests for the services that give templates access to text resources.
@Suite("MTL Resource Services")
struct MTLResourceServicesTests {

    /// Creates a fresh directory for one test.
    ///
    /// - Returns: The URL of the new, empty directory.
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtl-resource-services-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes a text file below a directory, creating intermediate directories.
    ///
    /// - Parameters:
    ///   - text: The content to write.
    ///   - path: The path relative to the directory.
    ///   - directory: The directory to write into.
    private func write(_ text: String, to path: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test("Text is read verbatim from a root")
    func readsVerbatim() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "line one\n\tline two  \n\nlast line without break"
        try write(content, to: "headers/a.h", in: root)
        let services = MTLResourceServices(roots: [root])
        #expect(try services.text(at: "headers/a.h") == content)
        #expect(try services.exists("headers/a.h"))
        #expect(try !services.exists("headers/missing.h"))
    }

    @Test("Roots are searched in order")
    func rootOrder() throws {
        let first = try makeDirectory()
        let second = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try write("first", to: "shared.txt", in: first)
        try write("second", to: "shared.txt", in: second)
        try write("only second", to: "other.txt", in: second)
        let services = MTLResourceServices(roots: [first, second])
        #expect(try services.text(at: "shared.txt") == "first")
        #expect(try services.text(at: "other.txt") == "only second")
    }

    @Test("Directories are not resources")
    func directoriesAreNotResources() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("x", to: "dir/file.txt", in: root)
        let services = MTLResourceServices(roots: [root])
        #expect(try !services.exists("dir"))
        #expect(throws: MTLResourceServicesError.notFound("dir")) { try services.text(at: "dir") }
    }

    @Test("A missing resource is reported")
    func missingResource() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let services = MTLResourceServices(roots: [root])
        #expect(throws: MTLResourceServicesError.notFound("nothing.txt")) {
            try services.text(at: "nothing.txt")
        }
    }

    @Test("Paths must stay below the roots")
    func pathsStayBelowRoots() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let services = MTLResourceServices(roots: [root.appendingPathComponent("inner", isDirectory: true)])
        try write("secret", to: "outside.txt", in: root)
        for path in ["", "/etc/hosts", "../outside.txt", "a/../../outside.txt", "a/..", "\\x", "C:\\x", "C:x"] {
            #expect(throws: MTLResourceServicesError.invalidPath(path)) { try services.text(at: path) }
            #expect(throws: MTLResourceServicesError.invalidPath(path)) { try services.exists(path) }
        }
    }

    @Test("Text that is not UTF-8 is rejected")
    func invalidEncoding() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0xFF, 0xFE, 0x00, 0xC3]).write(to: root.appendingPathComponent("binary.bin"))
        let services = MTLResourceServices(roots: [root])
        #expect(throws: MTLResourceServicesError.notText("binary.bin")) { try services.text(at: "binary.bin") }
    }

    @Test("Errors describe the problem")
    func messages() {
        #expect(MTLResourceServicesError.invalidPath("../x").errorDescription?.contains("../x") == true)
        #expect(MTLResourceServicesError.notFound("a.h").errorDescription?.contains("a.h") == true)
        #expect(MTLResourceServicesError.notText("b.bin").errorDescription?.contains("UTF-8") == true)
    }

    @Test("The directory of a module is the first root")
    func moduleDirectoryRoot() async throws {
        let root = try makeDirectory()
        let extra = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: extra)
        }
        try write("[module m('u')/]\n[template main()][resourceText('r.txt')/][/template]\n", to: "m.mtl", in: root)
        try write("beside the module", to: "r.txt", in: root)
        try write("extra", to: "r.txt", in: extra)
        try write("extra only", to: "e.txt", in: extra)
        let module = try await MTLParser().parse(root.appendingPathComponent("m.mtl"))
        let services = MTLResourceServices(module: module, roots: [extra])
        #expect(services.roots.count == 2)
        #expect(try services.text(at: "r.txt") == "beside the module")
        #expect(try services.text(at: "e.txt") == "extra only")
    }

    @Test("A module without a location contributes no root")
    func moduleWithoutLocation() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/]\n[template main()][/template]")
        let services = MTLResourceServices(module: module)
        #expect(services.roots.isEmpty)
    }

    @Test("Templates write resource text verbatim and can test for it")
    @MainActor
    func templateServices() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("#ifndef A\n#define A\n\n    indented\n#endif\n", to: "inc/a.h", in: root)
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template main()]
            [file ('out/a.h', false, 'UTF-8')][resourceText('inc/a.h')/][/file]
            [if (resourceExists('inc/a.h'))]yes[/if]|[if (not resourceExists('inc/b.h'))]no[/if]
            [/template]
            """)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        generator.register(MTLResourceServices(roots: [root]))
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        let files = await strategy.getGeneratedFiles()
        #expect(files["out/a.h"] == "#ifndef A\n#define A\n\n    indented\n#endif\n")
        #expect(files[MTLTestSupport.standardOutput]?.contains("yes|no") == true)
    }

    @Test("A template reading a missing resource fails")
    @MainActor
    func templateMissingResource() async throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[template main()][resourceText('none.h')/][/template]")
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        generator.register(MTLResourceServices(roots: [root]))
        await #expect(throws: (any Error).self) {
            try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        }
    }
}
