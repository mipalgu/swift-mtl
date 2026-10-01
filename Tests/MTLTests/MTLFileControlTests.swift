//
//  MTLFileControlTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import MTL

/// The generation strategies the file control tests run against.
enum FileControlStrategy: String, CaseIterable, CustomTestStringConvertible {
    case inMemory
    case fileSystem

    var testDescription: String { rawValue }
}

/// Runs templates against one strategy and reads the results back.
struct FileControlHarness {
    let kind: FileControlStrategy
    let directory: TemporaryDirectory
    let memory: MTLInMemoryStrategy
    let options: MTLGeneratorOptions

    init(_ kind: FileControlStrategy, options: MTLGeneratorOptions = MTLGeneratorOptions()) throws {
        self.kind = kind
        self.options = options
        self.memory = MTLInMemoryStrategy(options: options)
        self.directory = try TemporaryDirectory()
    }

    /// Puts a file in place before generation.
    func seed(_ path: String, _ content: String) async throws {
        switch kind {
        case .inMemory:
            await memory.setFile(content, at: path)
        case .fileSystem:
            let target = directory.file(path)
            try FileManager.default.createDirectory(
                atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try content.write(toFile: target, atomically: true, encoding: .utf8)
        }
    }

    /// Runs the `main` template of a module source.
    @MainActor
    func generate(_ source: String) async throws {
        let module = try await MTLParser().parse(source)
        let strategy: any MTLGenerationStrategy =
            kind == .inMemory ? memory : MTLFileSystemStrategy(basePath: directory.path, options: options)
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
    }

    /// Reads a file as UTF-8 text, or nil if it does not exist.
    func text(_ path: String) async -> String? {
        switch kind {
        case .inMemory:
            return await memory.getGeneratedFiles()[path]
        case .fileSystem:
            return try? String(contentsOfFile: directory.file(path), encoding: .utf8)
        }
    }

    /// Reads the bytes of a file on disk.
    func bytes(_ path: String) -> [UInt8]? {
        FileManager.default.contents(atPath: directory.file(path)).map { [UInt8]($0) }
    }
}

@Suite("MTL File Control: create mode")
struct MTLCreateModeTests {

    private let source = """
        [module T('u')]
        [template main()]
        [file ('keep.txt', 'create')]new[/file]
        [file ('fresh.txt', create)]fresh[/file]
        [/template]
        """

    @Test("An existing file is left untouched without an error", arguments: FileControlStrategy.allCases)
    @MainActor
    func skipsExisting(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("keep.txt", "original")
        try await harness.generate(source)
        #expect(await harness.text("keep.txt") == "original")
        #expect(await harness.text("fresh.txt") == "fresh")
    }

    @Test("A missing file is written", arguments: FileControlStrategy.allCases)
    @MainActor
    func writesMissing(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.generate(source)
        #expect(await harness.text("keep.txt") == "new")
    }

    @Test("The skipped body is not evaluated", arguments: FileControlStrategy.allCases)
    @MainActor
    func skippedBodyHasNoEffect(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("keep.txt", "original")
        try await harness.generate(
            """
            [module T('u')]
            [template main()]
            [file ('keep.txt', 'create')]body[file ('nested.txt')]n[/file][/file]
            [/template]
            """)
        #expect(await harness.text("keep.txt") == "original")
        #expect(await harness.text("nested.txt") == nil)
    }

    @Test("A computed create mode skips too", arguments: FileControlStrategy.allCases)
    @MainActor
    func computedMode(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("keep.txt", "original")
        try await harness.generate(
            "[module T('u')][template main()][file ('keep.txt', 'cre' + 'ate')]new[/file][/template]")
        #expect(await harness.text("keep.txt") == "original")
    }

    @Test("Writers created directly in create mode never replace a file", arguments: FileControlStrategy.allCases)
    @MainActor
    func directWriter(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("keep.txt", "original")
        let strategy: any MTLGenerationStrategy =
            kind == .inMemory ? harness.memory : MTLFileSystemStrategy(basePath: harness.directory.path)
        let writer = try await strategy.createWriter(
            url: "keep.txt", mode: .create, charset: "UTF-8", indentation: MTLIndentation())
        await writer.write("replacement", indent: false)
        try await strategy.finalizeWriter(writer)
        #expect(await harness.text("keep.txt") == "original")
    }
}

@Suite("MTL File Control: merge scope")
struct MTLMergeScopeTests {

    private static let existingJava = """
        package p;

        /**
         * @generated
         */
        public class Library {
            /**
             * @generated NOT
             */
            public int a() { return 42; }
        }

        """

