//
//  MTLSourceEncodingTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase
import Foundation
import Testing

@testable import MTL

/// Tests for the character encodings in which module files are read.
///
/// A module file is read as UTF-8; a file that is not valid UTF-8 is read as ISO-8859-1 with
/// a warning, and an explicit encoding is used alone, for the main module and for the
/// modules it imports alike.
@Suite("MTL source encodings")
struct MTLSourceEncodingTests {
    /// The main module, which imports ``library``.
    static let main = """
        [module main('http://example.com/main')/]
        [import library/]
        [comment Café /]
        [template public main()]Café [greeting()/][/template]

        """

    /// The imported module.
    static let library = """
        [module library('http://example.com/library')/]
        [template public greeting()]Grüße[/template]

        """

    /// What the main template writes.
    static let output = "Café Grüße"

    /// Encodes text in ISO-8859-1.
    ///
    /// - Parameter text: Text whose characters are all below U+0100.
    /// - Returns: One byte per character.
    static func latin1(_ text: String) -> Data {
        Data(text.unicodeScalars.map { UInt8($0.value) })
    }

    /// Writes the two modules to a new temporary directory.
    ///
    /// - Parameters:
    ///   - main: The bytes of the main module.
    ///   - library: The bytes of the imported module.
    /// - Returns: The location of the main module.
    /// - Throws: Any error writing the files.
    static func write(main: Data, library: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try library.write(to: directory.appendingPathComponent("library.mtl"))
        let url = directory.appendingPathComponent("main.mtl")
        try main.write(to: url)
        return url
    }

    /// Runs the main template of a module.
    @MainActor
    static func run(_ module: MTLModule) async throws -> String {
        try await MTLTestSupport.run(module)[MTLTestSupport.standardOutput] ?? ""
    }

    @Test("reads UTF-8 modules without a warning")
    @MainActor
    func utf8() async throws {
        let url = try Self.write(main: Data(Self.main.utf8), library: Data(Self.library.utf8))
        let parser = MTLParser()

        let module = try await parser.parse(url)

        #expect(try await Self.run(module).contains(Self.output))
        #expect(await parser.decodingWarnings.isEmpty)
    }

    @Test("reads modules that are not UTF-8 as ISO-8859-1, with a warning for each file")
    @MainActor
    func latin1Fallback() async throws {
        let url = try Self.write(main: Self.latin1(Self.main), library: Self.latin1(Self.library))
        let parser = MTLParser()

        let module = try await parser.parse(url)

        #expect(try await Self.run(module).contains(Self.output))
        let warnings = await parser.decodingWarnings
        #expect(warnings.count == 2)
        #expect(warnings.allSatisfy { $0.code == TextDecodingDiagnostic.decodedAsISOLatin1 })
        let documents = Set(warnings.compactMap(\.document).map { URL(string: $0)?.lastPathComponent })
        #expect(documents == ["main.mtl", "library.mtl"])
    }

    @Test("reads only the files that are not UTF-8 as ISO-8859-1")
    @MainActor
    func mixedEncodings() async throws {
        let url = try Self.write(main: Data(Self.main.utf8), library: Self.latin1(Self.library))
        let parser = MTLParser()

        let module = try await parser.parse(url)

        #expect(try await Self.run(module).contains(Self.output))
        let warnings = await parser.decodingWarnings
        #expect(warnings.count == 1)
        #expect(warnings.first?.document.flatMap { URL(string: $0)?.lastPathComponent } == "library.mtl")
    }

    @Test("reads every module in an explicit encoding without a warning")
    @MainActor
    func explicitEncoding() async throws {
        let url = try Self.write(main: Self.latin1(Self.main), library: Self.latin1(Self.library))
        let parser = MTLParser(encoding: .isoLatin1)

        let module = try await parser.parse(url)

        #expect(try await Self.run(module).contains(Self.output))
        #expect(await parser.decodingWarnings.isEmpty)
    }

    @Test("rejects a module that is not valid in an explicit encoding")
    func malformedExplicitEncoding() async throws {
        let url = try Self.write(main: Data(Self.main.utf8), library: Self.latin1(Self.library))
        let parser = MTLParser(encoding: .utf8)

        await #expect {
            _ = try await parser.parse(url)
        } throws: { error in
            guard case MTLResourceError.loadError(let message) = error else { return false }
            return message.contains("library.mtl") && message.contains(TextEncoding.utf8.name)
        }
    }

    @Test("the loader reads modules in its encoding")
    @MainActor
    func loaderEncoding() async throws {
        let url = try Self.write(main: Self.latin1(Self.main), library: Self.latin1(Self.library))

        let module = try await MTLModuleLoader(encoding: .isoLatin1).load(url)

        #expect(try await Self.run(module).contains(Self.output))
    }

    @Test("parsing without linking reports the warning of the file")
    func withoutLinking() async throws {
        let url = try Self.write(main: Self.latin1(Self.main), library: Self.latin1(Self.library))
        let parser = MTLParser()

        let module = try await parser.parseWithoutLinking(url)

        #expect(module.name == "main")
        #expect(await parser.decodingWarnings.count == 1)
    }

    @Test("linking reports the warnings of the modules it reads")
    func linking() async throws {
        let url = try Self.write(main: Data(Self.main.utf8), library: Self.latin1(Self.library))
        let parser = MTLParser()
        let unlinked = try await MTLParser().parse(Self.main, filename: url.lastPathComponent)

        _ = try await parser.link(unlinked, relativeTo: url)

        #expect(await parser.decodingWarnings.count == 1)
    }

    @Test("forgets the warnings of an earlier file")
    func warningsOfLatestFile() async throws {
        let latin1 = try Self.write(main: Self.latin1(Self.main), library: Self.latin1(Self.library))
        let utf8 = try Self.write(main: Data(Self.main.utf8), library: Data(Self.library.utf8))
        let parser = MTLParser()

        _ = try await parser.parse(latin1)
        _ = try await parser.parse(utf8)

        #expect(await parser.decodingWarnings.isEmpty)
    }

    @Test("still reports a missing file as unreadable")
    func missingFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mtl")

        await #expect {
            _ = try await MTLParser().parse(url)
        } throws: { error in
            guard case MTLResourceError.loadError(let message) = error else { return false }
            return message == "Could not read file: \(url.path)"
        }
    }
}
