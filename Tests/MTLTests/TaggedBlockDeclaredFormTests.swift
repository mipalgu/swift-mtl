//
//  TaggedBlockDeclaredFormTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import MTL

private let stubComment = "// Ensure that you remove @generated or mark it @generated NOT"

private func merge(
    _ configuration: MTLMergeConfiguration, existing: String, generated: String
) throws -> String {
    try TaggedBlockMerger(configuration: configuration).merge(existing: existing, generated: generated)
}

@Suite("Tagged Block Merge: declared comment form")
struct TaggedBlockDeclaredFormTests {

    private let java = MergeFixtures.javaConfiguration

    @Test("A stub body that mentions the tags does not stop a generated method being replaced")
    func stubBodyIsReplaced() throws {
        let existing = """
            /** @generated */
            class A {
                /**
                 * Does a thing.
                 * @generated
                 */
                void f() {
                    \(stubComment)
                    throw new UnsupportedOperationException();
                }
            }
            """
        let generated = existing.replacingOccurrences(
            of: "throw new UnsupportedOperationException();", with: "return;")
        let merged = try merge(java, existing: existing, generated: generated)
        #expect(merged == generated)
    }

    @Test("A method whose leading comment really carries the keep tag is kept")
    func keepTagInLeadingCommentKeeps() throws {
        let existing = """
            /** @generated */
            class A {
                /**
                 * @generated NOT
                 */
                void f() {
                    hand();
                }
            }
            """
        let generated = existing.replacingOccurrences(of: "hand();", with: "gen();")
            .replacingOccurrences(of: "@generated NOT", with: "@generated")
        #expect(try merge(java, existing: existing, generated: generated) == existing)
    }

    @Test("Tags outside the declared form are ignored")
    func otherCommentFormsAreIgnored() throws {
        let existing = """
            /** @generated */
            /** @generated */
            class A {
                /** @generated */
                // @generated NOT
                void a() { old(); }
                /* @generated */
                void b() { old(); }
                /** @generated */
                void c() {
                    String s = "@generated NOT";
                    old();
                }
            }
            """
        let generated = """
            /** @generated */
            /** @generated */
            class A {
                /** @generated */
                // @generated NOT
                void a() { new(); }
                /* @generated */
                void b() { new(); }
                /** @generated */
                void c() {
                    String s = "@generated NOT";
                    new();
                }
            }
            """
        let merged = try merge(java, existing: existing, generated: generated)
        #expect(merged.contains("void a() { new(); }"))
        #expect(merged.contains("void b() { old(); }"))
        #expect(merged.contains("new();\n    }"))
    }

    @Test("Only the leading comment of a block carries tags, not comments further up")
    func distantCommentsAreIgnored() throws {
        let existing = """
            /** @generated NOT */
            package p;
            /** @generated */
            /** @generated */
            class A {
                /** @generated */
                void f() { old(); }
            }
            """
        let generated = existing.replacingOccurrences(of: "old()", with: "new()")
        let merged = try merge(java, existing: existing, generated: generated)
        #expect(merged.contains("void f() { new(); }"))
    }

    @Test("Nested generated types replace generated methods wholesale but keep kept members")
    func nestedTypes() throws {
        let existing = """
            /** @generated */
            /** @generated */
            /** @generated */
            class A {
                /** @generated */
                interface B {
                    /** @generated */
                    void f() {
                        \(stubComment)
                        old();
                    }
                    /** @generated NOT */
                    void kept() { mine(); }
                }
            }
            """
        let generated = """
            /** @generated */
            /** @generated */
            /** @generated */
            class A {
                /** @generated */
                interface B {
                    /** @generated */
                    void f() {
                        \(stubComment)
                        new();
                    }
                    /** @generated */
                    void kept() { theirs(); }
                }
            }
            """
        let merged = try merge(java, existing: existing, generated: generated)
        #expect(merged.contains("        new();"))
        #expect(!merged.contains("old();"))
        #expect(merged.contains("mine();"))
        #expect(!merged.contains("theirs();"))
        #expect(try merge(java, existing: merged, generated: generated) == merged)
    }

    @Test("Line comment carriers count only the contiguous comments directly above a block")
    func lineCommentCarriers() throws {
        let swift = MergeFixtures.swiftConfiguration
        let existing = """
            /// @generated

            func detached() { old() }
            /// @generated
            func attached() { old() }
            // @generated
            func otherForm() { old() }
            """
        let generated = existing.replacingOccurrences(of: "old()", with: "new()")
        let merged = try merge(swift, existing: existing, generated: generated)
        #expect(merged.contains("func detached() { old() }"))
        #expect(merged.contains("func attached() { new() }"))
        #expect(merged.contains("func otherForm() { old() }"))
    }

    @Test("A stub comment inside a generated body does not make it a container")
    func swiftStubBody() throws {
        let swift = MergeFixtures.swiftConfiguration
        let existing = """
            /// @generated
            func f() {
                \(stubComment)
                old()
            }

            """
        let generated = existing.replacingOccurrences(of: "old()", with: "new()")
        let merged = try merge(swift, existing: existing, generated: generated)
        #expect(merged.contains("new()"))
        #expect(!merged.contains("old()"))
    }