    private static func template(
        mergeOptions: String = ", 'files=*.java'", javaFileOptions: String = ""
    ) -> String {
        """
        [module T('u')]
        [merge ('/**', '*/', '@generated', '@generated NOT', 'braces'\(mergeOptions))/]
        [template main()]
        [file ('src/Library.java', 'overwrite', 'UTF-8'\(javaFileOptions))]
        package p;

        /**
         * @generated
         */
        public class Library {
            /**
             * @generated
             */
            public int a() { return 1; }
        }
        [/file]
        [file ('plugin.xml', 'overwrite', 'UTF-8')]
        <plugin/>
        [/file]
        [/template]
        """
    }

    @Test("Only files matching the patterns are merged", arguments: FileControlStrategy.allCases)
    @MainActor
    func scopedToPatterns(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("src/Library.java", Self.existingJava)
        try await harness.seed("plugin.xml", "<plugin>old { content } here</plugin>\n")
        try await harness.generate(Self.template())
        #expect(await harness.text("src/Library.java")?.contains("return 42") == true)
        #expect(await harness.text("plugin.xml") == "<plugin/>\n")
    }

    @Test("Without patterns the merge applies to every file", arguments: FileControlStrategy.allCases)
    @MainActor
    func unscoped(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("src/Library.java", Self.existingJava)
        try await harness.generate(Self.template(mergeOptions: ""))
        #expect(await harness.text("src/Library.java")?.contains("return 42") == true)
    }

    @Test("A file option disables merging for one file", arguments: FileControlStrategy.allCases)
    @MainActor
    func perFileOption(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("src/Library.java", Self.existingJava)
        try await harness.generate(Self.template(javaFileOptions: ", 'merge=false'"))
        #expect(await harness.text("src/Library.java")?.contains("return 1;") == true)
        #expect(await harness.text("src/Library.java")?.contains("return 42") == false)
    }

    @Test("An explicit merge=true file option keeps merging")
    @MainActor
    func explicitTrue() async throws {
        let harness = try FileControlHarness(.inMemory)
        try await harness.seed("src/Library.java", Self.existingJava)
        try await harness.generate(Self.template(javaFileOptions: ", 'merge=true'"))
        #expect(await harness.text("src/Library.java")?.contains("return 42") == true)
    }

    @Test("The merge declaration records its file patterns")
    func parsesPatterns() async throws {
        let module = try await MTLParser().parse(
            "[module T('u')]\n[merge ('/**', '*/', '@generated', 'NOT', 'files=*.java src/**/*.txt')/]")
        let configuration = try #require(module.mergeConfiguration)
        #expect(configuration.filePatterns == ["*.java", "src/**/*.txt"])
        #expect(configuration.applies(toFile: "a/B.java"))
        #expect(configuration.applies(toFile: "src/x/y/z.txt"))
        #expect(!configuration.applies(toFile: "plugin.xml"))
    }

    @Test("A configuration without patterns applies to every file")
    func noPatterns() {
        let configuration = MTLMergeConfiguration(
            commentStart: "/**", commentEnd: "*/", generatedTag: "@generated", keepTag: "NOT")
        #expect(configuration.filePatterns.isEmpty)
        #expect(configuration.applies(toFile: "anything.xml"))
    }

    @Test("Glob patterns match as documented", arguments: [
        ("*.java", "Library.java", true),
        ("*.java", "src/Library.java", true),
        ("*.java", "Library.javax", false),
        ("*.java", "src.java/Library.xml", false),
        ("src/*.java", "src/Library.java", true),
        ("src/*.java", "src/sub/Library.java", false),
        ("src/**.java", "src/sub/Library.java", true),
        ("src/**/*.java", "src/sub/Library.java", true),
        ("Lib?.java", "Lib1.java", true),
        ("Lib?.java", "Lib12.java", false),
        ("Lib?", "Lib/", false),
        ("MANIFEST.MF", "META-INF/MANIFEST.MF", true),
        ("*", "", true),
    ])
    func globs(pattern: String, url: String, expected: Bool) {
        #expect(MTLFileGlob.matches(pattern: pattern, url: url) == expected)
    }

    @Test("Malformed merge and file options are rejected", arguments: [
        "[merge ('/**', '*/', '@generated', 'NOT', 'files= ')/]",
        "[template main()][file ('a', 'overwrite', 'UTF-8', 'merge=maybe')]x[/file][/template]",
        "[template main()][file ('a', 'overwrite', 'UTF-8', 'colour=red')]x[/file][/template]",
        "[template main()][file ('a', 'overwrite', 'UTF-8', 'merge')]x[/file][/template]",
        "[template main()][file ('a', 'overwrite', 'UTF-8', 5)]x[/file][/template]",
    ])
    func rejectsMalformed(declaration: String) async {
        await #expect(throws: (any Error).self) {
            _ = try await MTLParser().parse("[module T('u')]\n\(declaration)")
        }
    }

