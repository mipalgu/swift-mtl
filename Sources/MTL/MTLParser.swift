//
//  MTLParser.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//
import Foundation
import ECore
import EMFBase
import AQL
import OrderedCollections

// MARK: - Parse Error Helpers

/// Helper to format parse errors with line and column information.
private func parseError(_ message: String, line: Int, column: Int) -> MTLParseError {
    return .invalidSyntax("Line \(line), column \(column): \(message)")
}

// MARK: - Token Types

/// Token types for MTL lexical analysis.
private enum MTLTokenType: Equatable {
    // Text content (outside directives)
    case text(String)

    // Delimiters
    case leftBracket        // [
    case rightBracket       // ]
    case slash              // /
    case leftParen          // (
    case rightParen         // )
    case comma              // ,
    case colon              // :
    case dot                // .
    case pipe               // |
    case questionMark       // ?

    // Keywords
    case keyword(String)    // module, template, query, if, for, etc.

    // Identifiers and literals
    case identifier(String)
    case stringLiteral(String)
    case integerLiteral(Int)
    case realLiteral(Double)
    case booleanLiteral(Bool)

    // Operators
    case `operator`(String) // +, -, *, /, =, <>, <, >, etc.

    // Special
    case comment(String)
    case whitespace
    case newline
    case eof

    var isWhitespace: Bool {
        switch self {
        case .whitespace, .newline:
            return true
        default:
            return false
        }
    }
}

// MARK: - Token

/// A token with its type, value, and position information.
private struct MTLToken: Equatable {
    let type: MTLTokenType
    let line: Int
    let column: Int

    var isWhitespace: Bool { type.isWhitespace }
}

// MARK: - Lexer

