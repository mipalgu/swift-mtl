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

    // MARK: - Expression Parsing Tests

    @Test("Parse template with variable expression")
    @MainActor
    func testParseVariableExpression() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = """
        [module Test('http://example.com')]
        [template greet(name : String)]
        Hello [name/]!
        [/template]
        """

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["greet"]!

        // Should have 3 statements: "Hello ", expression, "!"
        #expect(template.body.statements.count == 3)

        // Check expression statement
        let exprStmt = template.body.statements[1]
        #expect(exprStmt is MTLExpressionStatement)
    }

    @Test("Parse template with navigation expression")
    @MainActor
    func testParseNavigationExpression() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template showName(person : Person)]Name: [person.name/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["showName"]!

        #expect(template.body.statements.count == 2)
    }

    @Test("Parse template with string literal")
    @MainActor
    func testParseStringLiteral() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()]['Hello, World!'/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        #expect(template.body.statements[0] is MTLExpressionStatement)
    }

    @Test("Parse template with integer literal")
    @MainActor
    func testParseIntegerLiteral() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][42/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
    }

    @Test("Parse template with boolean literal")
    @MainActor
    func testParseBooleanLiteral() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][true/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
    }

    @Test("Parse template with binary expression")
    @MainActor
    func testParseBinaryExpression() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][1 + 2/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
    }

    @Test("Parse template with string concatenation")
    @MainActor
    func testParseStringConcatenation() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template greet(firstName : String, lastName : String)][firstName + ' ' + lastName/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["greet"]!

        #expect(template.body.statements.count == 1)
    }

    @Test("Parse template with comparison expression")
    @MainActor
    func testParseComparisonExpression() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test(age : Integer)][age > 18/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
    }

    @Test("Parse template with logical expression")
    @MainActor
    func testParseLogicalExpression() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test(a : Boolean, b : Boolean)][a and b/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
    }

    @Test("Parse template with parenthesized expression")
    @MainActor
    func testParseParenthesizedExpression() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][(1 + 2) * 3/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
    }

    @Test("Parse template with collection size operation")
    @MainActor
    func testParseCollectionSizeOperation() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test(items : Collection)][items->size()/][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
    }

    // MARK: - Control Flow Tests

    @Test("Parse if statement with true condition")
    @MainActor
    func testParseIfStatementTrue() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][if (true)]YES[/if][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let ifStmt = template.body.statements[0] as? MTLIfStatement else {
            Issue.record("Expected MTLIfStatement")
            return
        }
        #expect(ifStmt.thenBlock.statements.count == 1)
        #expect(ifStmt.elseIfBlocks.isEmpty)
        #expect(ifStmt.elseBlock == nil)
    }

    @Test("Parse if-else statement")
    @MainActor
    func testParseIfElseStatement() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test(x : Integer)][if (x > 10)]BIG[else]SMALL[/if][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let ifStmt = template.body.statements[0] as? MTLIfStatement else {
            Issue.record("Expected MTLIfStatement")
            return
        }
        #expect(ifStmt.thenBlock.statements.count == 1)
        #expect(ifStmt.elseIfBlocks.isEmpty)
        #expect(ifStmt.elseBlock != nil)
        #expect(ifStmt.elseBlock?.statements.count == 1)
    }

    @Test("Parse if-elseif-else statement")
    @MainActor
    func testParseIfElseIfElseStatement() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test(x : Integer)][if (x > 10)]BIG[elseif (x > 5)]MEDIUM[else]SMALL[/if][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let ifStmt = template.body.statements[0] as? MTLIfStatement else {
            Issue.record("Expected MTLIfStatement")
            return
        }
        #expect(ifStmt.thenBlock.statements.count == 1)
        #expect(ifStmt.elseIfBlocks.count == 1)
        #expect(ifStmt.elseBlock != nil)
    }

    @Test("Parse for loop with separator")
    @MainActor
    func testParseForLoopWithSeparator() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test(items : Collection)][for (item in items) separator(', ')][item/][/for][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let forStmt = template.body.statements[0] as? MTLForStatement else {
            Issue.record("Expected MTLForStatement")
            return
        }
        #expect(forStmt.binding.variable.name == "item")
        #expect(forStmt.separator != nil)
        #expect(forStmt.body.statements.count == 1)
    }

    @Test("Parse for loop without separator")
    @MainActor
    func testParseForLoopWithoutSeparator() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test(items : Collection)][for (item in items)][item/][/for][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let forStmt = template.body.statements[0] as? MTLForStatement else {
            Issue.record("Expected MTLForStatement")
            return
        }
        #expect(forStmt.binding.variable.name == "item")
        #expect(forStmt.separator == nil)
        #expect(forStmt.body.statements.count == 1)
    }

    @Test("Parse for loop with type annotation")
    @MainActor
    func testParseForLoopWithType() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test(items : Collection)][for (item : String in items)][item/][/for][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let forStmt = template.body.statements[0] as? MTLForStatement else {
            Issue.record("Expected MTLForStatement")
            return
        }
        #expect(forStmt.binding.variable.name == "item")
        #expect(forStmt.binding.variable.type == "String")
    }

    @Test("Parse let statement with single variable")
    @MainActor
    func testParseLetStatementSingleVariable() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][let greeting = 'Hello']Use [greeting/][/let][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let letStmt = template.body.statements[0] as? MTLLetStatement else {
            Issue.record("Expected MTLLetStatement")
            return
        }
        #expect(letStmt.variables.count == 1)
        #expect(letStmt.variables[0].variable.name == "greeting")
        #expect(letStmt.body.statements.count == 2)  // "Use " and expression
    }

    @Test("Parse let statement with type annotation")
    @MainActor
    func testParseLetStatementWithType() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][let count : Integer = 42][count/][/let][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let letStmt = template.body.statements[0] as? MTLLetStatement else {
            Issue.record("Expected MTLLetStatement")
            return
        }
        #expect(letStmt.variables.count == 1)
        #expect(letStmt.variables[0].variable.name == "count")
        #expect(letStmt.variables[0].variable.type == "Integer")
    }

    @Test("Parse let statement with multiple variables")
    @MainActor
    func testParseLetStatementMultipleVariables() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][let x = 1, y = 2][x/] [y/][/let][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let letStmt = template.body.statements[0] as? MTLLetStatement else {
            Issue.record("Expected MTLLetStatement")
            return
        }
        #expect(letStmt.variables.count == 2)
        #expect(letStmt.variables[0].variable.name == "x")
        #expect(letStmt.variables[1].variable.name == "y")
    }

    @Test("Parse nested control flow")
    @MainActor
    func testParseNestedControlFlow() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test(items : Collection)][for (item in items)][if (item > 0)]POS[else]NEG[/if][/for][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let forStmt = template.body.statements[0] as? MTLForStatement else {
            Issue.record("Expected MTLForStatement")
            return
        }
        #expect(forStmt.body.statements.count == 1)
        guard let ifStmt = forStmt.body.statements[0] as? MTLIfStatement else {
            Issue.record("Expected nested MTLIfStatement")
            return
        }
        #expect(ifStmt.elseBlock != nil)
    }

    // MARK: - Advanced Feature Tests

    @Test("Parse file statement")
    @MainActor
    func testParseFileStatement() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][file ('output.txt', 'overwrite', 'UTF-8')]Content[/file][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let fileStmt = template.body.statements[0] as? MTLFileStatement else {
            Issue.record("Expected MTLFileStatement")
            return
        }
        #expect(fileStmt.mode == .overwrite)
        #expect(fileStmt.body.statements.count == 1)
    }

    @Test("Parse file statement with minimal arguments")
    @MainActor
    func testParseFileStatementMinimal() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][file ('out.txt')]Content[/file][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let fileStmt = template.body.statements[0] as? MTLFileStatement else {
            Issue.record("Expected MTLFileStatement")
            return
        }
        #expect(fileStmt.charset == nil)
    }

    @Test("Parse protected area")
    @MainActor
    func testParseProtectedArea() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][protected ('area1', '//', '//')]Default content[/protected][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let protectedStmt = template.body.statements[0] as? MTLProtectedArea else {
            Issue.record("Expected MTLProtectedArea")
            return
        }
        #expect(protectedStmt.startTagPrefix != nil)
        #expect(protectedStmt.endTagPrefix != nil)
        #expect(protectedStmt.body.statements.count == 1)
    }

    @Test("Parse protected area with minimal arguments")
    @MainActor
    func testParseProtectedAreaMinimal() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][template test()][protected ('area1')]Default[/protected][/template]"

        let module = try await parser.parse(source, filename: "test.mtl")
        let template = module.templates["test"]!

        #expect(template.body.statements.count == 1)
        guard let protectedStmt = template.body.statements[0] as? MTLProtectedArea else {
            Issue.record("Expected MTLProtectedArea")
            return
        }
        #expect(protectedStmt.startTagPrefix == nil)
        #expect(protectedStmt.endTagPrefix == nil)
    }

    @Test("Parse query without parameters")
    @MainActor
    func testParseQueryNoParams() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][query getVersion() : String = '1.0'/]"

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.queries.count == 1)
        guard let query = module.queries["getVersion"] else {
            Issue.record("Expected query 'getVersion'")
            return
        }
        #expect(query.name == "getVersion")
        #expect(query.parameters.isEmpty)
        #expect(query.returnType == "String")
    }

    @Test("Parse query with parameters")
    @MainActor
    func testParseQueryWithParams() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][query fullName(first : String, last : String) : String = first + ' ' + last/]"

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.queries.count == 1)
        guard let query = module.queries["fullName"] else {
            Issue.record("Expected query 'fullName'")
            return
        }
        #expect(query.parameters.count == 2)
        #expect(query.parameters[0].name == "first")
        #expect(query.parameters[1].name == "last")
        #expect(query.returnType == "String")
    }

    @Test("Parse query with visibility")
    @MainActor
    func testParseQueryWithVisibility() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][query private helper() : String = 'help'/]"

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.queries.count == 1)
        guard let query = module.queries["helper"] else {
            Issue.record("Expected query 'helper'")
            return
        }
        #expect(query.visibility == .private)
    }

    @Test("Parse macro without body parameter")
    @MainActor
    func testParseMacroNoBody() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][macro repeat(times : Integer)]Repeated[/macro]"

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.macros.count == 1)
        guard let macro = module.macros["repeat"] else {
            Issue.record("Expected macro 'repeat'")
            return
        }
        #expect(macro.name == "repeat")
        #expect(macro.parameters.count == 1)
        #expect(macro.bodyParameter == nil)
    }

    @Test("Parse macro with body parameter")
    @MainActor
    func testParseMacroWithBody() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][macro wrapper(content : Body)]<div>[content/]</div>[/macro]"

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.macros.count == 1)
        guard let macro = module.macros["wrapper"] else {
            Issue.record("Expected macro 'wrapper'")
            return
        }
        #expect(macro.bodyParameter == "content")
        #expect(macro.parameters.isEmpty)  // Body parameters are separate
    }

    @Test("Parse macro with mixed parameters")
    @MainActor
    func testParseMacroMixedParams() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][macro conditional(flag : Boolean, content : Body)][if (flag)][content/][/if][/macro]"

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.macros.count == 1)
        guard let macro = module.macros["conditional"] else {
            Issue.record("Expected macro 'conditional'")
            return
        }
        #expect(macro.parameters.count == 1)
        #expect(macro.parameters[0].name == "flag")
        #expect(macro.bodyParameter == "content")
    }

    @Test("Parse module with multiple queries and macros")
    @MainActor
    func testParseModuleQueriesAndMacros() async throws {
        let parser = MTLParser(enableDebugging: false)
        let source = "[module Test('http://example.com')][query q1() : String = 'a'/][query q2() : String = 'b'/][macro m1()][/macro][macro m2()][/macro]"

        let module = try await parser.parse(source, filename: "test.mtl")

        #expect(module.queries.count == 2)
        #expect(module.macros.count == 2)
        #expect(module.queries["q1"] != nil)
        #expect(module.queries["q2"] != nil)
        #expect(module.macros["m1"] != nil)
        #expect(module.macros["m2"] != nil)
    }
}
