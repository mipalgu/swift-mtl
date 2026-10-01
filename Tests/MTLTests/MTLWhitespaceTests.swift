//
//  MTLWhitespaceTests.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

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
}