/// Lexer for MTL with dual-mode tokenization.
///
/// The lexer operates in two modes:
/// - TEXT mode: Accumulates literal text until `[` is encountered
/// - DIRECTIVE mode: Standard tokenization inside `[...]` blocks
private actor MTLLexer {

    // MARK: - Lexing Mode

    enum LexingMode {
        case text       // Outside directives, accumulate text
        case directive  // Inside directives, tokenize normally
    }

    // MARK: - Keywords

    static let keywords: Set<String> = [
        // Module and imports
        "module", "import", "extends",

        // Templates and queries
        "template", "query", "macro",

        // Visibility
        "public", "private", "protected",

        // Control flow
        "if", "elseif", "else", "for", "let",

        // File operations
        "file",

        // Protected areas
        "protected",

        // Special
        "main", "post", "guard", "overrides",

        // Separators
        "separator",

        // File modes
        "overwrite", "append", "create",

        // Boolean
        "true", "false",

        // OCL/AQL operations (commonly used in MTL)
        "in", "and", "or", "not", "xor", "implies",
        "select", "reject", "collect", "forAll", "exists", "any",
        "size", "isEmpty", "notEmpty", "first", "last",
        "oclIsKindOf", "oclIsTypeOf", "oclAsType"
    ]

    // MARK: - Operators

    static let operators: Set<String> = [
        "+", "-", "*", "/", "%",
        "=", "<>", "<", ">", "<=", ">=",
        "and", "or", "not", "xor", "implies",
        "->", "."
    ]

    // MARK: - Properties

    private let input: String
    private var position: String.Index
    private var line: Int = 1
    private var column: Int = 1
    private var mode: LexingMode = .text
    private var textBuffer: String = ""
    private let enableDebugging: Bool

    // MARK: - Initialization

    init(_ input: String, enableDebugging: Bool = false) {
        self.input = input
        self.position = input.startIndex
        self.enableDebugging = enableDebugging
    }

    // MARK: - Tokenization

    func tokenize() throws -> [MTLToken] {
        var tokens: [MTLToken] = []

        while position < input.endIndex {
            switch mode {
            case .text:
                try tokenizeText(&tokens)
            case .directive:
                try tokenizeDirective(&tokens)
            }
        }

        // Flush any remaining text
        if !textBuffer.isEmpty {
            tokens.append(MTLToken(type: .text(textBuffer), line: line, column: column))
            textBuffer = ""
        }

        tokens.append(MTLToken(type: .eof, line: line, column: column))

        if enableDebugging {
            debugPrint("Tokenized \(tokens.count) tokens")
        }

        return tokens
    }

    // MARK: - Text Mode Tokenization

    private func tokenizeText(_ tokens: inout [MTLToken]) throws {
        let char = input[position]

        if char == "[" {
            // Flush text buffer
            if !textBuffer.isEmpty {
                tokens.append(MTLToken(type: .text(textBuffer), line: line, column: column - textBuffer.count))
                textBuffer = ""
            }

            // Switch to directive mode
            mode = .directive
            tokens.append(MTLToken(type: .leftBracket, line: line, column: column))
            advance()
        } else {
            // Accumulate text
            textBuffer.append(char)
            advance()
        }
    }

    // MARK: - Directive Mode Tokenization

    private func tokenizeDirective(_ tokens: inout [MTLToken]) throws {
        skipWhitespace()

        guard position < input.endIndex else { return }

        let char = input[position]
        let tokenLine = line
        let tokenColumn = column

        // Comments
        if char == "-" && peek() == "-" {
            try tokenizeComment(&tokens)
            return
        }

        // Right bracket - switch back to text mode
        if char == "]" {
            tokens.append(MTLToken(type: .rightBracket, line: tokenLine, column: tokenColumn))
            advance()
            mode = .text
            return
        }

        // String literals
        if char == "'" {
            try tokenizeString(&tokens)
            return
        }

        // Numbers
        if char.isNumber || (char == "-" && peek()?.isNumber == true) {
            try tokenizeNumber(&tokens)
            return
        }

        // Identifiers and keywords
        if char.isLetter || char == "_" {
            try tokenizeIdentifierOrKeyword(&tokens)
            return
        }

        // Operators and punctuation
        try tokenizeOperatorOrPunctuation(&tokens)
    }

    // MARK: - Specific Token Types

    private func tokenizeComment(_ tokens: inout [MTLToken]) throws {
        let tokenLine = line
        let tokenColumn = column
        var comment = ""

        // Skip --
        advance()
        advance()

        // Read until newline or ]
        while position < input.endIndex {
            let char = input[position]
            if char == "\n" || char == "]" {
                break
            }
            comment.append(char)
            advance()
        }

        tokens.append(MTLToken(type: .comment(comment.trimmingCharacters(in: .whitespaces)), line: tokenLine, column: tokenColumn))
    }

    private func tokenizeString(_ tokens: inout [MTLToken]) throws {
        let tokenLine = line
        let tokenColumn = column
        var string = ""

        // Skip opening '
        advance()

        while position < input.endIndex {
            let char = input[position]

            if char == "'" {
                // Check for escaped quote ''
                if peek() == "'" {
                    string.append("'")
                    advance()
                    advance()
                } else {
                    // End of string
                    advance()
                    tokens.append(MTLToken(type: .stringLiteral(string), line: tokenLine, column: tokenColumn))
                    return
                }
            } else if char == "\\" {
                // Escape sequences
                advance()
                guard position < input.endIndex else {
                    throw parseError("Unterminated string literal", line: tokenLine, column: tokenColumn)
                }
                let escaped = input[position]
                switch escaped {
                case "n": string.append("\n")
                case "t": string.append("\t")
                case "r": string.append("\r")
                case "\\": string.append("\\")
                case "'": string.append("'")
                default: string.append(escaped)
                }
                advance()
            } else {
                string.append(char)
                advance()
            }
        }

        throw parseError("Unterminated string literal", line: tokenLine, column: tokenColumn)
    }

    private func tokenizeNumber(_ tokens: inout [MTLToken]) throws {
        let tokenLine = line
        let tokenColumn = column
        var number = ""
        var hasDecimal = false

        // Handle negative sign
        if input[position] == "-" {
            number.append("-")
            advance()
        }

        // Read digits
        while position < input.endIndex {
            let char = input[position]
            if char.isNumber {
                number.append(char)
                advance()
            } else if char == "." && !hasDecimal && peek()?.isNumber == true {
                hasDecimal = true
                number.append(char)
                advance()
            } else {
                break
            }
        }

        if hasDecimal {
            guard let value = Double(number) else {
                throw parseError("Invalid real number: \(number)", line: tokenLine, column: tokenColumn)
            }
            tokens.append(MTLToken(type: .realLiteral(value), line: tokenLine, column: tokenColumn))
        } else {
            guard let value = Int(number) else {
                throw parseError("Invalid integer: \(number)", line: tokenLine, column: tokenColumn)
            }
            tokens.append(MTLToken(type: .integerLiteral(value), line: tokenLine, column: tokenColumn))
        }
    }

    private func tokenizeIdentifierOrKeyword(_ tokens: inout [MTLToken]) throws {
        let tokenLine = line
        let tokenColumn = column
        var identifier = ""

        while position < input.endIndex {
            let char = input[position]
            if char.isLetter || char.isNumber || char == "_" {
                identifier.append(char)
                advance()
            } else {
                break
            }
        }

        // Check for boolean literals
        if identifier == "true" {
            tokens.append(MTLToken(type: .booleanLiteral(true), line: tokenLine, column: tokenColumn))
        } else if identifier == "false" {
            tokens.append(MTLToken(type: .booleanLiteral(false), line: tokenLine, column: tokenColumn))
        } else if Self.keywords.contains(identifier) {
            tokens.append(MTLToken(type: .keyword(identifier), line: tokenLine, column: tokenColumn))
        } else {
            tokens.append(MTLToken(type: .identifier(identifier), line: tokenLine, column: tokenColumn))
        }
    }

    private func tokenizeOperatorOrPunctuation(_ tokens: inout [MTLToken]) throws {
        let tokenLine = line
        let tokenColumn = column
        let char = input[position]

        // Multi-character operators
        if char == "-" && peek() == ">" {
            tokens.append(MTLToken(type: .operator("->"), line: tokenLine, column: tokenColumn))
            advance()
            advance()
            return
        }

        if char == "<" && peek() == ">" {
            tokens.append(MTLToken(type: .operator("<>"), line: tokenLine, column: tokenColumn))
            advance()
            advance()
            return
        }

        if char == "<" && peek() == "=" {
            tokens.append(MTLToken(type: .operator("<="), line: tokenLine, column: tokenColumn))
            advance()
            advance()
            return
        }

        if char == ">" && peek() == "=" {
            tokens.append(MTLToken(type: .operator(">="), line: tokenLine, column: tokenColumn))
            advance()
            advance()
            return
        }

        // Single-character tokens
        switch char {
        case "/":
            tokens.append(MTLToken(type: .slash, line: tokenLine, column: tokenColumn))
            advance()
        case "(":
            tokens.append(MTLToken(type: .leftParen, line: tokenLine, column: tokenColumn))
            advance()
        case ")":
            tokens.append(MTLToken(type: .rightParen, line: tokenLine, column: tokenColumn))
            advance()
        case ",":
            tokens.append(MTLToken(type: .comma, line: tokenLine, column: tokenColumn))
            advance()
        case ":":
            tokens.append(MTLToken(type: .colon, line: tokenLine, column: tokenColumn))
            advance()
        case ".":
            tokens.append(MTLToken(type: .dot, line: tokenLine, column: tokenColumn))
            advance()
        case "|":
            tokens.append(MTLToken(type: .pipe, line: tokenLine, column: tokenColumn))
            advance()
        case "?":
            tokens.append(MTLToken(type: .questionMark, line: tokenLine, column: tokenColumn))
            advance()
        case "+", "-", "*", "=", "<", ">":
            tokens.append(MTLToken(type: .operator(String(char)), line: tokenLine, column: tokenColumn))
            advance()
        default:
            throw parseError("Unexpected character: '\(char)'", line: tokenLine, column: tokenColumn)
        }
    }

    // MARK: - Helper Methods

    private func advance() {
        guard position < input.endIndex else { return }

        let char = input[position]
        if char == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }

        position = input.index(after: position)
    }

    private func peek() -> Character? {
        let nextPosition = input.index(after: position)
        guard nextPosition < input.endIndex else { return nil }
        return input[nextPosition]
    }

    private func skipWhitespace() {
        while position < input.endIndex {
            let char = input[position]
            if char.isWhitespace {
                advance()
            } else {
                break
            }
        }
    }

    private func debugPrint(_ message: String) {
        if enableDebugging {
            print("[MTLLexer] \(message)")
        }
    }
}

