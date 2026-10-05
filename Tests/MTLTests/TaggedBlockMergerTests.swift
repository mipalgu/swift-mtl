//
//  TaggedBlockMergerTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import MTL

/// Loads the merge fixtures bundled with the tests.
enum MergeFixtures {

    /// Returns the text of a fixture in `Resources/merge`.
    static func text(_ name: String) throws -> String {
        let url = MTLTestSupport.resource("merge/\(name).txt")
        return try String(contentsOf: url, encoding: .utf8)
    }

    static let javaConfiguration = MTLMergeConfiguration(
        commentStart: "/**", commentEnd: "*/",
        generatedTag: "@generated", keepTag: "@generated NOT", strategy: .braces)

    static let cConfiguration = MTLMergeConfiguration(
        commentStart: "/*", commentEnd: "*/",
        generatedTag: "@generated", keepTag: "@generated NOT", strategy: .braces,
        syntax: {
            var syntax = MTLMergeSyntax.defaults(for: .braces)
            syntax.terminators = [";", "\n"]
            return syntax
        }())

    static let swiftConfiguration = MTLMergeConfiguration(
        commentStart: "///", commentEnd: "",
        generatedTag: "@generated", keepTag: "@generated NOT", strategy: .braces,
        syntax: {
            var syntax = MTLMergeSyntax.defaults(for: .braces)
            syntax.terminators = [";", "\n"]
            return syntax
        }())

    static let pythonConfiguration = MTLMergeConfiguration(
        commentStart: "#", commentEnd: "",
        generatedTag: "@generated", keepTag: "@generated NOT", strategy: .indentation)
}

@Suite("Tagged Block Scanner Tests")
struct TaggedBlockScannerTests {

    @Test("Braces inside strings, characters and comments are ignored")
    func bracesInLiteralsAndComments() throws {
        let source = """
            /** @generated */
            void a() {
                String s = "}";
                char c = '{';
                // }
                /* { */
            }
            /** @generated */
            void b() { }
            """
        let scan = try TaggedBlockScanner(configuration: MergeFixtures.javaConfiguration).scan(source)
        #expect(scan.blocks.map(\.signature) == ["void a()", "void b()"])
        #expect(scan.blocks[0].leadingComment == "/** @generated */")
    }

    @Test("Members without a body are terminated and nest")
    func nestedMembers() throws {
        let source = """
            class A {
                /** @generated */
                int x = 5;
                /** @generated */
                void f(int a, int b) { return; }
            }
            """
        let scan = try TaggedBlockScanner(configuration: MergeFixtures.javaConfiguration).scan(source)
        #expect(scan.blocks.count == 1)
        let children = scan.blocks[0].children
        #expect(children.map(\.signature) == ["int x", "void f(int a, int b)"])
        #expect(children[0].bodyRange == nil)
        #expect(scan.text(children[0].range).hasSuffix("int x = 5;"))
    }

    @Test("Unbalanced braces are reported")
    func unbalanced() {
        let scanner = TaggedBlockScanner(configuration: MergeFixtures.javaConfiguration)
        #expect(throws: TaggedBlockError.self) { try scanner.scan("void a() {") }
        #expect(throws: TaggedBlockError.self) { try scanner.scan("}") }
    }

    @Test("Triple quoted strings hide braces")
    func tripleQuoted() throws {
        let source = "let s = \"\"\"\n}\n\"\"\"\nfunc f() {}\n"
        var syntax = MTLMergeSyntax.defaults(for: .braces)
        syntax.terminators = ["\n"]
        let configuration = MTLMergeConfiguration(
            commentStart: "///", commentEnd: "", generatedTag: "@generated", keepTag: "",
            syntax: syntax)
        let scan = try TaggedBlockScanner(configuration: configuration).scan(source)
        #expect(scan.blocks.map(\.signature) == ["let s", "func f()"])
    }

    @Test("Indentation strategy nests by indentation")
    func indentation() throws {
        let source = "class A:\n    # @generated\n    def f(self):\n        return 1\n\n    x = 1\n"
        let scan = try TaggedBlockScanner(configuration: MergeFixtures.pythonConfiguration).scan(source)
        #expect(scan.blocks.map(\.signature) == ["class A"])
        let children = scan.blocks[0].children
        #expect(children.map(\.signature) == ["def f(self)", "x"])
        #expect(children[0].leadingComment == "# @generated")
        #expect(children[0].children.map(\.signature) == ["return 1"])
    }

    @Test("Ownership follows the tags")
    func ownership() {
        let configuration = MergeFixtures.javaConfiguration
        #expect(configuration.ownership(ofLeadingComment: "/** @generated */") == .generated)
        #expect(configuration.ownership(ofLeadingComment: "/** @generated NOT */") == .kept)
        #expect(configuration.ownership(ofLeadingComment: "/** hand written */") == .user)
    }

    @Test("The declared comment delimiters are recognised as comments")
    func declaredDelimitersAreComments() {
        let configuration = MergeFixtures.swiftConfiguration
        #expect(configuration.syntax.lineComments.contains("///"))
        let pair = MTLMergeSyntax.BlockComment(start: "/**", end: "*/")
        #expect(MergeFixtures.javaConfiguration.syntax.blockComments.contains(pair))
    }
}

@Suite("Tagged Block Merger Tests")
struct TaggedBlockMergerTests {