    @Test("File options are recorded on the statement and compare by value")
    func fileOptions() {
        #expect(MTLFileOptions().merge)
        #expect(MTLFileOptions(merge: false) != MTLFileOptions())
        #expect(MTLFileOptionKeys.all == [MTLFileOptionKeys.merge])
    }
}

@Suite("MTL File Control: services")
struct MTLFileServiceTests {

    @Test("fileExists reflects the generation base path", arguments: FileControlStrategy.allCases)
    @MainActor
    func fileExists(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("sub/plugin.xml", "<plugin/>")
        try await harness.generate(
            """
            [module T('u')]
            [template main()]
            [file ('result.txt')]
            [fileExists('sub/plugin.xml')/] [fileExists('plugin.xml')/] [fileExists('sub')/]
            [/file]
            [/template]
            """)
        #expect(await harness.text("result.txt")?.hasPrefix("true false") == true)
    }

    @Test("A template can write a file only while another is missing", arguments: FileControlStrategy.allCases)
    @MainActor
    func conditionalFile(kind: FileControlStrategy) async throws {
        let source = """
            [module T('u')]
            [template main()]
            [if (not fileExists('plugin.xml'))]
            [file ('build.properties')]bin.includes = plugin.xml[/file]
            [/if]
            [/template]
            """
        let without = try FileControlHarness(kind)
        defer { without.directory.remove() }
        try await without.generate(source)
        #expect(await without.text("build.properties") == "bin.includes = plugin.xml")

        let with = try FileControlHarness(kind)
        defer { with.directory.remove() }
        try await with.seed("plugin.xml", "<plugin/>")
        try await with.generate(source)
        #expect(await with.text("build.properties") == nil)
    }

    @Test("fileExists sees files written earlier in the same run", arguments: FileControlStrategy.allCases)
    @MainActor
    func writtenEarlier(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.generate(
            """
            [module T('u')]
            [template main()]
            [file ('a.txt')]a[/file]
            [file ('b.txt')][fileExists('a.txt')/][/file]
            [/template]
            """)
        #expect(await harness.text("b.txt") == "true")
    }

    @Test("forceOverwrite returns the generator option", arguments: FileControlStrategy.allCases, [false, true])
    @MainActor
    func forceOverwrite(kind: FileControlStrategy, forced: Bool) async throws {
        let harness = try FileControlHarness(kind, options: MTLGeneratorOptions(forceOverwrite: forced))
        defer { harness.directory.remove() }
        try await harness.generate(
            "[module T('u')][template main()][file ('o.txt')][forceOverwrite()/][/file][/template]")
        #expect(await harness.text("o.txt") == "\(forced)")
    }

    @Test("A strategy without options reports the defaults")
    @MainActor
    func defaultOptions() async {
        struct Minimal: MTLGenerationStrategy {
            func createWriter(url: String, mode: MTLOpenMode, charset: String, indentation: MTLIndentation)
                async throws -> MTLWriter
            { MTLWriter(indentation: indentation) }
            func finalizeWriter(_ writer: MTLWriter) async throws {}
        }
        let strategy = Minimal()
        #expect(strategy.generatorOptions == MTLGeneratorOptions())
        #expect(await strategy.fileExists(url: "x") == false)
    }

    @Test("Templates may override the built-in services")
    @MainActor
    func overridable() async throws {
        let files = try await MTLTestSupport.run(
            """
            [module T('u')]
            [query public fileExists(p : String) : Boolean = 'overridden' /]
            [template main()][fileExists('x')/][/template]
            """)
        #expect(files[MTLTestSupport.standardOutput] == "overridden")
    }

    @Test("The service names are defined once")
    func names() {
        #expect(MTLFileServiceNames.fileExists == "fileExists")
        #expect(MTLFileServiceNames.forceOverwrite == "forceOverwrite")
    }
}

@Suite("MTL File Control: charset")
struct MTLCharsetTests {

    private static func template(charset: String, text: String, mode: String = "overwrite") -> String {
        "[module T('u')][template main()][file ('c.txt', '\(mode)', '\(charset)')]\(text)[/file][/template]"
    }

    @Test("Charset names resolve flexibly", arguments: [
        ("UTF-8", MTLCharset.utf8), ("utf8", .utf8), ("UTF-16", .utf16), ("UTF-16BE", .utf16BigEndian),
        ("utf_16le", .utf16LittleEndian), ("ISO-8859-1", .latin1), ("Latin-1", .latin1),
        ("iso_8859_1", .latin1), ("US-ASCII", .ascii), ("ascii", .ascii),
    ])
    func names(name: String, expected: MTLCharset) {
        #expect(MTLCharset(name: name) == expected)
    }

