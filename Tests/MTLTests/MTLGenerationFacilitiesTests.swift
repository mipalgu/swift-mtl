//
//  MTLGenerationFacilitiesTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import MTL

/// A post-processor that appends a marker line, recording the paths it saw.
struct MarkerPostProcessor: MTLFilePostProcessor {
    let marker: String

    func process(_ content: String, path: String) async throws -> String {
        content + marker + "\n"
    }
}

/// A post-processor that always fails.
struct FailingPostProcessor: MTLFilePostProcessor {
    struct Failure: Error {}

    func process(_ content: String, path: String) async throws -> String {
        throw Failure()
    }
}

/// Creates a unique temporary directory and removes it afterwards.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtl-generation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    var path: String { url.path }

    func file(_ name: String) -> String {
        url.appendingPathComponent(name).path
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

private let javaModuleHeader = """
    [module Test('http://example.com')]
    [merge ('/**', '*/', '@generated', '@generated NOT', 'braces')/]
    """

private let javaTemplate = """
    \(javaModuleHeader)
    [template main()]
    [file ('Library.java', 'overwrite', 'UTF-8')]
    package p;

    [emit ('imports') separator('\\n')]import [item/];[/emit]

    /**
     * @generated
     */
    public class Library {
        /**
         * @generated
         */
        public int a() { return 1; }

        /**
         * @generated
         */
        public int b() { return 2; }
    }
    [collect ('imports', 'java.util.List')/]
    [/file]
    [/template]
    """

private let existingJava = """
    package p;

    import java.util.Set;

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

@Suite("MTL Merge Declaration Parsing")
struct MTLMergeParsingTests {

    @Test("A merge declaration is parsed into the module")
    func parsesDeclaration() async throws {
        let module = try await MTLParser().parse(
            "[module T('u')]\n[merge ('/**', '*/', '@generated', '@generated NOT', 'braces')/]\n[template main()][/template]"
        )
        let configuration = try #require(module.mergeConfiguration)
        #expect(configuration.commentStart == "/**")
        #expect(configuration.commentEnd == "*/")
        #expect(configuration.generatedTag == "@generated")
        #expect(configuration.keepTag == "@generated NOT")
        #expect(configuration.strategy == .braces)
    }

    @Test("The strategy defaults to braces and options override the syntax")
    func options() async throws {
        let module = try await MTLParser().parse(
            """
            [module T('u')]
            [merge ('///', '', '@generated', '@generated NOT', 'terminators=;\\n', 'lineComments=// #', 'blockComment=(* *)', 'quotes="', 'opener=[')/]
            """)
        let configuration = try #require(module.mergeConfiguration)
        #expect(configuration.strategy == .braces)
        #expect(configuration.syntax.terminators == [";", "\n"])
        #expect(configuration.syntax.lineComments.contains("#"))
        #expect(configuration.syntax.lineComments.contains("///"))
        #expect(configuration.syntax.blockComments.first == .init(start: "(*", end: "*)"))
        #expect(configuration.syntax.quotes == ["\""])
        #expect(configuration.syntax.opener == "[")
    }

    @Test("The indentation strategy is recognised")
    func indentation() async throws {
        let module = try await MTLParser().parse(
            "[module T('u')]\n[merge ('#', '', '@generated', '@generated NOT', 'indentation')/]")
        #expect(module.mergeConfiguration?.strategy == .indentation)
        #expect(module.mergeConfiguration?.syntax.opener == ":")
    }

    @Test("Malformed declarations are rejected", arguments: [
        "[merge ('/**', '*/', '@generated')/]",
        "[merge ('/**', '*/', '@generated', 'keep', 'recursion')/]",
        "[merge ('/**', '*/', '@generated', 'keep', 'braces', 'unknown=1')/]",
        "[merge ('/**', '*/', '@generated', 'keep', 'braces', 'noassignment')/]",
        "[merge ('/**', '*/', '@generated', 'keep', 'braces', 'blockComment=/*')/]",
        "[merge ('/**', '*/', '@generated', 'keep', 'braces', 'opener=ab')/]",
        "[merge ('/**', 5)/]",
        "[merge ('/**', '*/', '@generated', 'keep')/][merge ('/**', '*/', '@generated', 'keep')/]",
    ])
    func rejectsMalformed(declaration: String) async {
        await #expect(throws: (any Error).self) {
            _ = try await MTLParser().parse("[module T('u')]\n\(declaration)")
        }
    }

    @Test("Modules with different merge configurations differ")
    func equality() {
        let configuration = MTLMergeConfiguration(
            commentStart: "/**", commentEnd: "*/", generatedTag: "@generated", keepTag: "NOT")
        let first = MTLModule(name: "T", metamodels: [:], mergeConfiguration: configuration)
        let second = MTLModule(name: "T", metamodels: [:])
        #expect(first != second)
        #expect(first.hashValue != second.hashValue)
        #expect(first == MTLModule(name: "T", metamodels: [:], mergeConfiguration: configuration))
    }
}

@Suite("MTL Generation Options and Merge")
struct MTLGenerationFacilitiesTests {

    @Test("An existing file is merged when the module declares a merge")
    @MainActor
    func mergesExistingFile() async throws {
        let strategy = MTLInMemoryStrategy()
        await strategy.setFile(existingJava, at: "Library.java")
        let files = try await generateFiles(javaTemplate, strategy: strategy)
        let result = try #require(files["Library.java"])
        #expect(result.contains("return 42"))
        #expect(!result.contains("return 1;"))
        #expect(result.contains("return 2;"))
        #expect(result.contains("import java.util.List;"))
        #expect(result.contains("import java.util.Set;"))
        #expect(result.components(separatedBy: "class Library").count == 2)
    }

    @Test("A new file is written as generated")
    @MainActor
    func writesNewFile() async throws {
        let files = try await generateFiles(javaTemplate)
        let result = try #require(files["Library.java"])
        #expect(result.contains("return 1;"))
        #expect(result.contains("import java.util.List;"))
    }

    @Test("Regenerating a merged file changes nothing")
    @MainActor
    func mergeIsStable() async throws {
        let strategy = MTLInMemoryStrategy()
        await strategy.setFile(existingJava, at: "Library.java")
        let first = try await generateFiles(javaTemplate, strategy: strategy)
        let second = try await generateFiles(javaTemplate, strategy: strategy)
        #expect(first["Library.java"] == second["Library.java"])
    }

    @Test("Force overwrite replaces the file without merging")
    @MainActor
    func forceOverwrite() async throws {
        let strategy = MTLInMemoryStrategy(options: MTLGeneratorOptions(forceOverwrite: true))
        await strategy.setFile(existingJava, at: "Library.java")
        let files = try await generateFiles(javaTemplate, strategy: strategy)
        let result = try #require(files["Library.java"])
        #expect(!result.contains("return 42"))
        #expect(!result.contains("java.util.Set"))
    }

    @Test("Redirection writes alongside and leaves the original")
    @MainActor
    func redirection() async throws {
        let strategy = MTLInMemoryStrategy(
            options: MTLGeneratorOptions(redirectionPattern: ".{0}.new"))
        await strategy.setFile(existingJava, at: "src/Library.java")
        let source = javaTemplate.replacingOccurrences(of: "'Library.java'", with: "'src/Library.java'")
        let files = try await generateFiles(source, strategy: strategy)
        #expect(files["src/Library.java"] == existingJava)
        #expect(files["src/.Library.java.new"]?.contains("return 1;") == true)
    }

    @Test("Redirection is skipped when the content is unchanged")
    @MainActor
    func redirectionUnchanged() async throws {
        let strategy = MTLInMemoryStrategy(
            options: MTLGeneratorOptions(redirectionPattern: ".{0}.new"))
        let source = "[module T('u')]\n[template main()][file ('a.txt', 'overwrite', 'UTF-8')]same[/file][/template]"
        await strategy.setFile("same", at: "a.txt")
        let files = try await generateFiles(source, strategy: strategy)
        #expect(files[".a.txt.new"] == nil)
    }

    @Test("Redirection applies to new files only when the target exists")
    @MainActor
    func redirectionNewFile() async throws {
        let strategy = MTLInMemoryStrategy(
            options: MTLGeneratorOptions(redirectionPattern: ".{0}.new"))
        let files = try await generateFiles(javaTemplate, strategy: strategy)
        #expect(files["Library.java"] != nil)
        #expect(files[".Library.java.new"] == nil)
    }

    @Test("Redirected paths keep the directory")
    func redirectedPath() {
        let options = MTLGeneratorOptions(redirectionPattern: ".{0}.new")
        #expect(options.redirectedPath(for: "/out/p/A.java") == "/out/p/.A.java.new")
        #expect(options.redirectedPath(for: "A.java") == ".A.java.new")
        #expect(MTLGeneratorOptions().redirectedPath(for: "A.java") == nil)
    }

    @Test("Post-processors run in attachment order after merging")
    @MainActor
    func postProcessorOrder() async throws {
        let strategy = MTLInMemoryStrategy(postProcessors: [MarkerPostProcessor(marker: "first")])
        await strategy.addPostProcessor(MarkerPostProcessor(marker: "second"))
        let source = "[module T('u')]\n[template main()][file ('a.txt', 'overwrite', 'UTF-8')]body[/file][/template]"
        let files = try await generateFiles(source, strategy: strategy)
        #expect(files["a.txt"] == "bodyfirst\nsecond\n")
    }

    @Test("A failing post-processor aborts the generation")
    @MainActor
    func postProcessorFailure() async throws {
        let strategy = MTLInMemoryStrategy(postProcessors: [FailingPostProcessor()])
        let source = "[module T('u')]\n[template main()][file ('a.txt', 'overwrite', 'UTF-8')]body[/file][/template]"
        await #expect(throws: FailingPostProcessor.Failure.self) {
            _ = try await generateFiles(source, strategy: strategy)
        }
    }

    @Test("The line delimiter is applied last")
    @MainActor
    func lineDelimiter() async throws {
        let strategy = MTLInMemoryStrategy(options: MTLGeneratorOptions(lineDelimiter: "\r\n"))
        await strategy.addPostProcessor(MarkerPostProcessor(marker: "m"))
        let source = "[module T('u')]\n[template main()][file ('a.txt', 'overwrite', 'UTF-8')]x[/file][/template]"
        let files = try await generateFiles(source, strategy: strategy)
        #expect(files["a.txt"] == "xm\r\n")
    }

    @Test("A file that cannot be merged reports an error")
    @MainActor
    func unmergeable() async throws {
        let strategy = MTLInMemoryStrategy()
        await strategy.setFile("class A {", at: "Library.java")
        await #expect(throws: TaggedBlockError.self) {
            _ = try await generateFiles(javaTemplate, strategy: strategy)
        }
    }

    // MARK: File system

    @Test("The file system strategy merges, redirects and forces")
    @MainActor
    func fileSystemStrategy() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        // First generation creates the file
        try await generateToDirectory(
            javaTemplate, directory: directory.path)
        let target = directory.file("Library.java")
        #expect(try String(contentsOfFile: target, encoding: .utf8).contains("return 1;"))

        // The user edits the file
        let edited = try String(contentsOfFile: target, encoding: .utf8)
            .replacingOccurrences(
                of: "/**\n     * @generated\n     */\n    public int a() { return 1; }",
                with: "/**\n     * @generated NOT\n     */\n    public int a() { return 99; }")
        try edited.write(toFile: target, atomically: true, encoding: .utf8)

        // Regeneration merges
        try await generateToDirectory(javaTemplate, directory: directory.path)
        let merged = try String(contentsOfFile: target, encoding: .utf8)
        #expect(merged.contains("return 99"))
        #expect(merged.contains("return 2;"))

        // Redirection leaves the file alone
        try await generateToDirectory(
            javaTemplate, directory: directory.path,
            options: MTLGeneratorOptions(redirectionPattern: ".{0}.new"))
        #expect(try String(contentsOfFile: target, encoding: .utf8) == merged)
        let redirected = try String(
            contentsOfFile: directory.file(".Library.java.new"), encoding: .utf8)
        #expect(redirected.contains("return 1;"))

        // Force overwrite replaces it
        try await generateToDirectory(
            javaTemplate, directory: directory.path,
            options: MTLGeneratorOptions(forceOverwrite: true))
        #expect(!(try String(contentsOfFile: target, encoding: .utf8)).contains("return 99"))
    }

    @Test("Protected areas survive regeneration on disk")
    @MainActor
    func protectedAreasOnDisk() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let source = """
            [module T('u')]
            [template main()]
            [file ('out.txt', 'overwrite', 'UTF-8')]
            generated
            [protected ('area1', '// ', '// ')]
            default body
            [/protected]
            tail
            [/file]
            [/template]
            """
        try await generateToDirectory(source, directory: directory.path)
        let target = directory.file("out.txt")
        let original = try String(contentsOfFile: target, encoding: .utf8)
        #expect(original.contains("default body"))

        let edited = original.replacingOccurrences(of: "default body", with: "user code\nsecond line")
        try edited.write(toFile: target, atomically: true, encoding: .utf8)

        try await generateToDirectory(source, directory: directory.path)
        let regenerated = try String(contentsOfFile: target, encoding: .utf8)
        #expect(regenerated.contains("user code\nsecond line"))
        #expect(!regenerated.contains("default body"))

        try await generateToDirectory(source, directory: directory.path)
        #expect(try String(contentsOfFile: target, encoding: .utf8) == regenerated)
    }

    @Test("Protected areas do not leak between files")
    @MainActor
    func protectedAreasPerFile() async throws {
        let strategy = MTLInMemoryStrategy()
        await strategy.setFile("// START PROTECTED REGION x\nuser\n// END PROTECTED REGION x", at: "a.txt")
        let source = """
            [module T('u')]
            [template main()]
            [file ('a.txt', 'overwrite', 'UTF-8')]
            [protected ('x', '// ', '// ')]default[/protected]
            [/file]
            [file ('b.txt', 'overwrite', 'UTF-8')]
            [protected ('x', '// ', '// ')]default[/protected]
            [/file]
            [/template]
            """
        let files = try await generateFiles(source, strategy: strategy)
        #expect(files["a.txt"]?.contains("user") == true)
        #expect(files["b.txt"]?.contains("default") == true)
        #expect(files["b.txt"]?.contains("user") == false)
    }

    @Test("Strategies report the content of existing targets")
    @MainActor
    func existingContentOfStrategies() async {
        let memory = MTLInMemoryStrategy()
        await memory.setFile("abc", at: "x")
        #expect(await memory.existingContent(url: "x") == "abc")
        #expect(await memory.existingContent(url: "y") == nil)

        let directory = try? TemporaryDirectory()
        defer { directory?.remove() }
        let strategy = MTLFileSystemStrategy(basePath: directory?.path ?? "/nonexistent")
        #expect(await strategy.existingContent(url: "none.txt") == nil)
        try? "hello".write(toFile: directory!.file("some.txt"), atomically: true, encoding: .utf8)
        #expect(await strategy.existingContent(url: "some.txt") == "hello")
    }
}

/// Generates with a file system strategy rooted in a directory.
@MainActor
func generateToDirectory(
    _ source: String,
    directory: String,
    options: MTLGeneratorOptions = MTLGeneratorOptions()
) async throws {
    let module = try await MTLParser().parse(source)
    let fileStrategy = MTLFileSystemStrategy(basePath: directory, options: options)
    let generator = MTLGenerator(module: module, generationStrategy: fileStrategy)
    try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
}