    @Test("Java-like merge keeps edits, replaces generated, adds, removes, unions imports")
    func java() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        let regions = [MTLEmittedRegion(name: "imports", firstLine: 2, lineCount: 2)]
        let merged = try merger.merge(
            existing: MergeFixtures.text("java-existing"),
            generated: MergeFixtures.text("java-generated"), regions: regions)
        #expect(merged == (try MergeFixtures.text("java-expected")))
    }

    @Test("Merging is idempotent")
    func idempotent() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        let regions = [MTLEmittedRegion(name: "imports", firstLine: 2, lineCount: 2)]
        let generated = try MergeFixtures.text("java-generated")
        let once = try merger.merge(
            existing: MergeFixtures.text("java-existing"), generated: generated, regions: regions)
        let twice = try merger.merge(existing: once, generated: generated, regions: regions)
        #expect(once == twice)
    }

    @Test("C-like merge")
    func cLike() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.cConfiguration)
        let regions = [MTLEmittedRegion(name: "includes", firstLine: 0, lineCount: 2)]
        let merged = try merger.merge(
            existing: MergeFixtures.text("c-existing"),
            generated: MergeFixtures.text("c-generated"), regions: regions)
        #expect(merged == (try MergeFixtures.text("c-expected")))
    }

    @Test("Swift-like merge with newline terminated members")
    func swiftLike() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.swiftConfiguration)
        let merged = try merger.merge(
            existing: MergeFixtures.text("swift-existing"),
            generated: MergeFixtures.text("swift-generated"))
        #expect(merged == (try MergeFixtures.text("swift-expected")))
    }

    @Test("Indentation strategy merge")
    func indentationStrategy() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.pythonConfiguration)
        let merged = try merger.merge(
            existing: MergeFixtures.text("python-existing"),
            generated: MergeFixtures.text("python-generated"))
        #expect(merged == (try MergeFixtures.text("python-expected")))
    }

    @Test("An empty existing file yields the generated text")
    func emptyExisting() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        let merged = try merger.merge(existing: " \n", generated: "class A {}\r\n")
        #expect(merged == "class A {}\n")
    }

    @Test("Existing blocks without a tag are preserved")
    func userBlockPreserved() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        let existing = "/** @generated */\nclass A {\n    /** @generated */\n    int a() { return 1; }\n    int mine() { return 2; }\n}\n"
        let generated = "/** @generated */\nclass A {\n    /** @generated */\n    int a() { return 3; }\n}\n"
        let merged = try merger.merge(existing: existing, generated: generated)
        #expect(merged.contains("return 3"))
        #expect(merged.contains("mine"))
    }

    @Test("A user class without tags is preserved whole")
    func untaggedContainer() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        let existing = "class A {\n    int mine() { return 2; }\n}\n"
        let generated = "/** @generated */\nclass A {\n    /** @generated */\n    int a() { return 3; }\n}\n"
        let merged = try merger.merge(existing: existing, generated: generated)
        #expect(merged == existing)
    }

    @Test("A kept container keeps its header but merges its members")
    func keptContainer() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        let existing = "/** @generated NOT */\nclass A extends Base {\n    /** @generated */\n    int a() { return 1; }\n}\n"
        let generated = "/** @generated */\nclass A {\n    /** @generated */\n    int a() { return 3; }\n}\n"
        let merged = try merger.merge(existing: existing, generated: generated)
        #expect(merged.contains("class A extends Base {"))
        #expect(merged.contains("return 3"))
    }

    @Test("New blocks are inserted at the start when they come first")
    func insertFirst() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        let existing = "/** @generated */\nclass A {\n    /** @generated */\n    int b() { return 1; }\n}\n"
        let generated =
            "/** @generated */\nclass A {\n    /** @generated */\n    int a() { return 0; }\n\n    /** @generated */\n    int b() { return 1; }\n}\n"
        let merged = try merger.merge(existing: existing, generated: generated)
        let aPosition = try #require(merged.range(of: "int a()"))
        let bPosition = try #require(merged.range(of: "int b()"))
        #expect(aPosition.lowerBound < bPosition.lowerBound)
    }

    @Test("Duplicate signatures are matched in order")
    func duplicateSignatures() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        let existing = "/** @generated */\nvoid f() { 1 }\n/** @generated */\nvoid f() { 2 }\n"
        let generated = "/** @generated */\nvoid f() { 3 }\n/** @generated */\nvoid f() { 4 }\n"
        #expect(try merger.merge(existing: existing, generated: generated) == generated)
    }

    @Test("An emitted region with no counterpart is inserted before the first tagged block")
    func regionWithoutAnchor() throws {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        let existing = "package p;\n\n/** @generated */\nclass A {}\n"
        let generated = "package p;\n\nimport x.Y;\n\n/** @generated */\nclass A {}\n"
        let regions = [MTLEmittedRegion(name: "imports", firstLine: 2, lineCount: 1)]
        let merged = try merger.merge(existing: existing, generated: generated, regions: regions)
        #expect(merged == "package p;\n\nimport x.Y;\n\n/** @generated */\nclass A {}\n")
    }

    @Test("Unbalanced existing files cannot be merged")
    func unbalancedExisting() {
        let merger = TaggedBlockMerger(configuration: MergeFixtures.javaConfiguration)
        #expect(throws: TaggedBlockError.self) {
            try merger.merge(existing: "void a() {", generated: "void a() {}")
        }
    }

    @Test("Scan errors have descriptions")
    func errorDescription() {
        #expect(TaggedBlockError.unbalancedBraces(offset: 3).errorDescription?.contains("3") == true)
    }
}
