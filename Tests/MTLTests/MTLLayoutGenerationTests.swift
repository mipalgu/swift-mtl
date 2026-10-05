//
//  MTLLayoutGenerationTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import MTL

/// A module that generates a Java-like file and an XML file in the tab and own-line style.
private func layoutModule(
    declaration: String = "[layout ('indent=\\t', 'targetIndent=  ', 'opener=sameLine', 'files=*.java')/]",
    mergeDeclaration: String = "",
    javaFileOptions: String = ""
) -> String {
    """
    [module T('u')]
    \(declaration)
    \(mergeDeclaration)
    [template main()]
    [file ('src/Library.java', 'overwrite', 'UTF-8'\(javaFileOptions))]
    package p;

    /**
     * @generated
     */
    public class Library
    {
    \t/**
    \t * @generated
    \t */
    \tpublic int a()
    \t{
    \t\treturn 1;
    \t}
    }
    [/file]
    [file ('plugin.xml', 'overwrite', 'UTF-8')]
    <plugin>
    \t<extension>
    \t</extension>
    </plugin>
    [/file]
    [/template]
    """
}

/// The generated Java text after conversion to two spaces and same-line openers.
private let convertedJava = """
    package p;

    /**
     * @generated
     */
    public class Library {
      /**
       * @generated
       */
      public int a() {
        return 1;
      }
    }

    """

@Suite("MTL Layout: declaration")
struct MTLLayoutDeclarationTests {

    @Test("The declaration records every option")
    func declarationOptions() async throws {
        let module = try await MTLParser().parse(
            """
            [module T('u')]
            [layout ('indent=\\t', 'targetIndent=    ', 'opener=sameLine', 'openerToken=(', 'lineComments=# ;', 'blockComment=<! !>', 'quotes="', 'terminators=;,', 'files=*.java src/**/*.txt')/]
            """)
        let layout = try #require(module.layoutConfiguration)
        #expect(layout.sourceIndent == "\t")
        #expect(layout.targetIndent == "    ")
        #expect(layout.openerPlacement == .sameLine)
        #expect(layout.syntax.opener == "(")
        #expect(layout.syntax.lineComments == ["#", ";"])
        #expect(layout.syntax.blockComments == [.init(start: "<!", end: "!>")])
        #expect(layout.syntax.quotes == ["\""])
        #expect(layout.syntax.terminators == [";", ","])
        #expect(layout.filePatterns == ["*.java", "src/**/*.txt"])
    }

    @Test("Defaults leave the layout as generated, and modules without a declaration have none")
    func defaults() async throws {
        let module = try await MTLParser().parse("[module T('u')]\n[layout ('files=*.c')/]\n")
        let layout = try #require(module.layoutConfiguration)
        #expect(layout.isIdentity)
        #expect(layout.syntax == MTLMergeSyntax.defaults(for: .braces))
        let plain = try await MTLParser().parse("[module T('u')]\n")
        #expect(plain.layoutConfiguration == nil)
    }

    @Test("Modules with different layouts are different")
    func equality() async throws {
        let one = try await MTLParser().parse("[module T('u')]\n[layout ('opener=sameLine')/]\n")
        let two = try await MTLParser().parse("[module T('u')]\n[layout ('opener=ownLine')/]\n")
        #expect(one != two)
        #expect(one.hashValue != two.hashValue || one != two)
        let same = try await MTLParser().parse("[module T('u')]\n[layout ('opener=sameLine')/]\n")
        #expect(one == same)
    }

    @Test("Malformed declarations are rejected", arguments: [
        "[layout ('opener=elsewhere')/]",
        "[layout ('opener')/]",
        "[layout ('colour=red')/]",
        "[layout ('openerToken=ab')/]",
        "[layout ('blockComment=/*')/]",
        "[layout ('files= ')/]",
        "[layout (indent)/]",
        "[layout ('opener=sameLine')/][layout ('opener=ownLine')/]",
    ])
    func malformed(declaration: String) async {
        await #expect(throws: (any Error).self) {
            _ = try await MTLParser().parse("[module T('u')]\n\(declaration)\n")
        }
    }

    @Test("Malformed layout file options are rejected")
    func malformedFileOption() async {
        await #expect(throws: (any Error).self) {
            _ = try await MTLParser().parse(
                "[module T('u')][template main()][file ('a', 'overwrite', 'UTF-8', 'layout=maybe')]x[/file][/template]")
        }
    }

    @Test("The file option is recorded")
    func fileOption() {
        #expect(MTLFileOptions().layout)
        #expect(MTLFileOptions(layout: false) != MTLFileOptions())
        #expect(MTLFileOptionKeys.all.contains(MTLFileOptionKeys.layout))
    }

    @Test("The word layout stays usable as a variable name")
    @MainActor
    func layoutAsIdentifier() async throws {
        let output = try await MTLTestSupport.output(
            "[module T('u')]\n[template main()]\n[let layout = 'wide'][layout/][/let]\n[/template]")
        #expect(output == "wide")
    }
}

@Suite("MTL Layout: generation")
struct MTLLayoutGenerationTests {

