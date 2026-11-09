//
//  MTLDefaultCharsetTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import MTL

/// Verifies the charset of `[file]` blocks that name none, and the windows-1252 charset.
@Suite("MTL File Control: default charset")
struct MTLDefaultCharsetTests {

    /// A module whose first file names no charset and whose second names UTF-8.
    private static let source = """
        [module T('u')][template main()][file ('plain.txt')]caf\u{E9}[/file]\
        [file ('named.txt', 'overwrite', 'UTF-8')]caf\u{E9}[/file][/template]
        """

    @Test("The default charset is UTF-8 unless the options name another")
    func defaultIsUTF8() {
        #expect(MTLGeneratorOptions().defaultCharset == MTLSyntax.defaultCharset)
        #expect(MTLSyntax.defaultCharset == "UTF-8")
    }

    @Test("A file that names no charset is written in the default charset of the options")
    @MainActor
    func optionsCharset() async throws {
        var options = MTLGeneratorOptions()
        options.defaultCharset = "ISO-8859-1"
        let harness = try FileControlHarness(.fileSystem, options: options)
        defer { harness.directory.remove() }
        try await harness.generate(Self.source)
        #expect(harness.bytes("plain.txt") == [0x63, 0x61, 0x66, 0xE9])
        #expect(harness.bytes("named.txt") == [0x63, 0x61, 0x66, 0xC3, 0xA9])
    }

    @Test("Without a default charset in the options, files are written in UTF-8 as before")
    @MainActor
    func unchangedDefault() async throws {
        let harness = try FileControlHarness(.fileSystem)
        defer { harness.directory.remove() }
        try await harness.generate(Self.source)
        #expect(harness.bytes("plain.txt") == [0x63, 0x61, 0x66, 0xC3, 0xA9])
    }

    @Test("windows-1252 is recognised by its names", arguments: ["windows-1252", "Windows-1252", "cp1252"])
    func windowsNames(name: String) {
        #expect(MTLCharset(name: name) == .windows1252)
    }

    @Test("windows-1252 files hold the euro sign in one byte and round-trip")
    @MainActor
    func windows1252() async throws {
        let harness = try FileControlHarness(.fileSystem)
        defer { harness.directory.remove() }
        try await harness.generate(
            "[module T('u')][template main()][file ('c.txt', 'overwrite', 'windows-1252')]5 \u{20AC}[/file][/template]")
        #expect(harness.bytes("c.txt") == [0x35, 0x20, 0x80])
        let data = try MTLCharset.windows1252.encode("na\u{EF}ve \u{20AC}", path: "x")
        #expect(MTLCharset.windows1252.decode(data) == "na\u{EF}ve \u{20AC}")
        #expect(MTLCharset.windows1252.textEncoding == .windows1252)
    }

    @Test("Decomposed characters are written precomposed in the single-byte charsets, and as they are in UTF-8")
    @MainActor
    func precomposes() async throws {
        var options = MTLGeneratorOptions()
        options.defaultCharset = "ISO-8859-1"
        let harness = try FileControlHarness(.fileSystem, options: options)
        defer { harness.directory.remove() }
        try await harness.generate(
            "[module T('u')][template main()][file ('c.txt')]cafe\u{301}[/file]"
                + "[file ('u.txt', 'overwrite', 'UTF-8')]cafe\u{301}[/file][/template]")
        #expect(harness.bytes("c.txt") == [0x63, 0x61, 0x66, 0xE9])
        #expect(harness.bytes("u.txt") == Array("cafe\u{301}".utf8))
        #expect(try Array(MTLCharset.windows1252.encode("e\u{301}", path: "x")) == [0xE9])
        #expect(try Array(MTLCharset.ascii.encode("plain", path: "x")) == Array("plain".utf8))
    }

    @Test("An unrepresentable character is reported with its line and column, and no file is written",
        arguments: FileControlStrategy.allCases)
    @MainActor
    func position(kind: FileControlStrategy) async throws {
        var options = MTLGeneratorOptions()
        options.defaultCharset = "US-ASCII"
        let harness = try FileControlHarness(kind, options: options)
        defer { harness.directory.remove() }
        do {
            try await harness.generate("[module T('u')][template main()][file ('c.txt')]first\nca\u{2603}[/file][/template]")
            Issue.record("Expected an error")
        } catch let MTLExecutionError.fileError(message) {
            #expect(message.contains("U+2603"))
            #expect(message.contains("line 2, column 3"))
            #expect(message.contains("c.txt"))
        }
        #expect(await harness.text("c.txt") == nil)
    }
}
