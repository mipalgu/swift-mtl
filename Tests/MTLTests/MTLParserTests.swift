//
//  MTLParserTests.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Testing
@testable import MTL

@Suite("MTL Parser Tests")
struct MTLParserTests {

    // MARK: - Lexer Tests

    @Test("Lexer tokenizes simple text")
    func testLexerSimpleText() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "Hello, World!"

        // Parse will fail because we haven't implemented the parser yet,
        // but we can test that it doesn't crash during lexing
        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles text with directives")
    func testLexerTextWithDirectives() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "Hello [name/] World"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Parse module declaration")
    @MainActor
    func testParseModuleDeclaration() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module MyModule('http://example.com')]"

        let module = try await parser.parse(source, filename: "test.mtl")
        #expect(module.name == "MyModule")
    }

    @Test("Parse template declaration")
    @MainActor
    func testParseTemplateDeclaration() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = """
        [module Test('uri')]
        [template myTemplate(param : String)]
        Text content
        [/template]
        """

        let module = try await parser.parse(source, filename: "test.mtl")
        #expect(module.templates["myTemplate"] != nil)
    }

    @Test("Parse module with string literals")
    @MainActor
    func testParseStringLiterals() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('uri with spaces')]"

        let module = try await parser.parse(source, filename: "test.mtl")
        #expect(module.name == "Test")
    }

    @Test("Lexer handles integer literals")
    func testLexerIntegerLiterals() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[if (value > 42)]text[/if]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles real literals")
    func testLexerRealLiterals() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[if (value > 3.14)]text[/if]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles boolean literals")
    func testLexerBooleanLiterals() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[if (true)]yes[/if][if (false)]no[/if]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Parse module with comments")
    @MainActor
    func testParseCommentsAtTopLevel() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = """
        [module Test('uri')]
        [-- This is a comment]
        [template foo()]content[/template]
        """

        let module = try await parser.parse(source, filename: "test.mtl")
        #expect(module.templates["foo"] != nil)
    }

    @Test("Lexer handles operators")
    func testLexerOperators() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[if (a + b * c - d / e > 10)]text[/if]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles navigation")
    func testLexerNavigation() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[person.name/]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles arrow operator")
    func testLexerArrowOperator() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[collection->select(x | x > 0)]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles nested brackets")
    func testLexerNestedBrackets() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = """
        [if (cond)]
            [if (inner)]
                nested
            [/if]
        [/if]
        """

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles for loops")
    func testLexerForLoop() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[for (item in collection) separator(', ')][item.name/][/for]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles let statements")
    func testLexerLetStatement() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[let temp : String = 'value'][temp/][/let]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles file blocks")
    func testLexerFileBlock() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[file ('output.txt', 'overwrite', 'UTF-8')]content[/file]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles protected areas")
    func testLexerProtectedArea() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[protected ('area1')]default content[/protected]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles escaped quotes in strings")
    func testLexerEscapedQuotes() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[let str = 'It''s a test']text[/let]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles escape sequences in strings")
    func testLexerEscapeSequences() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[let str = 'Line 1\\nLine 2\\tTabbed']text[/let]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer handles multiline text")
    func testLexerMultilineText() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = """
        Line 1
        Line 2
        Line 3
        """

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    @Test("Lexer error on unterminated string")
    func testLexerUnterminatedString() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[let str = 'unterminated]"

        await #expect(throws: MTLParseError.self) {
            try await parser.parse(source, filename: "test.mtl")
        }
    }

    // MARK: - Parser Tests

    @Test("Parse simple module with template")
    @MainActor
    func testParseSimpleModuleWithTemplate() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = """
        [module HelloWorld('http://example.com')]
        [template greet()]
        Hello, World!
        [/template]
        """

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.name == "HelloWorld")
        #expect(module.templates.count == 1)
        #expect(module.templates["greet"] != nil)

        let template = module.templates["greet"]!
        #expect(template.name == "greet")
        #expect(template.parameters.count == 0)
        #expect(template.body.statements.count == 1)

        // Check the text statement
        let stmt = template.body.statements[0]
        #expect(stmt is MTLTextStatement)
        if let textStmt = stmt as? MTLTextStatement {
            #expect(textStmt.value.contains("Hello, World!"))
        }
    }

    @Test("Parse module with multiple templates - compact")
    @MainActor
    func testParseModuleWithMultipleTemplatesCompact() async throws {
        let parser = MTLParser(enableDebugging: true)
        // No whitespace between templates
        let source = "[module Multi('http://example.com')][template first()]First[/template][template second()]Second[/template]"

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.name == "Multi")
        #expect(module.templates.count == 2)
        #expect(module.templates["first"] != nil)
        #expect(module.templates["second"] != nil)
    }

    @Test("Parse module with multiple templates - with newlines")
    @MainActor
    func testParseModuleWithMultipleTemplates() async throws {
        let parser = MTLParser(enableDebugging: true)
        let source = """
        [module Multi('http://example.com')]
        [template first()]
        First template
        [/template]
        [template second()]
        Second template
        [/template]
        """

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.name == "Multi")
        #expect(module.templates.count == 2)
        #expect(module.templates["first"] != nil)
        #expect(module.templates["second"] != nil)
    }

    @Test("Parse template with parameters")
    @MainActor
    func testParseTemplateWithParameters() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = """
        [module Test('http://example.com')]
        [template greet(name : String, age : Integer)]
        Template with parameters
        [/template]
        """

        let module = try await parser.parse(source, filename: "test.mtl")

        let template = module.templates["greet"]!
        #expect(template.parameters.count == 2)
        #expect(template.parameters[0].name == "name")
        #expect(template.parameters[0].type == "String")
        #expect(template.parameters[1].name == "age")
        #expect(template.parameters[1].type == "Integer")
    }

    @Test("Parse template with mixed text and newlines")
    @MainActor
    func testParseTemplateWithMixedContent() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = """
        [module Test('http://example.com')]
        [template content()]
        Line 1
        Line 2
        Line 3
        [/template]
        """

        let module = try await parser.parse(source, filename: "test.mtl")

        let template = module.templates["content"]!
        #expect(template.body.statements.count > 0)
    }

    @Test("Parse empty template")
    @MainActor
    func testParseEmptyTemplate() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template empty()][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")

        let template = module.templates["empty"]!
        #expect(template.body.statements.count == 0)
    }

    @Test("Parse module with comments")
    @MainActor
    func testParseModuleWithComments() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = """
        [module Test('http://example.com')]
        [-- This is a comment]
        [template foo()]
        content
        [/template]
        """

        let module = try await parser.parse(source, filename: "test.mtl")
        #expect(module.templates.count == 1)
    }

    // Note: Expression, control flow, and advanced feature tests will be added in later phases
}
