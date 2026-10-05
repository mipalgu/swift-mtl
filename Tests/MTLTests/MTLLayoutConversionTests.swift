//
//  MTLLayoutConversionTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import MTL

/// Layouts shared by the layout tests.
private enum Layouts {

    /// Tabs to four spaces, openers unchanged.
    static let tabsToSpaces = MTLLayoutConfiguration(sourceIndent: "\t", targetIndent: "    ")

    /// Four spaces to tabs, openers unchanged.
    static let spacesToTabs = MTLLayoutConfiguration(sourceIndent: "    ", targetIndent: "\t")

    /// Openers on the preceding line, indentation unchanged.
    static let sameLine = MTLLayoutConfiguration(openerPlacement: .sameLine)

    /// Tabs to two spaces with openers on the preceding line.
    static let compact = MTLLayoutConfiguration(
        sourceIndent: "\t", targetIndent: "  ", openerPlacement: .sameLine)
}

@Suite("MTL Layout: indentation")
struct MTLLayoutIndentationTests {

    @Test("Leading tabs become the target unit and text inside lines is untouched")
    func tabsToSpaces() {
        let result = Layouts.tabsToSpaces.convert("a\n\tb\n\t\tc\tgap\td\n")
        #expect(result == "a\n    b\n        c\tgap\td\n")
    }

    @Test("Leading spaces become tabs, leaving a remainder")
    func spacesToTabs() {
        let result = Layouts.spacesToTabs.convert("a\n    b\n        c\n      d\n  e\n")
        #expect(result == "a\n\tb\n\t\tc\n\t  d\n  e\n")
    }

    @Test("Only the unbroken run of units at the start of a line is converted")
    func mixedIndentation() {
        #expect(Layouts.tabsToSpaces.convert("\t \tx\n") == "     \tx\n")
        #expect(Layouts.tabsToSpaces.convert(" \tx\n") == " \tx\n")
    }

    @Test("Continuation lines keep their alignment after the indentation")
    func continuationLines() {
        let result = Layouts.tabsToSpaces.convert("\t\tcall(a,\n\t\t     b,\n\t\t     c);\n")
        #expect(result == "        call(a,\n             b,\n             c);\n")
    }

    @Test("Blank lines are preserved and indentation-only lines are converted")
    func blankLines() {
        #expect(Layouts.tabsToSpaces.convert("a\n\n\t\n\n\tb\n") == "a\n\n    \n\n    b\n")
        #expect(Layouts.tabsToSpaces.convert("\n\n") == "\n\n")
    }

    @Test("An empty text and an empty source unit change nothing")
    func degenerateInputs() {
        #expect(Layouts.tabsToSpaces.convert("").isEmpty)
        let none = MTLLayoutConfiguration(sourceIndent: "", targetIndent: "  ")
        #expect(none.convert("\tx\n") == "\tx\n")
    }

    @Test("Line comment continuation and block comment lines are converted")
    func commentLines() {
        let result = Layouts.tabsToSpaces.convert("\t/**\n\t * doc\n\t */\n\t// note\n")
        #expect(result == "    /**\n     * doc\n     */\n    // note\n")
    }

    @Test("Lines that start inside a multi-line string literal are untouched")
    func multiLineLiteral() {
        let text = "\tx = \"\"\"\n\tkeep\n\t\"\"\"\n\ty\n"
        #expect(Layouts.tabsToSpaces.convert(text) == "    x = \"\"\"\n\tkeep\n\t\"\"\"\n    y\n")
    }

    @Test("CRLF line breaks are preserved and lines after them are converted")
    func crlf() {
        let result = Layouts.tabsToSpaces.convert("a\r\n\tb\r\n\t\tc\r\n")
        #expect(result == "a\r\n    b\r\n        c\r\n")
    }

    @Test("Multi-character units are replaced as units")
    func multiCharacterUnits() {
        let layout = MTLLayoutConfiguration(sourceIndent: "  ", targetIndent: "\t")
        #expect(layout.convert("  a\n    b\n   c\n") == "\ta\n\t\tb\n\t c\n")
    }

    @Test("Conversion is idempotent when the target does not start with the source")
    func idempotentIndentation() {
        let text = "a\n\t\tb\n\t \tc\n      d\n\t/**\n\t * x\n\t */\n"
        for layout in [Layouts.tabsToSpaces, Layouts.spacesToTabs] {
            let once = layout.convert(text)
            #expect(layout.convert(once) == once)
        }
    }