// MARK: - Public Parser Interface

/// Parser for MTL (Model-to-Text Language) templates.
///
/// Parses MTL template files into MTLModule AST structures that can be
/// executed by MTLGenerator.
///
/// ## Usage
///
/// ```swift
/// let parser = MTLParser()
/// let module = try await parser.parse(URL(fileURLWithPath: "template.mtl"))
/// ```
public actor MTLParser {

    // MARK: - Properties

    private let enableDebugging: Bool

    // MARK: - Initialization

    public init(enableDebugging: Bool = false) {
        self.enableDebugging = enableDebugging
    }

    // MARK: - Parsing

    /// Parses an MTL template file.
    ///
    /// - Parameter url: URL of the MTL file to parse
    /// - Returns: Parsed MTLModule
    /// - Throws: MTLParseError if parsing fails
    public func parse(_ url: URL) async throws -> MTLModule {
        debugPrint("Parsing MTL file: \(url.path)")

        // Read file
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw MTLResourceError.loadError("Could not read file: \(url.path)")
        }

        return try await parse(contents, filename: url.lastPathComponent)
    }

    /// Parses MTL template source code.
    ///
    /// - Parameters:
    ///   - source: MTL template source code
    ///   - filename: Optional filename for error messages
    /// - Returns: Parsed MTLModule
    /// - Throws: MTLParseError if parsing fails
    public func parse(_ source: String, filename: String = "<input>") async throws -> MTLModule {
        debugPrint("Parsing MTL source (\(source.count) characters)")

        // Tokenize
        let lexer = MTLLexer(source, enableDebugging: enableDebugging)
        let tokens = try await lexer.tokenize()

        debugPrint("Tokenization complete: \(tokens.count) tokens")

        // Parse
        let parser = MTLSyntaxParser(tokens: tokens, enableDebugging: enableDebugging)
        return try await parser.parseModule()
    }

    // MARK: - Debugging

    private func debugPrint(_ message: String) {
        if enableDebugging {
            print("[MTLParser] \(message)")
        }
    }
}