    @Test("A module declaration converts matching files only", arguments: FileControlStrategy.allCases)
    @MainActor
    func scopedToPatterns(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.generate(layoutModule())
        #expect(await harness.text("src/Library.java") == convertedJava)
        #expect(await harness.text("plugin.xml") == "<plugin>\n\t<extension>\n\t</extension>\n</plugin>\n")
    }

    @Test("Without a declaration nothing is converted", arguments: FileControlStrategy.allCases)
    @MainActor
    func noDeclaration(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.generate(layoutModule(declaration: ""))
        let text = try #require(await harness.text("src/Library.java"))
        #expect(text.contains("public class Library\n{\n\t/**"))
    }

    @Test("Generator options override the module declaration", arguments: FileControlStrategy.allCases)
    @MainActor
    func optionsOverride(kind: FileControlStrategy) async throws {
        let options = MTLGeneratorOptions(
            layout: MTLLayoutConfiguration(
                sourceIndent: "\t", targetIndent: "    ", openerPlacement: .ownLine, filePatterns: ["*.xml"]))
        let harness = try FileControlHarness(kind, options: options)
        defer { harness.directory.remove() }
        try await harness.generate(layoutModule())
        let java = try #require(await harness.text("src/Library.java"))
        #expect(java.contains("public class Library\n{\n\t/**"))
        #expect(await harness.text("plugin.xml") == "<plugin>\n    <extension>\n    </extension>\n</plugin>\n")
    }

    @Test("Generator options convert modules that declare nothing", arguments: FileControlStrategy.allCases)
    @MainActor
    func optionsWithoutDeclaration(kind: FileControlStrategy) async throws {
        let options = MTLGeneratorOptions(
            layout: MTLLayoutConfiguration(
                sourceIndent: "\t", targetIndent: "  ", openerPlacement: .sameLine, filePatterns: ["*.java"]))
        let harness = try FileControlHarness(kind, options: options)
        defer { harness.directory.remove() }
        try await harness.generate(layoutModule(declaration: ""))
        #expect(await harness.text("src/Library.java") == convertedJava)
    }

    @Test("A file can opt out", arguments: FileControlStrategy.allCases)
    @MainActor
    func fileOptOut(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.generate(layoutModule(javaFileOptions: ", 'layout=false'"))
        let text = try #require(await harness.text("src/Library.java"))
        #expect(text.contains("public class Library\n{\n\t/**"))
    }

    @Test("An opt-out holds against generator options too", arguments: FileControlStrategy.allCases)
    @MainActor
    func fileOptOutAgainstOptions(kind: FileControlStrategy) async throws {
        let options = MTLGeneratorOptions(
            layout: MTLLayoutConfiguration(sourceIndent: "\t", targetIndent: "  "))
        let harness = try FileControlHarness(kind, options: options)
        defer { harness.directory.remove() }
        try await harness.generate(layoutModule(javaFileOptions: ", 'layout=false'"))
        let text = try #require(await harness.text("src/Library.java"))
        #expect(text.contains("\n\t/**"))
    }

    @Test("An explicit layout=true keeps converting", arguments: FileControlStrategy.allCases)
    @MainActor
    func fileOptIn(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.generate(layoutModule(javaFileOptions: ", 'layout=true'"))
        #expect(await harness.text("src/Library.java") == convertedJava)
    }

    @Test("The line delimiter applies after conversion", arguments: FileControlStrategy.allCases)
    @MainActor
    func lineDelimiter(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind, options: MTLGeneratorOptions(lineDelimiter: "\r\n"))
        defer { harness.directory.remove() }
        try await harness.generate(layoutModule())
        let text = try #require(await harness.text("src/Library.java"))
        #expect(text == convertedJava.replacingOccurrences(of: "\n", with: "\r\n"))
    }

    @Test("Regenerating converted text changes nothing", arguments: FileControlStrategy.allCases)
    @MainActor
    func regenerationIsStable(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.generate(layoutModule())
        let first = try #require(await harness.text("src/Library.java"))
        try await harness.seed("src/Library.java", first)
        try await harness.generate(layoutModule())
        #expect(await harness.text("src/Library.java") == first)
    }

    @Test("A redirected file is compared in the target layout", arguments: FileControlStrategy.allCases)
    @MainActor
    func redirection(kind: FileControlStrategy) async throws {
        let options = MTLGeneratorOptions(redirectionPattern: ".{0}.new")
        let harness = try FileControlHarness(kind, options: options)
        defer { harness.directory.remove() }
        try await harness.seed("src/Library.java", convertedJava)
        try await harness.generate(layoutModule())
        #expect(await harness.text("src/Library.java") == convertedJava)
        #expect(await harness.text("src/.Library.java.new") == nil)
    }
}

@Suite("MTL Layout: merge and protected areas")
struct MTLLayoutMergeTests {

    private static let merge = "[merge ('/**', '*/', '@generated', '@generated NOT', 'braces', 'files=*.java')/]"