    @Test("Unknown charsets are rejected before generating", arguments: FileControlStrategy.allCases)
    @MainActor
    func unknown(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        await #expect(throws: MTLExecutionError.self) {
            try await harness.generate(Self.template(charset: "EBCDIC", text: "x"))
        }
        #expect(MTLCharset(name: "EBCDIC") == nil)
    }

    @Test("ISO-8859-1 files hold one byte per character")
    @MainActor
    func latin1() async throws {
        let harness = try FileControlHarness(.fileSystem)
        defer { harness.directory.remove() }
        try await harness.generate(Self.template(charset: "ISO-8859-1", text: "caf\u{E9}"))
        #expect(harness.bytes("c.txt") == [0x63, 0x61, 0x66, 0xE9])
    }

    @Test("UTF-16 files start with a big-endian byte order mark")
    @MainActor
    func utf16() async throws {
        let harness = try FileControlHarness(.fileSystem)
        defer { harness.directory.remove() }
        try await harness.generate(Self.template(charset: "UTF-16", text: "A\u{E9}"))
        #expect(harness.bytes("c.txt") == [0xFE, 0xFF, 0x00, 0x41, 0x00, 0xE9])
    }

    @Test("UTF-16 variants without a byte order mark")
    @MainActor
    func utf16Variants() async throws {
        let harness = try FileControlHarness(.fileSystem)
        defer { harness.directory.remove() }
        try await harness.generate(Self.template(charset: "UTF-16LE", text: "A"))
        #expect(harness.bytes("c.txt") == [0x41, 0x00])
        try await harness.generate(Self.template(charset: "UTF-16BE", text: "A"))
        #expect(harness.bytes("c.txt") == [0x00, 0x41])
    }

    @Test("ASCII files and UTF-8 files are written as before")
    @MainActor
    func asciiAndUTF8() async throws {
        let harness = try FileControlHarness(.fileSystem)
        defer { harness.directory.remove() }
        try await harness.generate(Self.template(charset: "US-ASCII", text: "abc"))
        #expect(harness.bytes("c.txt") == [0x61, 0x62, 0x63])
        try await harness.generate(Self.template(charset: "UTF-8", text: "\u{E9}\u{20AC}"))
        #expect(harness.bytes("c.txt") == [0xC3, 0xA9, 0xE2, 0x82, 0xAC])
    }

    @Test("The default charset is UTF-8", arguments: FileControlStrategy.allCases)
    @MainActor
    func defaultCharset(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.generate("[module T('u')][template main()][file ('c.txt')]\u{20AC}[/file][/template]")
        #expect(await harness.text("c.txt") == "\u{20AC}")
    }

    @Test("Unrepresentable characters are an error naming the character and file",
        arguments: FileControlStrategy.allCases, [("US-ASCII", "caf\u{E9}", "U+00E9"), ("ISO-8859-1", "\u{20AC}", "U+20AC")])
    @MainActor
    func unrepresentable(kind: FileControlStrategy, case sample: (String, String, String)) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        do {
            try await harness.generate(Self.template(charset: sample.0, text: sample.1))
            Issue.record("Expected an error")
        } catch let MTLExecutionError.fileError(message) {
            #expect(message.contains(sample.2))
            #expect(message.contains("c.txt"))
        }
        #expect(await harness.text("c.txt") == nil)
    }

    @Test("Existing files are read in their charset when appending")
    @MainActor
    func appendsInCharset() async throws {
        let harness = try FileControlHarness(.fileSystem)
        defer { harness.directory.remove() }
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: URL(fileURLWithPath: harness.directory.file("c.txt")))
        try await harness.generate(Self.template(charset: "ISO-8859-1", text: "!", mode: "append"))
        #expect(harness.bytes("c.txt") == [0x63, 0x61, 0x66, 0xE9, 0x21])
    }

    @Test("Encoding and decoding round-trip", arguments: [
        MTLCharset.utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .latin1,
    ])
    func roundTrip(charset: MTLCharset) throws {
        let data = try charset.encode("na\u{EF}ve", path: "x")
        #expect(charset.decode(data) == "na\u{EF}ve")
    }

    @Test("Files of unknown charset are read by detection", arguments: FileControlStrategy.allCases)
    func detection(kind: FileControlStrategy) throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let cases: [(String, [UInt8], String)] = [
            ("utf8", [0xC3, 0xA9], "\u{E9}"),
            ("latin1", [0xE9], "\u{E9}"),
            ("utf16be", [0xFE, 0xFF, 0x00, 0xE9], "\u{E9}"),
            ("utf16le", [0xFF, 0xFE, 0xE9, 0x00], "\u{E9}"),
        ]
        for (name, bytes, expected) in cases {
            let path = directory.file(name)
            try Data(bytes).write(to: URL(fileURLWithPath: path))
            #expect(MTLCharset.readDetecting(atPath: path) == expected)
        }
        #expect(MTLCharset.readDetecting(atPath: directory.file("missing")) == nil)
        #expect(MTLCharset.utf8.read(atPath: directory.file("missing")) == nil)
    }
}