    @Test("A target that starts with the source converts again, so it must be applied once")
    func nonIdempotentWhenTargetStartsWithSource() {
        let layout = MTLLayoutConfiguration(sourceIndent: "  ", targetIndent: "    ")
        let once = layout.convert("  a\n")
        #expect(once == "    a\n")
        #expect(layout.convert(once) == "        a\n")
    }
}

@Suite("MTL Layout: opener placement")
struct MTLLayoutOpenerTests {

    private func convert(_ text: String, _ layout: MTLLayoutConfiguration = Layouts.sameLine) -> String {
        layout.convert(text)
    }

    @Test("Classes and methods")
    func classesAndMethods() {
        #expect(
            convert("class A\n{\n\tvoid f()\n\t{\n\t}\n}\n")
                == "class A {\n\tvoid f() {\n\t}\n}\n")
    }

    @Test("The default placement leaves the text alone")
    func ownLineIsIdentity() {
        let text = "class A\n{\n}\n"
        #expect(MTLLayoutConfiguration().convert(text) == text)
        #expect(MTLLayoutConfiguration().isIdentity)
        #expect(!Layouts.sameLine.isIdentity)
    }

    @Test("Control statements and else")
    func controlStatements() {
        let text = "if (x)\n{\n\ty();\n}\nelse\n{\n\tz();\n}\nwhile (c)\n{\n}\n"
        #expect(convert(text) == "if (x) {\n\ty();\n}\nelse {\n\tz();\n}\nwhile (c) {\n}\n")
    }

    @Test("Try, catch and finally")
    func tryCatchFinally() {
        let text = "try\n{\n\ta();\n}\ncatch (E e)\n{\n\tb();\n}\nfinally\n{\n\tc();\n}\n"
        #expect(convert(text) == "try {\n\ta();\n}\ncatch (E e) {\n\tb();\n}\nfinally {\n\tc();\n}\n")
    }

    @Test("Anonymous classes and nested blocks that follow an opener")
    func anonymousClasses() {
        let text = "r = new R()\n{\n\tvoid run()\n\t{\n\t}\n};\n"
        #expect(convert(text) == "r = new R() {\n\tvoid run() {\n\t}\n};\n")
    }

    @Test("Array initialisers on their own line move; those with content on the line do not")
    func arrayInitialisers() {
        let text = "int[] a =\n{\n\t1, 2\n};\nint[] b = { 1, 2 };\nint[] c = {\n};\n"
        #expect(convert(text) == "int[] a = {\n\t1, 2\n};\nint[] b = { 1, 2 };\nint[] c = {\n};\n")
    }

    @Test("Annotations on earlier lines do not matter")
    func annotations() {
        let text = "@Override\npublic void f()\n{\n}\n"
        #expect(convert(text) == "@Override\npublic void f() {\n}\n")
    }

    @Test("An opener with other text on its line stays")
    func openerWithCompany() {
        let text = "a\n{ b\n}\nc\n}{\n"
        #expect(convert(text) == text)
        #expect(convert("a\n{ // note\n") == "a\n{ // note\n")
    }

    @Test("Empty bodies keep the closer on its own line")
    func emptyBodies() {
        #expect(convert("void f()\n{\n}\n") == "void f() {\n}\n")
        #expect(convert("void f()\n{}\n") == "void f()\n{}\n")
    }

    @Test("Blank lines before an opener and blanks around it are removed")
    func blanksAreRemoved() {
        #expect(convert("void f()  \t\n\n\n\t{ \t\n}\n") == "void f() {\n}\n")
    }

    @Test("An opener with no earlier line, or at the end of the text without a line break, stays")
    func edges() {
        #expect(convert("{\n}\n") == "{\n}\n")
        #expect(convert("\n\n{\n}\n") == "\n\n{\n}\n")
        #expect(convert("a\n{") == "a\n{")
        #expect(convert("a\n{\t") == "a\n{\t")
    }

    @Test("A line that follows a statement terminator keeps its opener, wherever it occurs")
    func terminators() {
        #expect(convert("a;\n{\n\tb;\n}\n") == "a;\n{\n\tb;\n}\n")
        #expect(convert("x\n{\n}\na;\n{\n}\n") == "x {\n}\na;\n{\n}\n")
    }

    @Test("An opener whose previous line ends in an opener stays, so two never share a line")
    func consecutiveOpeners() {
        #expect(convert("a\n{\n{\n}\n}\n") == "a {\n{\n}\n}\n")
        #expect(convert("a {\n{\n}\n}\n") == "a {\n{\n}\n}\n")
        #expect(convert("a\n{\n\n{\n}\n}\n") == "a {\n\n{\n}\n}\n")
    }

    @Test("A closer on the previous line is joined")
    func afterCloser() {
        #expect(convert("}\n\n{\n}\n") == "} {\n}\n")
    }

    @Test("A previous line that ends in a line comment is never joined")
    func previousLineComment() {
        #expect(convert("a // note\n{\n}\n") == "a // note\n{\n}\n")
        #expect(convert("// note\n{\n}\n") == "// note\n{\n}\n")
    }

    @Test("A previous line that ends in a closed block comment is joined")
    func previousBlockComment() {
        #expect(convert("a() /* note */\n{\n}\n") == "a() /* note */ {\n}\n")
    }

    @Test("Openers inside block comments are never moved")
    func openerInBlockComment() {
        let text = "a\n/*\n{\n*/\nb\n"
        #expect(convert(text) == text)
        #expect(convert("a\n/* x\n  {\n*/\n") == "a\n/* x\n  {\n*/\n")
    }

    @Test("A line that ends inside a block comment is never joined")
    func previousInsideBlockComment() {
        let text = "a /* open\n{\n*/\n"
        #expect(convert(text) == text)
    }

    @Test("Openers inside line comments and string and character literals are never moved")
    func openerInLiterals() {
        let text = "a\n// {\nb = \"{\";\nc = '{';\nd\n\"{\"\n"
        #expect(convert(text) == text)
        let multiLine = "x = \"\"\"\n{\n\"\"\"\n"
        #expect(convert(multiLine) == multiLine)
        let afterMultiLine = "x = \"\"\"\ntext\n\"\"\"\n{\n"
        #expect(convert(afterMultiLine) == "x = \"\"\"\ntext\n\"\"\" {\n")
    }

    @Test("Comment markers inside literals do not stop a join")
    func commentMarkerInLiteral() {
        #expect(convert("f(\"a//b\")\n{\n}\n") == "f(\"a//b\") {\n}\n")
    }

    @Test("A literal that is not closed on its line does not swallow the rest")
    func unterminatedLiteral() {
        #expect(convert("it's\nx\n{\n}\n") == "it's\nx {\n}\n")
    }

    @Test("Escaped quotes do not end a literal")
    func escapedQuotes() {
        #expect(convert("f(\"a\\\"{\")\n{\n}\n") == "f(\"a\\\"{\") {\n}\n")
    }

    @Test("CRLF line breaks are understood and preserved")
    func crlf() {
        let text = "class A\r\n{\r\n\tvoid f()\r\n\r\n\t{\r\n\t}\r\n}\r\n"
        #expect(convert(text) == "class A {\r\n\tvoid f() {\r\n\t}\r\n}\r\n")
    }

    @Test("A lone carriage return after an opener is not a line break")
    func loneCarriageReturn() {
        #expect(convert("a\r\n{\rb\r\n") == "a\r\n{\rb\r\n")
    }

    @Test("Conversion combines with indentation conversion")
    func combined() {
        let text = "class A\n{\n\tvoid f()\n\t{\n\t\tx();\n\t}\n}\n"
        #expect(Layouts.compact.convert(text) == "class A {\n  void f() {\n    x();\n  }\n}\n")
    }

    @Test("Opener placement is idempotent")
    func idempotent() {
        let samples = [
            "class A\n{\n\tvoid f()\n\t{\n\t}\n}\n",
            "a\n{\n{\n}\n}\n",
            "a;\n{\n}\nb\n{\n}\n",
            "a // c\n{\n}\nb\n\n{\n}\n",
            "}\n{\n}\n{\n",
            "a\r\n{\r\n}\r\n",
            "x = \"\"\"\n{\n\"\"\"\n{\n",
        ]
        for layout in [Layouts.sameLine, Layouts.compact] {
            for sample in samples {
                let once = layout.convert(sample)
                #expect(layout.convert(once) == once, "\(sample.debugDescription)")
            }
        }
    }

    @Test("The opener token, terminators and comment syntax are data")
    func configurableSyntax() {
        var syntax = MTLMergeSyntax.defaults(for: .braces)
        syntax.opener = "("
        let paren = MTLLayoutConfiguration(openerPlacement: .sameLine, syntax: syntax)
        #expect(paren.convert("call\n(\n\ta\n)\n") == "call (\n\ta\n)\n")
        #expect(paren.convert("call\n{\n}\n") == "call\n{\n}\n")

        var hash = MTLMergeSyntax.defaults(for: .braces)
        hash.lineComments = ["#"]
        let hashed = MTLLayoutConfiguration(openerPlacement: .sameLine, syntax: hash)
        #expect(hashed.convert("a # c\n{\n") == "a # c\n{\n")
        #expect(hashed.convert("a // c\n{\n}\n") == "a // c {\n}\n")

        var colon = MTLMergeSyntax.defaults(for: .braces)
        colon.terminators = [":"]
        let colons = MTLLayoutConfiguration(openerPlacement: .sameLine, syntax: colon)
        #expect(colons.convert("case 1:\n{\n}\na;\n{\n}\n") == "case 1:\n{\n}\na; {\n}\n")
    }

    @Test("Verbatim lines are never changed or joined to")
    func verbatim() {
        let text = "a\n\tkeep\n{\n\tx\n"
        let converter = MTLLayoutConverter(configuration: Layouts.compact)
        let result = converter.convert(text, verbatimLines: [1..<2])
        #expect(result.text == "a\n\tkeep\n{\n  x\n")
        let inside = converter.convert("a\n\t{\n\tb\n", verbatimLines: [1..<2])
        #expect(inside.text == "a\n\t{\n  b\n")
    }

    @Test("The line map follows removed lines")
    func lineMap() {
        let converter = MTLLayoutConverter(configuration: Layouts.sameLine)
        let result = converter.convert("a\nb\n\n{\nc\n}\n")
        #expect(result.text == "a\nb {\nc\n}\n")
        #expect(result.lineMap == [0, 1, 2, 2, 2, 3, 4, 5])
        #expect(result.newLine(forOld: 4) == 2)
        #expect(result.newLine(forOld: 100) == result.lineMap.last)
    }
}

