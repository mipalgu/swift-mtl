//
//  MTLWhitespaceTests.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase
import Testing

@testable import MTL

@Suite("MTL Whitespace Rules")
struct MTLWhitespaceTests {

    @Test("Lines with only block tags produce no output")
    @MainActor
    func standaloneBlockTags() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            [for (x | Sequence{'a', 'b'})]
            - [x/]
            [/for]
            done
            [/template]
            """)
        #expect(output == "- a\n- b\ndone\n")
    }

    @Test("If, elseif and else lines produce no output")
    @MainActor
    func standaloneConditionalTags() async throws {
        let source = """
            [module m('u')/]
            [template main(n : Integer)]
            [if (n = 1)]
            one
            [elseif (n = 2)]
            two
            [else]
            many
            [/if]
            [/template]
            """
        #expect(try await MTLTestSupport.output(source, arguments: [1]) == "one\n")
        #expect(try await MTLTestSupport.output(source, arguments: [2]) == "two\n")
        #expect(try await MTLTestSupport.output(source, arguments: [3]) == "many\n")
    }

    @Test("Indentation around a block tag is removed with its line")
    @MainActor
    func indentedBlockTags() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
                [if (true)]
                text
                [/if]
            [/template]
            """)
        #expect(output == "    text\n")
    }

    @Test("A block that shares its line with text keeps the line break")
    @MainActor
    func inlineBlocks() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            [if (true)]a[/if]
            b[if (true)]c[/if]
            [/template]
            """)
        #expect(output == "a\nbc\n")
    }

    @Test("Lines with an expression tag keep their line break")
    @MainActor
    func expressionLines() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            [1 + 1/]
            [2 + 2/]
            [/template]
            """)
        #expect(output == "2\n4\n")
    }

    @Test("Blank lines are preserved")
    @MainActor
    func blankLines() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            a

            b
            [/template]
            """)
        #expect(output == "a\n\nb\n")
    }

    @Test("Several block tags on a line are removed together")
    @MainActor
    func severalTagsOnOneLine() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            [if (true)][for (x | Sequence{'a'})]
            [x/]
            [/for][/if]
            [/template]
            """)
        #expect(output == "a\n")
    }

    @Test("Comment lines produce no output")
    @MainActor
    func commentLines() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            a
                [comment explains the next line /]
            b
            [-- another comment]
            c
            [/template]
            """)
        #expect(output == "a\nb\nc\n")
    }

    @Test("File blocks on their own lines contribute only their content")
    @MainActor
    func fileBlockLines() async throws {
        let files = try await MTLTestSupport.run("""
            [module m('u')/]
            [template main()]
            [file ('out.txt', false)]
            line one
            line two
            [/file]
            [/template]
            """)
        #expect(files["out.txt"] == "line one\nline two\n")
        #expect(files[MTLTestSupport.standardOutput] == "")
    }

    @Test("Let and macro lines produce no output")
    @MainActor
    func letAndMacroLines() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [macro wrap(content : Body)]
            <[content/]>
            [/macro]
            [template main()]
            [let v = 'x']
            [wrap()]
            [v/]
            [/wrap]
            [/let]
            [/template]
            """)
        #expect(output == "<x\n>\n")
    }

    @Test("Windows line endings are handled like Unix ones")
    @MainActor
    func windowsLineEndings() async throws {
        let source = "[module m('u')/]\r\n[template main()]\r\n[for (x | Sequence{'a'})]\r\n[x/]\r\n[/for]\r\n[/template]\r\n"
        #expect(try await MTLTestSupport.output(source) == "a\r\n")
    }

    @Test("A closing tag at the end of the file needs no line break")
    @MainActor
    func closingTagAtEndOfFile() async throws {
        let output = try await MTLTestSupport.output("[module m('u')/]\n[template main()]\ntext\n[/template]")
        #expect(output == "text\n")
    }

    @Test("The text before the template header is not part of the output")
    @MainActor
    func textOutsideTemplates() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]

            Some stray text

            [template main()]x[/template]
            """)
        #expect(output == "x")
    }

    @Test("Protected area tags on their own lines leave only the markers")
    @MainActor
    func protectedAreaLines() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            [protected ('body')]
            default
            [/protected]
            [/template]
            """)
        #expect(output.contains("default"))
        #expect(output.contains("START PROTECTED REGION body"))
    }

    @Test("Protected area prefixes can be written as clauses")
    @MainActor
    func protectedAreaClauses() async throws {
        let source = """
            [module m('u')/]
            [template main()]
            [protected ('id') startTagPrefix('// ') endTagPrefix('// ')]
            body
            [/protected]
            [/template]
            """
        let module = try await MTLTestSupport.parse(source)
        let area = try #require(module.templates["main"]?.body.statements.first as? MTLProtectedArea)
        #expect(area.startTagPrefix != nil)
        #expect(area.endTagPrefix != nil)
        let output = try await MTLTestSupport.output(source)
        #expect(output.contains("// START PROTECTED REGION id"))
        #expect(output.contains("// END PROTECTED REGION id"))
    }

    @Test("Positional protected area prefixes still work")
    func protectedAreaPositional() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template main()][protected ('id', '#', '#')]x[/protected][/template]
            """)
        let area = try #require(module.templates["main"]?.body.statements.first as? MTLProtectedArea)
        #expect(area.startTagPrefix != nil)
    }

    @Test("A line break after an expression is not duplicated when the result ends with one")
    @MainActor
    func expressionLineBreakNotDuplicated() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            first
            [item('a')/]
            [item('b')/]
            last
            [/template]
            [template item(name : String)]
            item [name/]
            [/template]
            """)
        #expect(output == "first\nitem a\nitem b\nlast\n")
    }

    @Test("A line break after an expression is kept when the result lacks one")
    @MainActor
    func expressionLineBreakKept() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            a: [1 + 1/]
            b: [item('x')/] end
            [/template]
            [template item(name : String)][name/][/template]
            """)
        #expect(output == "a: 2\nb: x end\n")
    }

    @Test("An expression with no result alone on its line produces no line")
    @MainActor
    func emptyExpressionLine() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            before
            [nothing()/]
            after [nothing()/]
            end
            [/template]
            [template nothing()][/template]
            """)
        #expect(output == "before\nafter \nend\n")
    }

    // MARK: - Standard Behaviour

    /// Runs a template with the standard options and returns its standard output.
    ///
    /// - Parameters:
    ///   - source: The module source.
    ///   - main: The name of the template to run.
    ///   - arguments: The template arguments.
    /// - Returns: The standard output.
    @MainActor
    private static func output(
        _ source: String, main: String = "main", arguments: [(any EcoreValue)?] = []
    ) async throws -> String {
        try await MTLTestSupport.output(source, main: main, arguments: arguments, options: .standard)
    }

    // MARK: - Template Bodies and Their Final Line Break

    /// A module whose `body` template ends in the given statements and whose `main` template
    /// calls it on a line of its own, between two lines of text.
    private static func callingBody(_ ending: String) -> String {
        """
        [module m('u')/]
        [template main()]
        a
        [body()/]
        b
        [/template]
        [template body()]
        text
        \(ending)
        [/template]
        [template helper()]
        helper
        [/template]
        """
    }

    @Test("A template body that ends in text keeps the final line break")
    @MainActor
    func bodyEndingInText() async throws {
        let source = Self.callingBody("last")
        #expect(try await Self.output(source, main: "body") == "text\nlast\n")
        #expect(try await Self.output(source) == "a\ntext\nlast\nb\n")
    }

    @Test("A template body that ends in a call keeps one final line break")
    @MainActor
    func bodyEndingInCall() async throws {
        let source = Self.callingBody("[helper()/]")
        #expect(try await Self.output(source, main: "body") == "text\nhelper\n")
        #expect(try await Self.output(source) == "a\ntext\nhelper\nb\n")
    }

    @Test("A template body that ends in a multi-line if keeps the final line break of its content")
    @MainActor
    func bodyEndingInMultiLineIf() async throws {
        let source = Self.callingBody("[if (true)]\nshown\n[/if]")
        #expect(try await Self.output(source, main: "body") == "text\nshown\n")
        #expect(try await Self.output(source) == "a\ntext\nshown\nb\n")
    }

    @Test("A template body that ends in a multi-line if that is not taken ends with the line before")
    @MainActor
    func bodyEndingInSkippedMultiLineIf() async throws {
        let source = Self.callingBody("[if (false)]\nhidden\n[/if]")
        #expect(try await Self.output(source, main: "body") == "text\n")
        #expect(try await Self.output(source) == "a\ntext\nb\n")
    }

    @Test("A template body that ends in a multi-line for keeps the final line break of its content")
    @MainActor
    func bodyEndingInMultiLineFor() async throws {
        let source = Self.callingBody("[for (s | Sequence{'x', 'y'})]\n[s/]\n[/for]")
        #expect(try await Self.output(source, main: "body") == "text\nx\ny\n")
        #expect(try await Self.output(source) == "a\ntext\nx\ny\nb\n")
    }

    // MARK: - Line Breaks After Blocks Written on One Line

    /// A module whose `main` template writes the given line between two lines of text, with a
    /// `line` template whose output ends in a line break.
    private static func writingLine(_ line: String, lineEnding: String = "\n") -> String {
        [
            "[module m('u')/]", "[template main()]", "a", line, "b", "[/template]",
            "[template line(s : String)]", "line [s/]", "[/template]", "",
        ].joined(separator: lineEnding)
    }

    @Test("A call on a line of its own adds no blank line")
    @MainActor
    func standaloneCallLine() async throws {
        let output = try await Self.output(Self.writingLine("[line('x')/]"))
        #expect(output == "a\nline x\nb\n")
    }

    @Test("A one-line if around a call adds no blank line")
    @MainActor
    func inlineIfAroundCall() async throws {
        let output = try await Self.output(Self.writingLine("[if (true)][line('x')/][/if]"))
        #expect(output == "a\nline x\nb\n")
    }

    @Test("A one-line if around text and a call adds no blank line")
    @MainActor
    func inlineIfAroundTextAndCall() async throws {
        let output = try await Self.output(
            Self.writingLine("[if (true)]first [line('x')/][/if]"))
        #expect(output == "a\nfirst line x\nb\n")
    }

    @Test("A one-line for around a call adds no blank line")
    @MainActor
    func inlineForAroundCall() async throws {
        let output = try await Self.output(
            Self.writingLine("[for (s | Sequence{'x', 'y'})][line(s)/][/for]"))
        #expect(output == "a\nline x\nline y\nb\n")
    }

    @Test("Nested one-line blocks around a call add no blank line")
    @MainActor
    func nestedInlineBlocksAroundCall() async throws {
        let output = try await Self.output(
            Self.writingLine("[for (s | Sequence{'x', 'y'})][if (s <> 'z')][line(s)/][/if][/for]"))
        #expect(output == "a\nline x\nline y\nb\n")
    }

    @Test("A one-line let around a call adds no blank line")
    @MainActor
    func inlineLetAroundCall() async throws {
        let output = try await Self.output(Self.writingLine("[let v = 'x'][line(v)/][/let]"))
        #expect(output == "a\nline x\nb\n")
    }

    @Test("A one-line if around a call adds no blank line with Windows line endings")
    @MainActor
    func inlineIfAroundCallWithWindowsLineEndings() async throws {
        let output = try await Self.output(
            Self.writingLine("[if (true)][line('x')/][/if]", lineEnding: "\r\n"))
        #expect(output == "a\r\nline x\r\nb\r\n")
    }

    @Test("A one-line if that produces nothing alone on its line produces no line")
    @MainActor
    func emptyInlineIfLine() async throws {
        let output = try await Self.output(Self.writingLine("[if (false)][line('x')/][/if]"))
        #expect(output == "a\nb\n")
    }

    @Test("A one-line if that produces nothing after text keeps the line break")
    @MainActor
    func emptyInlineIfAfterText() async throws {
        let output = try await Self.output(
            Self.writingLine("before [if (false)][line('x')/][/if]"))
        #expect(output == "a\nbefore \nb\n")
    }

    @Test("A one-line if whose output does not end a line keeps the line break")
    @MainActor
    func inlineIfWithoutLineBreak() async throws {
        let output = try await Self.output(Self.writingLine("[if (true)]x[/if]"))
        #expect(output == "a\nx\nb\n")
    }

    @Test("A block closed after text on its last line does not duplicate the line break")
    @MainActor
    func blockClosedAfterText() async throws {
        let source = """
            [module m('u')/]
            [template main(n : Integer)]
            a
            [if (n = 1)]
            shown[/if]
            b
            [/template]
            """
        #expect(try await Self.output(source, arguments: [1]) == "a\nshown\nb\n")
        #expect(try await Self.output(source, arguments: [2]) == "a\nb\n")
    }

    @Test("A blank line after a block on lines of its own is kept")
    @MainActor
    func blankLineAfterStandaloneBlock() async throws {
        let output = try await Self.output("""
            [module m('u')/]
            [template main()]
            [if (true)]
            x
            [/if]

            y
            [/template]
            """)
        #expect(output == "x\n\ny\n")
    }

    // MARK: - Lines of Blocks That Produce Nothing

    @Test("A one-line if that is not taken before text keeps the text and its line break")
    @MainActor
    func untakenInlineIfBeforeText() async throws {
        let output = try await Self.output(Self.writingLine("[if (false)]x[/if] after"))
        #expect(output == "a\n after\nb\n")
    }

    @Test("A one-line if that is not taken between texts keeps the line")
    @MainActor
    func untakenInlineIfBetweenTexts() async throws {
        let output = try await Self.output(Self.writingLine("before [if (false)]x[/if] after"))
        #expect(output == "a\nbefore  after\nb\n")
    }

    @Test("A one-line if that is not taken after white space keeps the line like an expression")
    @MainActor
    func untakenInlineIfAfterWhiteSpace() async throws {
        let block = try await Self.output(Self.writingLine("  [if (false)]x[/if]"))
        let expression = try await Self.output(Self.writingLine("  [''/]"))
        #expect(block == "a\n  \nb\n")
        #expect(block == expression)
    }

    @Test("A one-line if whose else branch writes nothing produces no line")
    @MainActor
    func inlineElseWritingNothing() async throws {
        let output = try await Self.output(Self.writingLine("[if (false)]x[else][''/][/if]"))
        #expect(output == "a\nb\n")
    }

    @Test("A one-line if around an expression with no result produces no line")
    @MainActor
    func inlineIfAroundEmptyExpression() async throws {
        let output = try await Self.output(Self.writingLine("[if (true)][''/][/if]"))
        #expect(output == "a\nb\n")
    }

    @Test("A one-line for over an empty collection produces no line")
    @MainActor
    func inlineForOverEmptyCollection() async throws {
        let output = try await Self.output(
            Self.writingLine("[for (s | Sequence{'x', 'y'}->select(e | e = 'z'))][s/][/for]"))
        #expect(output == "a\nb\n")
    }

    @Test("A one-line for whose body writes nothing produces no line")
    @MainActor
    func inlineForWritingNothing() async throws {
        let output = try await Self.output(
            Self.writingLine("[for (s | Sequence{'x', 'y'})][if (s = 'z')][s/][/if][/for]"))
        #expect(output == "a\nb\n")
    }

    @Test("A one-line for over a collection writes its items on the line")
    @MainActor
    func inlineForOverCollection() async throws {
        let output = try await Self.output(Self.writingLine("[for (s | Sequence{'x', 'y'})][s/][/for]"))
        #expect(output == "a\nxy\nb\n")
    }

    @Test("A one-line let that writes nothing produces no line")
    @MainActor
    func inlineLetWritingNothing() async throws {
        let output = try await Self.output(Self.writingLine("[let v = ''][v/][/let]"))
        #expect(output == "a\nb\n")
    }

    @Test("Several one-line blocks that produce nothing produce no lines")
    @MainActor
    func consecutiveEmptyInlineBlocks() async throws {
        let output = try await Self.output("""
            [module m('u')/]
            [template main()]
            [if (false)]x[/if]
            [for (s | Sequence{'x'}->select(e | e = 'z'))][s/][/for]
            a
            [if (false)]y[/if]
            [/template]
            """)
        #expect(output == "a\n")
    }

    @Test("A blank line after a one-line block that produces nothing is kept")
    @MainActor
    func blankLineAfterEmptyInlineBlock() async throws {
        let output = try await Self.output("""
            [module m('u')/]
            [template main()]
            a
            [if (false)]x[/if]

            b
            [/template]
            """)
        #expect(output == "a\n\nb\n")
    }

    @Test("A block that starts on its own line and produces nothing produces no line")
    @MainActor
    func emptyBlockStartingOnItsOwnLine() async throws {
        let source = """
            [module m('u')/]
            [template main(n : Integer)]
            a
            [if (n = 1)]
            shown[/if]
            b
            [if (n = 1)]
            shown[/if] after
            c
            [/template]
            """
        #expect(try await Self.output(source, arguments: [2]) == "a\nb\n after\nc\n")
    }

    @Test("A one-line if that is not taken produces no line with Windows line endings")
    @MainActor
    func untakenInlineIfWithWindowsLineEndings() async throws {
        let output = try await Self.output(
            Self.writingLine("[if (false)][line('x')/][/if]", lineEnding: "\r\n"))
        #expect(output == "a\r\nb\r\n")
    }

    @Test("A one-line if that is not taken in a called template produces no line")
    @MainActor
    func untakenInlineIfInCalledTemplate() async throws {
        let output = try await Self.output("""
            [module m('u')/]
            [template main()]
            a
            [body()/]
            b
            [/template]
            [template body()]
            [if (false)]x[/if]
            text
            [/template]
            """)
        #expect(output == "a\ntext\nb\n")
    }
}