    /// An existing file in the target layout with a block the user has edited.
    private static let existing = """
        package p;

        /**
         * @generated
         */
        public class Library {
          /**
           * @generated NOT
           */
          public int a() {
            return 42;
          }
        }

        """

    @Test("A kept block in the target layout is preserved verbatim", arguments: FileControlStrategy.allCases)
    @MainActor
    func keptBlockSurvives(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("src/Library.java", Self.existing)
        try await harness.generate(layoutModule(mergeDeclaration: Self.merge))
        #expect(await harness.text("src/Library.java") == Self.existing)
    }

    @Test("Generated blocks are replaced in the target layout", arguments: FileControlStrategy.allCases)
    @MainActor
    func generatedBlockReplaced(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        let stale = Self.existing.replacingOccurrences(of: "@generated NOT", with: "@generated")
            .replacingOccurrences(of: "return 42;", with: "return 7;")
        try await harness.seed("src/Library.java", stale)
        try await harness.generate(layoutModule(mergeDeclaration: Self.merge))
        #expect(await harness.text("src/Library.java") == convertedJava)
    }

    @Test("Merging is stable over repeated regeneration", arguments: FileControlStrategy.allCases)
    @MainActor
    func repeatedMerge(kind: FileControlStrategy) async throws {
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed("src/Library.java", Self.existing)
        for _ in 0..<3 {
            try await harness.generate(layoutModule(mergeDeclaration: Self.merge))
        }
        #expect(await harness.text("src/Library.java") == Self.existing)
    }

    @Test("Emitted regions still line up after openers move", arguments: FileControlStrategy.allCases)
    @MainActor
    func emittedRegions(kind: FileControlStrategy) async throws {
        let source = """
            [module T('u')]
            [layout ('indent=\\t', 'targetIndent=  ', 'opener=sameLine')/]
            [merge ('/**', '*/', '@generated', '@generated NOT', 'braces')/]
            [template main()]
            [file ('A.java', 'overwrite', 'UTF-8')]
            [collect ('imports', 'java.util.List')/]
            package p;
            public class A
            {
            [emit ('imports')]
            import [item/];
            [/emit]

            \t/**
            \t * @generated
            \t */
            \tint a()
            \t{
            \t}
            }
            [/file]
            [/template]
            """
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed(
            "A.java",
            "package p;\npublic class A {\nimport java.util.Set;\n\n  /**\n   * @generated\n   */\n  int a() {\n  }\n}\n")
        try await harness.generate(source)
        let text = try #require(await harness.text("A.java"))
        #expect(text.contains("import java.util.List;"))
        #expect(text.contains("import java.util.Set;"))
        #expect(text.components(separatedBy: "int a()").count == 2)
        #expect(!text.contains("\t"))
    }

    @Test("Preserved protected areas are not converted", arguments: FileControlStrategy.allCases)
    @MainActor
    func protectedAreaIsVerbatim(kind: FileControlStrategy) async throws {
        let source = """
            [module T('u')]
            [layout ('indent=\\t', 'targetIndent=  ', 'opener=sameLine')/]
            [template main()]
            [file ('A.txt', 'overwrite', 'UTF-8')]
            class A
            {
            \tint generated;
            [protected ('body') startTagPrefix('// ') endTagPrefix('// ')]
            \tdefault();
            [/protected]
            \tint tail;
            }
            [/file]
            [/template]
            """
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.seed(
            "A.txt",
            "class A {\n// START PROTECTED REGION body\n\tuser();\n\tif (x)\n\t{\n\t}\n// END PROTECTED REGION body\n}\n")
        try await harness.generate(source)
        #expect(
            await harness.text("A.txt")
                == "class A {\n  int generated;\n// START PROTECTED REGION body\n\tuser();\n\tif (x)\n\t{\n\t}\n// END PROTECTED REGION body\n  int tail;\n}\n"
        )
    }

    @Test("An unpreserved protected area is generated in the target layout", arguments: FileControlStrategy.allCases)
    @MainActor
    func protectedAreaDefaultConverted(kind: FileControlStrategy) async throws {
        let source = """
            [module T('u')]
            [layout ('indent=\\t', 'targetIndent=  ', 'opener=sameLine')/]
            [template main()]
            [file ('A.txt', 'overwrite', 'UTF-8')]
            class A
            {
            [protected ('body') startTagPrefix('// ') endTagPrefix('// ')]
            \tdefault();
            [/protected]
            }
            [/file]
            [/template]
            """
        let harness = try FileControlHarness(kind)
        defer { harness.directory.remove() }
        try await harness.generate(source)
        #expect(
            await harness.text("A.txt")
                == "class A {\n// START PROTECTED REGION body\n  default();\n// END PROTECTED REGION body\n}\n")
    }

    @Test("Verbatim markers never leak into output outside a file")
    @MainActor
    func noMarkerLeak() async throws {
        let output = try await MTLTestSupport.output(
            "[module T('u')]\n[template main()]\n[protected ('x')]\nkeep\n[/protected]\n[/template]")
        #expect(!output.contains(MTLVerbatimMarkers.open))
        #expect(!output.contains(MTLVerbatimMarkers.close))
    }
}
