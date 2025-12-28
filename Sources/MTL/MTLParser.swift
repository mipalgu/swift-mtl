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
            advance()  // Consume the keyword
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

    // MARK: - Expression Parsing

    /// Parses an expression with operator precedence.
    private func parseExpression() throws -> MTLExpression {
        return try parseLogicalOrExpression()
    }

    /// Parses logical OR expression (lowest precedence).
    private func parseLogicalOrExpression() throws -> MTLExpression {
        var left = try parseLogicalAndExpression()

        while case .keyword("or") = current()?.type {
            advance()
            let right = try parseLogicalAndExpression()
            left = MTLExpression(
                AQLBinaryExpression(left: left.aqlExpression, op: .or, right: right.aqlExpression)
            )
        }

        return left
    }

    /// Parses logical AND expression.
    private func parseLogicalAndExpression() throws -> MTLExpression {
        var left = try parseComparisonExpression()

        while case .keyword("and") = current()?.type {
            advance()
            let right = try parseComparisonExpression()
            left = MTLExpression(
                AQLBinaryExpression(left: left.aqlExpression, op: .and, right: right.aqlExpression)
            )
        }

        return left
    }

    /// Parses comparison expression.
    private func parseComparisonExpression() throws -> MTLExpression {
        var left = try parseAdditiveExpression()

        while let op = parseComparisonOperator() {
            let right = try parseAdditiveExpression()
            left = MTLExpression(
                AQLBinaryExpression(left: left.aqlExpression, op: op, right: right.aqlExpression)
            )
        }

        return left
    }

    /// Parses comparison operator if present.
    private func parseComparisonOperator() -> AQLBinaryExpression.Operator? {
        switch current()?.type {
        case .operator("="):
            advance()
            return .equals
        case .operator("<>"):
            advance()
            return .notEquals
        case .operator("<"):
            advance()
            return .lessThan
        case .operator(">"):
            advance()
            return .greaterThan
        case .operator("<="):
            advance()
            return .lessOrEqual
        case .operator(">="):
            advance()
            return .greaterOrEqual
        default:
            return nil
        }
    }

    /// Parses additive expression (+ and -).
    private func parseAdditiveExpression() throws -> MTLExpression {
        var left = try parseMultiplicativeExpression()

        while true {
            switch current()?.type {
            case .operator("+"):
                advance()
                let right = try parseMultiplicativeExpression()
                left = MTLExpression(
                    AQLBinaryExpression(left: left.aqlExpression, op: .add, right: right.aqlExpression)
                )
            case .operator("-"):
                advance()
                let right = try parseMultiplicativeExpression()
                left = MTLExpression(
                    AQLBinaryExpression(left: left.aqlExpression, op: .subtract, right: right.aqlExpression)
                )
            default:
                return left
            }
        }
    }

    /// Parses multiplicative expression (*, /).
    private func parseMultiplicativeExpression() throws -> MTLExpression {
        var left = try parseNavigationExpression()

        while true {
            switch current()?.type {
            case .operator("*"):
                advance()
                let right = try parseNavigationExpression()
                left = MTLExpression(
                    AQLBinaryExpression(left: left.aqlExpression, op: .multiply, right: right.aqlExpression)
                )
            case .operator("/"):
                advance()
                let right = try parseNavigationExpression()
                left = MTLExpression(
                    AQLBinaryExpression(left: left.aqlExpression, op: .divide, right: right.aqlExpression)
                )
            default:
                return left
            }
        }
    }

    /// Parses navigation expression (obj.prop, obj->operation()).
    private func parseNavigationExpression() throws -> MTLExpression {
        var expr = try parsePrimaryExpression()

        while true {
            switch current()?.type {
            case .dot:
                // Property navigation: obj.prop
                advance()
                guard case .identifier(let propName) = current()?.type else {
                    throw error("Expected property name after '.'")
                }
                advance()
                expr = MTLExpression(
                    AQLNavigationExpression(source: expr.aqlExpression, property: propName)
                )

            case .operator("->"):
                // Collection operation: obj->select(...)
                advance()
                expr = try parseCollectionOperation(source: expr)

            default:
                return expr
            }
        }
    }

    /// Parses collection operation like select, reject, collect, etc.
    private func parseCollectionOperation(source: MTLExpression) throws -> MTLExpression {
        // Parse operation name (allow keywords as operation names)
        let opName: String
        switch current()?.type {
        case .identifier(let id):
            opName = id
        case .keyword(let kw):
            opName = kw
        default:
            throw error("Expected collection operation name after '->'")
        }
        advance()

        // Map operation name to AQLCollectionExpression.Operation
        let operation: AQLCollectionExpression.Operation
        switch opName {
        case "select": operation = .select
        case "reject": operation = .reject
        case "collect": operation = .collect
        case "any": operation = .any
        case "exists": operation = .exists
        case "forAll": operation = .forAll
        case "size": operation = .size
        case "isEmpty": operation = .isEmpty
        case "notEmpty": operation = .notEmpty
        case "first": operation = .first
        case "last": operation = .last
        default:
            throw error("Unknown collection operation: \(opName)")
        }

        // Operations that don't need parameters
        if operation == .size || operation == .isEmpty || operation == .notEmpty ||
           operation == .first || operation == .last {
            // These operations may have () or not
            if current()?.type == .leftParen {
                advance()
                try expect(.rightParen)
            }
            return MTLExpression(
                AQLCollectionExpression(source: source.aqlExpression, operation: operation)
            )
        }

        // Operations that need iterator and body: select, reject, collect, any, forAll, exists
        try expect(.leftParen)

        // Parse iterator variable: x | body
        guard case .identifier(let iterator) = current()?.type else {
            throw error("Expected iterator variable in collection operation")
        }
        advance()

        try expect(.pipe)

        // Parse body expression
        let body = try parseExpression()

        try expect(.rightParen)

        return MTLExpression(
            AQLCollectionExpression(
                source: source.aqlExpression,
                operation: operation,
                iterator: iterator,
                body: body.aqlExpression
            )
        )
    }

    /// Parses primary expression (literals, variables, parentheses).
    private func parsePrimaryExpression() throws -> MTLExpression {
        switch current()?.type {
        // String literal
        case .stringLiteral(let value):
            advance()
            return MTLExpression(AQLLiteralExpression(value: value))

        // Integer literal
        case .integerLiteral(let value):
            advance()
            return MTLExpression(AQLLiteralExpression(value: value))

        // Real literal
        case .realLiteral(let value):
            advance()
            return MTLExpression(AQLLiteralExpression(value: value))

        // Boolean literal
        case .booleanLiteral(let value):
            advance()
            return MTLExpression(AQLLiteralExpression(value: value))

        // Variable or keyword used as variable
        case .identifier(let name):
            advance()
            return MTLExpression(AQLVariableExpression(name: name))

        case .keyword(let keyword):
            // Some keywords can be used as variable names in expressions
            advance()
            return MTLExpression(AQLVariableExpression(name: keyword))

        // Parenthesized expression
        case .leftParen:
            advance()
            let expr = try parseExpression()
            try expect(.rightParen)
            return expr

        default:
            throw error("Expected expression, got \(current()?.type ?? .eof)")
        }
    }

    // MARK: - Control Flow Statements

    /// Parses an if statement: [if (condition)]...[elseif (cond)]...[else]...[/if]
    private func parseIfStatement() throws -> MTLIfStatement {
        // Already consumed 'if' keyword
        debugPrint("Parsing if statement")

        // Parse condition: (expr)
        try expect(.leftParen)
        let condition = try parseExpression()
        try expect(.rightParen)
        try expect(.rightBracket)

        // Parse then block
        let thenBlock = try parseBlock(until: ["elseif", "else", "/if"])

        // Parse elseif blocks
        var elseIfBlocks: [(MTLExpression, MTLBlock)] = []
        while case .keyword("elseif") = current()?.type {
            advance()  // Consume 'elseif'

            // Parse elseif condition
            try expect(.leftParen)
            let elseIfCondition = try parseExpression()
            try expect(.rightParen)
            try expect(.rightBracket)

            // Parse elseif block
            let elseIfBlock = try parseBlock(until: ["elseif", "else", "/if"])
            elseIfBlocks.append((elseIfCondition, elseIfBlock))
        }

        // Parse optional else block
        var elseBlock: MTLBlock? = nil
        if case .keyword("else") = current()?.type {
            advance()  // Consume 'else'
            try expect(.rightBracket)

            elseBlock = try parseBlock(until: ["/if"])
        }

        // Expect closing [/if]
        try expect(.slash)
        try expectKeyword("if")
        try expect(.rightBracket)

        return MTLIfStatement(
            condition: condition,
            thenBlock: thenBlock,
            elseIfBlocks: elseIfBlocks,
            elseBlock: elseBlock
        )
    }

    /// Parses a for statement: [for (item in collection) separator(sep)][/for]
    private func parseForStatement() throws -> MTLForStatement {
        // Already consumed 'for' keyword
        debugPrint("Parsing for statement")

        // Parse binding: (var : Type in collection)
        try expect(.leftParen)

        // Parse variable name
        let varName: String
        switch current()?.type {
        case .identifier(let id):
            varName = id
        case .keyword(let kw):
            varName = kw  // Allow keywords as variable names
        default:
            throw error("Expected variable name in for loop")
        }
        advance()

        // Parse optional type annotation: : Type
        var varType = "OclAny"  // Default type
        if case .colon = current()?.type {
            advance()  // Consume ':'

            switch current()?.type {
            case .identifier(let typeName):
                varType = typeName
                advance()
            case .keyword(let typeName):
                varType = typeName
                advance()
            default:
                throw error("Expected type name after ':'")
            }
        }

        // Parse 'in' keyword
        guard case .keyword("in") = current()?.type else {
            throw error("Expected 'in' keyword in for loop")
        }
        advance()

        // Parse collection expression
        let collectionExpr = try parseExpression()

        try expect(.rightParen)

        // Parse optional separator
        var separator: MTLExpression? = nil
        if case .identifier("separator") = current()?.type {
            advance()  // Consume 'separator'
            try expect(.leftParen)
            separator = try parseExpression()
            try expect(.rightParen)
        } else if case .keyword("separator") = current()?.type {
            advance()  // Consume 'separator' (as keyword)
            try expect(.leftParen)
            separator = try parseExpression()
            try expect(.rightParen)
        }

        try expect(.rightBracket)

        // Parse body
        let body = try parseBlock(until: ["/for"])

        // Expect closing [/for]
        try expect(.slash)
        try expectKeyword("for")
        try expect(.rightBracket)

        let variable = MTLVariable(name: varName, type: varType)
        let binding = MTLBinding(variable: variable, initExpression: collectionExpr)

        return MTLForStatement(binding: binding, separator: separator, body: body)
    }

    /// Parses a let statement: [let var : Type = expr]...[/let]
    private func parseLetStatement() throws -> MTLLetStatement {
        // Already consumed 'let' keyword
        debugPrint("Parsing let statement")

        var variables: [MTLBinding] = []

        // Parse variable bindings (comma-separated)
        while true {
            // Parse variable name
            let varName: String
            switch current()?.type {
            case .identifier(let id):
                varName = id
            case .keyword(let kw):
                varName = kw  // Allow keywords as variable names
            default:
                throw error("Expected variable name in let statement")
            }
            advance()

            // Parse optional type annotation: : Type
            var varType = "OclAny"  // Default type
            if case .colon = current()?.type {
                advance()  // Consume ':'

                switch current()?.type {
                case .identifier(let typeName):
                    varType = typeName
                    advance()
                case .keyword(let typeName):
                    varType = typeName
                    advance()
                default:
                    throw error("Expected type name after ':'")
                }
            }

            // Parse '=' and initialization expression
            try expect(.operator("="))
            let initExpr = try parseExpression()

            let variable = MTLVariable(name: varName, type: varType)
            let binding = MTLBinding(variable: variable, initExpression: initExpr)
            variables.append(binding)

            // Check for comma (more variables) or right bracket (end)
            if case .comma = current()?.type {
                advance()  // Consume comma, continue parsing
            } else {
                break  // No more variables
            }
        }

        try expect(.rightBracket)

        // Parse body
        let body = try parseBlock(until: ["/let"])

        // Expect closing [/let]
        try expect(.slash)
        try expectKeyword("let")
        try expect(.rightBracket)

        return MTLLetStatement(variables: variables, body: body)
    }

    /// Parses a block of statements until one of the specified terminating keywords is encountered.
    private func parseBlock(until terminators: [String]) throws -> MTLBlock {
        var statements: [any MTLStatement] = []

        while let token = current() {
            // Check for terminating keywords
            if case .leftBracket = token.type {
                // Check for closing tags like [/if] or keywords like [elseif]
                if let nextToken = peek() {
                    // Check for closing tag: [/keyword]
                    if case .slash = nextToken.type {
                        if let keywordToken = peek(2), case .keyword(let keyword) = keywordToken.type {
                            let closingTag = "/\(keyword)"
                            if terminators.contains(closingTag) {
                                // Found closing tag terminator
                                advance()  // Consume '['
                                return MTLBlock(statements: statements, inlined: false)
                            }
                        }
                    }
                    // Check for continuation keyword: [elseif] or [else]
                    else if case .keyword(let keyword) = nextToken.type {
                        if terminators.contains(keyword) {
                            // Found keyword terminator
                            advance()  // Consume '['
                            return MTLBlock(statements: statements, inlined: false)
                        }
                    }
                }
            }

            // Parse statement
            let statement = try parseStatement()
            statements.append(statement)
        }

        throw error("Unexpected end of file while parsing block (expected one of: \(terminators.joined(separator: ", ")))")
    }

    // MARK: - Advanced Feature Parsing

    /// Parses a file statement: [file (url, mode, charset)]...[/file]
    private func parseFileStatement() throws -> MTLFileStatement {
        // Already consumed 'file' keyword
        debugPrint("Parsing file statement")

        // Parse arguments: (url, mode, charset)
        try expect(.leftParen)

        // Parse URL expression
        let urlExpr = try parseExpression()

        // Parse optional mode (default: overwrite)
        let mode = MTLOpenMode.overwrite
        if case .comma = current()?.type {
            advance()  // Consume comma

            // Parse mode string
            _ = try parseExpression()
            // Mode will be evaluated at runtime, for now just default to overwrite
            // In a real implementation, we'd evaluate constant expressions here
        }

        // Parse optional charset (default: UTF-8)
        var charset: MTLExpression? = nil
        if case .comma = current()?.type {
            advance()  // Consume comma
            charset = try parseExpression()
        }

        try expect(.rightParen)
        try expect(.rightBracket)

        // Parse body
        let body = try parseBlock(until: ["/file"])

        // Expect closing [/file]
        try expect(.slash)
        try expectKeyword("file")
        try expect(.rightBracket)

        return MTLFileStatement(url: urlExpr, mode: mode, charset: charset, body: body)
    }

    /// Parses a protected area: [protected (id, startPrefix, endPrefix)]...[/protected]
    private func parseProtectedArea() throws -> MTLProtectedArea {
        // Already consumed 'protected' keyword
        debugPrint("Parsing protected area")

        // Parse arguments: (id, optional startPrefix, optional endPrefix)
        try expect(.leftParen)

        // Parse ID expression
        let idExpr = try parseExpression()

        // Parse optional start tag prefix
        var startTagPrefix: MTLExpression? = nil
        if case .comma = current()?.type {
            advance()  // Consume comma
            startTagPrefix = try parseExpression()
        }

        // Parse optional end tag prefix
        var endTagPrefix: MTLExpression? = nil
        if case .comma = current()?.type {
            advance()  // Consume comma
            endTagPrefix = try parseExpression()
        }

        try expect(.rightParen)
        try expect(.rightBracket)

        // Parse body
        let body = try parseBlock(until: ["/protected"])

        // Expect closing [/protected]
        try expect(.slash)
        try expectKeyword("protected")
        try expect(.rightBracket)

        return MTLProtectedArea(id: idExpr, startTagPrefix: startTagPrefix, endTagPrefix: endTagPrefix, body: body)
    }

    /// Parses a query: [query name(params) : ReturnType = expr/]
    private func parseQuery() throws -> MTLQuery {
        // Already consumed 'query' keyword
        debugPrint("Parsing query")

        // Parse optional visibility (default: public)
        var visibility = MTLVisibility.public
        if case .keyword(let kw) = current()?.type,
           let vis = MTLVisibility(rawValue: kw) {
            visibility = vis
            advance()
        }

        // Parse query name
        let name: String
        switch current()?.type {
        case .identifier(let id):
            name = id
        case .keyword(let kw):
            name = kw  // Allow keywords as query names
        default:
            throw error("Expected query name")
        }
        advance()

        // Parse parameters: (param1 : Type1, param2 : Type2)
        try expect(.leftParen)

        var parameters: [MTLVariable] = []
        if current()?.type != .rightParen {
            while true {
                // Parse parameter name
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

                // Parse type annotation: : Type
                try expect(.colon)

                let paramType: String
                switch current()?.type {
                case .identifier(let typeName):
                    paramType = typeName
                    advance()
                case .keyword(let typeName):
                    paramType = typeName
                    advance()
                default:
                    throw error("Expected type name")
                }

                parameters.append(MTLVariable(name: paramName, type: paramType))

                // Check for comma (more parameters) or right paren (end)
                if case .comma = current()?.type {
                    advance()
                } else {
                    break
                }
            }
        }

        try expect(.rightParen)

        // Parse return type: : ReturnType
        try expect(.colon)

        let returnType: String
        switch current()?.type {
        case .identifier(let typeName):
            returnType = typeName
            advance()
        case .keyword(let typeName):
            returnType = typeName
            advance()
        default:
            throw error("Expected return type")
        }

        // Parse body: = expr
        try expect(.operator("="))
        let bodyExpr = try parseExpression()

        // Expect closing /]
        if case .slash = current()?.type {
            advance()
        }
        try expect(.rightBracket)

        return MTLQuery(
            name: name,
            visibility: visibility,
            parameters: parameters,
            returnType: returnType,
            body: bodyExpr,
            documentation: nil
        )
    }

    /// Parses a macro: [macro name(params, bodyParam : Body)]...[/macro]
    private func parseMacro() throws -> MTLMacro {
        // Already consumed 'macro' keyword
        debugPrint("Parsing macro")

        // Parse macro name (skip visibility - macros don't have visibility)
        let name: String
        switch current()?.type {
        case .identifier(let id):
            name = id
        case .keyword(let kw):
            name = kw  // Allow keywords as macro names
        default:
            throw error("Expected macro name")
        }
        advance()

        // Parse parameters: (param1 : Type1, bodyParam : Body)
        try expect(.leftParen)

        var parameters: [MTLVariable] = []
        var bodyParameter: String? = nil

        if current()?.type != .rightParen {
            while true {
                // Parse parameter name
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

                // Parse type annotation: : Type
                try expect(.colon)

                let paramType: String
                switch current()?.type {
                case .identifier(let typeName):
                    paramType = typeName
                    advance()
                case .keyword(let typeName):
                    paramType = typeName
                    advance()
                default:
                    throw error("Expected type name")
                }

                // Check if this is a body parameter
                if paramType == "Body" {
                    bodyParameter = paramName
                } else {
                    parameters.append(MTLVariable(name: paramName, type: paramType))
                }

                // Check for comma (more parameters) or right paren (end)
                if case .comma = current()?.type {
                    advance()
                } else {
                    break
                }
            }
        }

        try expect(.rightParen)
        try expect(.rightBracket)

        // Parse body
        let body = try parseBlock(until: ["/macro"])

        // Expect closing [/macro]
        try expect(.slash)
        try expectKeyword("macro")
        try expect(.rightBracket)

        return MTLMacro(
            name: name,
            parameters: parameters,
            bodyParameter: bodyParameter,
            body: body,
            documentation: nil
        )
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