// MARK: - Syntax Parser

/// Recursive descent parser for MTL syntax.
private actor MTLSyntaxParser {

    // MARK: - Properties

    private let tokens: [MTLToken]
    private var position: Int = 0
    private let enableDebugging: Bool

    // MARK: - Initialization

    init(tokens: [MTLToken], enableDebugging: Bool = false) {
        self.tokens = tokens.filter { !$0.isWhitespace }  // Skip whitespace tokens
        self.enableDebugging = enableDebugging
    }

    // MARK: - Module Parsing

    func parseModule() throws -> MTLModule {
        debugPrint("Parsing module")

        // Parse module header: [module moduleName('uri')]
        let (moduleName, metamodelURI) = try parseModuleHeader()

        debugPrint("Module: \(moduleName), URI: \(metamodelURI)")

        // Parse module contents
        var templates: OrderedDictionary<String, MTLTemplate> = [:]
        var queries: OrderedDictionary<String, MTLQuery> = [:]
        var macros: OrderedDictionary<String, MTLMacro> = [:]
        var imports: [String] = []
        var extendsModule: String? = nil

        // Parse top-level declarations
        while let token = current(), token.type != .eof {
            debugPrint("Parsing token: \(token.type)")

            switch token.type {
            case .leftBracket:
                advance()
                guard let next = current() else {
                    throw error("Unexpected end of input after '['")
                }

                switch next.type {
                case .keyword("template"):
                    advance()  // Consume 'template' keyword
                    debugPrint("About to parse template, current token: \(current()?.type ?? .eof)")
                    let template = try parseTemplate()
                    if templates[template.name] != nil {
                        throw error("Duplicate template: \(template.name)")
                    }
                    templates[template.name] = template

                case .keyword("query"):
                    advance()  // Consume 'query' keyword
                    let query = try parseQuery()
                    if queries[query.name] != nil {
                        throw error("Duplicate query: \(query.name)")
                    }
                    queries[query.name] = query

                case .keyword("macro"):
                    advance()  // Consume 'macro' keyword
                    let macro = try parseMacro()
                    if macros[macro.name] != nil {
                        throw error("Duplicate macro: \(macro.name)")
                    }
                    macros[macro.name] = macro

                case .keyword("import"):
                    advance()  // Consume 'import' keyword
                    let importModule = try parseImport()
                    imports.append(importModule)

                case .keyword("extends"):
                    advance()  // Consume 'extends' keyword
                    extendsModule = try parseExtends()

                case .comment:
                    // Skip comments
                    advance()
                    try expect(.rightBracket)

                default:
                    throw error("Unexpected keyword in module scope: \(next.type)")
                }

            case .text:
                // Skip top-level text (whitespace, etc.)
                advance()

            default:
                throw error("Unexpected token in module scope: \(token.type)")
            }
        }

        // Build module
        // Note: Metamodel packages will be loaded separately by the CLI or runtime
        // The parser only captures the URI, actual EPackage loading happens during execution
        let module = MTLModule(
            name: moduleName,
            metamodels: [:],  // Empty - will be populated when models are loaded
            extends: extendsModule,
            imports: imports,
            templates: templates,
            queries: queries,
            macros: macros,
            encoding: "UTF-8"
        )

        debugPrint("Module parsing complete: \(templates.count) templates, \(queries.count) queries, \(macros.count) macros")

        return module
    }

    /// Parses module header: [module name('uri')]
    private func parseModuleHeader() throws -> (name: String, uri: String) {
        // Expect [module
        try expect(.leftBracket)
        try expectKeyword("module")

        // Parse module name
        guard case .identifier(let moduleName) = current()?.type else {
            throw error("Expected module name")
        }
        advance()

        // Expect (
        try expect(.leftParen)

        // Parse URI
        guard case .stringLiteral(let uri) = current()?.type else {
            throw error("Expected module URI string literal")
        }
        advance()

        // Expect )
        try expect(.rightParen)

        // Expect ]
        try expect(.rightBracket)

        return (moduleName, uri)
    }

    // MARK: - Template Parsing

    /// Parses a template declaration.
    /// Note: '[template' has already been consumed
    private func parseTemplate() throws -> MTLTemplate {
        debugPrint("Parsing template")

        // Parse signature
        let signature = try parseTemplateSignature()

        // Parse optional guard
        var guardCondition: MTLExpression? = nil
        if case .keyword("guard") = current()?.type {
            advance()
            try expect(.leftParen)
            guardCondition = try parseExpression()
            try expect(.rightParen)
        }

        // Expect ]
        try expect(.rightBracket)

        // Parse body
        let body = try parseTemplateBody()

        // Expect [/template]
        try expect(.leftBracket)
        try expect(.slash)
        try expectKeyword("template")
        try expect(.rightBracket)

        return MTLTemplate(
            name: signature.name,
            visibility: signature.visibility,
            parameters: signature.parameters,
            guard: guardCondition,
            post: nil,  // Post conditions not yet implemented
            body: body,
            isMain: signature.isMain,
            overrides: nil,
            documentation: nil
        )
    }

    /// Parses template signature: name(param1 : Type1, ...) or name()
    private func parseTemplateSignature() throws -> (name: String, visibility: MTLVisibility, parameters: [MTLVariable], isMain: Bool) {
        // Parse name (allow keywords as names in this context)
        let name: String
        switch current()?.type {
        case .identifier(let id):
            name = id
            advance()
        case .keyword(let kw):
            // Allow keywords to be used as template names
            name = kw
            advance()
        default:
            throw error("Expected template name")
        }

        // Parse parameters
        try expect(.leftParen)
        var parameters: [MTLVariable] = []

        while current()?.type != .rightParen {
            // Parse parameter name (allow keywords)
            let paramName: String
            switch current()?.type {
            case .identifier(let id):
                paramName = id
            case .keyword(let kw):
                paramName = kw
            default:
                throw error("Expected parameter name")
            }
            advance()

            // Expect :
            try expect(.colon)

            // Parse type (allow keywords)
            let typeName: String
            switch current()?.type {
            case .identifier(let id):
                typeName = id
            case .keyword(let kw):
                typeName = kw
            default:
                throw error("Expected parameter type")
            }
            advance()

            parameters.append(MTLVariable(name: paramName, type: typeName))

            // Check for comma or closing paren
            if current()?.type == .comma {
                advance()
            }
        }

        try expect(.rightParen)

        // Default visibility and isMain
        let visibility: MTLVisibility = .public
        let isMain = false

        return (name, visibility, parameters, isMain)
    }

    /// Parses template body until [/template]
    private func parseTemplateBody() throws -> MTLBlock {
        var statements: [any MTLStatement] = []

        while true {
            guard let token = current() else {
                throw error("Unexpected end of file in template body")
            }

            // Check for closing tag
            if case .leftBracket = token.type {
                if case .slash = peek()?.type {
                    // This is the closing tag
                    break
                }
            }

            // Parse statement
            let statement = try parseStatement()
            statements.append(statement)
        }

        return MTLBlock(statements: statements, inlined: false)
    }

    // MARK: - Statement Parsing

    /// Parses a statement.
    private func parseStatement() throws -> any MTLStatement {
        guard let token = current() else {
            throw error("Unexpected end of file")
        }

        switch token.type {
        case .text(let textContent):
            advance()
            return MTLTextStatement(value: textContent)

        case .leftBracket:
            advance()
            return try parseDirectiveStatement()

        default:
            throw error("Unexpected token in statement: \(token.type)")
        }
    }

    /// Parses a directive statement (inside [...])
    private func parseDirectiveStatement() throws -> any MTLStatement {
        guard let token = current() else {
            throw error("Unexpected end of directive")
        }

        switch token.type {
        case .keyword(let keyword):
            switch keyword {
            case "if":
                return try parseIfStatement()
            case "for":
                return try parseForStatement()
            case "let":
                return try parseLetStatement()
            case "file":
                return try parseFileStatement()
            case "protected":
                return try parseProtectedArea()
            default:
                throw error("Unknown statement keyword: \(keyword)")
            }

        case .slash:
            // Expression statement: [expr/]
            advance()
            let expr = try parseExpression()
            try expect(.rightBracket)
            return MTLExpressionStatement(expression: expr)

        default:
            // Expression statement without /: [expr]
            let expr = try parseExpression()

            // Check for / before ]
            if current()?.type == .slash {
                advance()
            }

            try expect(.rightBracket)
            return MTLExpressionStatement(expression: expr)
        }
    }

    // MARK: - Placeholder Parse Methods

    private func parseExpression() throws -> MTLExpression {
        // TODO: Implement in Phase 3
        throw MTLParseError.malformedExpression("Expression parsing not yet implemented")
    }

    private func parseIfStatement() throws -> MTLIfStatement {
        // TODO: Implement in Phase 4
        throw MTLParseError.invalidSyntax("If statement parsing not yet implemented")
    }

    private func parseForStatement() throws -> MTLForStatement {
        // TODO: Implement in Phase 4
        throw MTLParseError.invalidSyntax("For statement parsing not yet implemented")
    }

    private func parseLetStatement() throws -> MTLLetStatement {
        // TODO: Implement in Phase 4
        throw MTLParseError.invalidSyntax("Let statement parsing not yet implemented")
    }

    private func parseFileStatement() throws -> MTLFileStatement {
        // TODO: Implement in Phase 5
        throw MTLParseError.invalidSyntax("File statement parsing not yet implemented")
    }

    private func parseProtectedArea() throws -> MTLProtectedArea {
        // TODO: Implement in Phase 5
        throw MTLParseError.invalidSyntax("Protected area parsing not yet implemented")
    }

    private func parseQuery() throws -> MTLQuery {
        // TODO: Implement in Phase 5
        throw MTLParseError.invalidSyntax("Query parsing not yet implemented")
    }

    private func parseMacro() throws -> MTLMacro {
        // TODO: Implement in Phase 5
        throw MTLParseError.invalidSyntax("Macro parsing not yet implemented")
    }

    private func parseImport() throws -> String {
        // TODO: Implement later
        throw MTLParseError.invalidSyntax("Import parsing not yet implemented")
    }

    private func parseExtends() throws -> String {
        // TODO: Implement later
        throw MTLParseError.invalidSyntax("Extends parsing not yet implemented")
    }

    // MARK: - Helper Methods

    private func current() -> MTLToken? {
        guard position < tokens.count else { return nil }
        return tokens[position]
    }

    private func peek(_ offset: Int = 1) -> MTLToken? {
        let index = position + offset
        guard index < tokens.count else { return nil }
        return tokens[index]
    }

    private func advance() {
        position += 1
    }

    private func expect(_ expectedType: MTLTokenType) throws {
        guard let token = current() else {
            throw error("Expected \(expectedType) but got end of file")
        }

        if token.type != expectedType {
            throw error("Expected \(expectedType) but got \(token.type)", token: token)
        }

        advance()
    }

    private func expectKeyword(_ keyword: String) throws {
        guard let token = current() else {
            throw error("Expected keyword '\(keyword)' but got end of file")
        }

        guard case .keyword(let actualKeyword) = token.type, actualKeyword == keyword else {
            throw error("Expected keyword '\(keyword)' but got \(token.type)", token: token)
        }

        advance()
    }

    private func error(_ message: String, token: MTLToken? = nil) -> MTLParseError {
        let errorToken = token ?? current()
        if let t = errorToken {
            return parseError(message, line: t.line, column: t.column)
        } else {
            return MTLParseError.invalidSyntax(message)
        }
    }

    private func debugPrint(_ message: String) {
        if enableDebugging {
            print("[MTLSyntaxParser] \(message)")
        }
    }
}