@Suite("MTL Layout: configuration")
struct MTLLayoutConfigurationTests {

    @Test("File patterns scope a configuration")
    func scoping() {
        let all = MTLLayoutConfiguration(filePatterns: [])
        #expect(all.applies(toFile: "anything.txt"))
        let java = MTLLayoutConfiguration(filePatterns: ["*.java"])
        #expect(java.applies(toFile: "src/A.java"))
        #expect(!java.applies(toFile: "plugin.xml"))
    }

    @Test("A post-processor converts matching files only")
    func postProcessor() async throws {
        let processor = MTLLayoutPostProcessor(
            configuration: MTLLayoutConfiguration(
                sourceIndent: "\t", targetIndent: "  ", openerPlacement: .sameLine, filePatterns: ["*.java"]))
        let source = "class A\n{\n\tint x;\n}\n"
        #expect(try await processor.process(source, path: "A.java") == "class A {\n  int x;\n}\n")
        #expect(try await processor.process(source, path: "A.xml") == source)
    }

    @Test("Placements round trip through their names")
    func placementNames() {
        #expect(MTLOpenerPlacement(rawValue: "sameLine") == .sameLine)
        #expect(MTLOpenerPlacement(rawValue: "ownLine") == .ownLine)
        #expect(MTLOpenerPlacement(rawValue: "elsewhere") == nil)
    }

    @Test("Verbatim markers wrap, strip and report the lines they enclose")
    func verbatimMarkers() {
        let wrapped = "a\n" + MTLVerbatimMarkers.wrap("x\ny") + "\nb\n" + MTLVerbatimMarkers.wrap("z\n") + "c\n"
        let stripped = MTLVerbatimMarkers.strip(wrapped)
        #expect(stripped.text == "a\nx\ny\nb\nz\nc\n")
        #expect(stripped.lines == [1..<3, 4..<5])
        #expect(MTLVerbatimMarkers.wrap("").isEmpty)
        #expect(MTLVerbatimMarkers.strip("plain\n").lines.isEmpty)
    }
}