    @Test("The indentation strategy ignores tags in bodies and detached comments")
    func indentationStrategy() throws {
        let python = MergeFixtures.pythonConfiguration
        let existing = """
            # @generated
            class A:
                # @generated
                def f(self):
                    # helper
                    return 1

                # @generated

                def detached(self):
                    return 1

                # @generated NOT
                def kept(self):
                    return 1
            """
        let generated = existing.replacingOccurrences(of: "return 1", with: "return 2")
            .replacingOccurrences(of: "# @generated NOT\n    def kept", with: "# @generated\n    def kept")
        let merged = try merge(python, existing: existing, generated: generated)
        #expect(merged.contains("def f(self):\n        # helper\n        return 2"))
        #expect(merged.contains("def detached(self):\n        return 1"))
        #expect(merged.contains("def kept(self):\n        return 1"))
        #expect(try merge(python, existing: merged, generated: generated) == merged)
    }

    @Test("The scanner exposes the declared comment of a block")
    func declaredComment() throws {
        let source = """
            /* plain */
            /** @generated */
            // note
            void a() { }
            """
        let scan = try TaggedBlockScanner(configuration: java).scan(source)
        #expect(scan.blocks[0].declaredComment == "/** @generated */")
        #expect(scan.blocks[0].leadingComment.contains("// note"))
    }
}

@Suite("Tagged Block Merge: container layout")
struct TaggedBlockContainerLayoutTests {

    private let java = MergeFixtures.javaConfiguration

    private func source(indent: String, member: String = "generatedMember", kept: String = "mine") -> String {
        let lines = [
            "/** @generated */",
            "class A {",
            "\(indent)/** @generated */",
            "\(indent)interface B {",
            "\(indent)\(indent)/** @generated */",
            "\(indent)\(indent)void \(member)();",
            "\(indent)\(indent)/** @generated NOT */",
            "\(indent)\(indent)void keptMember() { \(kept)(); }",
            "\(indent)}",
            "}",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    @Test("A generated container takes its closing line from the new text", arguments: [
        ("\t", "  "), ("  ", "\t"),
    ])
    func layoutChange(from old: String, to new: String) throws {
        let existing = source(indent: old)
        let generated = source(indent: new, kept: "theirs")
        let merged = try merge(java, existing: existing, generated: generated)
        #expect(merged.contains("\(new)}\n}"))
        #expect(merged.contains("\(new)\(new)void generatedMember();"))
        // Kept members keep their own text verbatim.
        #expect(merged.contains("\(old)\(old)/** @generated NOT */\n\(old)\(old)void keptMember() { mine(); }"))
        #expect(!merged.contains("theirs"))
        #expect(try merge(java, existing: merged, generated: generated) == merged)
    }

    @Test("A kept container keeps its header and closing line")
    func keptContainer() throws {
        let existing = """
            /** @generated NOT */
            class A {
            \t/** @generated */
            \tvoid f() { old(); }
            }
            """
        let generated = """
            /** @generated */
            class   A  {
              /** @generated */
              void f() { new(); }
              /** @generated */
              void g() { new(); }
            }
            """
        let merged = try merge(java, existing: existing, generated: generated)
        #expect(merged.hasPrefix("/** @generated NOT */\nclass A {\n  /** @generated */\n  void f() { new(); }"))
        #expect(merged.hasSuffix("void g() { new(); }\n}"))
        #expect(!merged.contains("class   A"))
    }
}

@Suite("Tagged Block Merge: layout change through the generator")
struct TaggedBlockGeneratorLayoutTests {

    private static let module = """
        [module T('u')]
        [layout ('indent=\\t', 'targetIndent=  ', 'opener=sameLine', 'files=*.java')/]
        [merge ('/**', '*/', '@generated', '@generated NOT', 'braces', 'files=*.java')/]
        [template main()]
        [file ('src/Library.java', 'overwrite', 'UTF-8')]
        /** @generated */
        public class Library
        {
        \t/** @generated */
        \tpublic interface Item
        \t{
        \t\t/** @generated */
        \t\tint a();
        \t\t/** @generated */
        \t\tvoid b()
        \t\t{
        \t\t\t// Ensure that you remove @generated or mark it @generated NOT
        \t\t\tthrow new UnsupportedOperationException();
        \t\t}
        \t}
        }
        [/file]
        [/template]
        """

    private static let tabbed = """
        /** @generated */
        public class Library {
        \t/** @generated */
        \tpublic interface Item {
        \t\t/** @generated NOT */
        \t\tint a();
        \t\t/** @generated */
        \t\tvoid b() {
        \t\t\t// Ensure that you remove @generated or mark it @generated NOT
        \t\t\tthrow new IllegalStateException();
        \t\t}
        \t}
        }

        """

    @Test("A nested generated type follows a new layout and stays stable", arguments: FileControlStrategy.allCases)
    @MainActor
    func layoutChange(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("src/Library.java", Self.tabbed)
        try await harness.generate(Self.module)
        let first = try #require(await harness.text("src/Library.java"))
        #expect(first.contains("\n  }\n}"))
        #expect(first.contains("\n  /** @generated */\n  public interface Item {"))
        #expect(first.contains("\t\t/** @generated NOT */\n\t\tint a();"))
        #expect(first.contains("throw new UnsupportedOperationException();"))
        #expect(!first.contains("IllegalStateException"))
        try await harness.generate(Self.module)
        #expect(await harness.text("src/Library.java") == first)
    }
}
