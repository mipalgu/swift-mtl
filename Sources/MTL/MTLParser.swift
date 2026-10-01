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
enum MTLTokenType: Equatable {
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
    case doubleColon        // ::
    case leftBrace          // {
    case rightBrace         // }

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
    case commentDirective(String)   // complete [comment .../] or [comment]...[/comment]
    case documentation(String)      // complete [** ... **/]
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
struct MTLToken: Equatable {
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
        "main", "post", "guard", "overrides", "then", "endif", "mod", "div",

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
        "oclIsKindOf", "oclIsTypeOf", "oclAsType", "oclIsUndefined",

        // Null literal
        "null"
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

        if char == "[", try lexCommentDirective(&tokens) {
            return
        }

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
        if char.isNumber || (char == "-" && peek()?.isNumber == true && !endsOperand(tokens.last)) {
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
            if peek() == ":" {
                tokens.append(MTLToken(type: .doubleColon, line: tokenLine, column: tokenColumn))
                advance()
            } else {
                tokens.append(MTLToken(type: .colon, line: tokenLine, column: tokenColumn))
            }
            advance()
        case "{":
            tokens.append(MTLToken(type: .leftBrace, line: tokenLine, column: tokenColumn))
            advance()
        case "}":
            tokens.append(MTLToken(type: .rightBrace, line: tokenLine, column: tokenColumn))
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

    /// The directories searched for imported and extended modules after the importing file's directory.
    private let searchPaths: [URL]

    // MARK: - Initialization

    /// Creates a parser.
    ///
    /// - Parameters:
    ///   - enableDebugging: Whether the parser logs its progress.
    ///   - searchPaths: The directories searched for imported and extended modules,
    ///     after the directory of the importing file (default: none).
    public init(enableDebugging: Bool = false, searchPaths: [URL] = []) {
        self.enableDebugging = enableDebugging
        self.searchPaths = searchPaths
    }

    // MARK: - Parsing

    /// Parses an MTL template file together with the modules it imports and extends.
    ///
    /// Imported and extended modules are located relative to the file first,
    /// then in the search paths given to the initialiser, and are attached to
    /// the returned module so that their templates and queries can be called.
    ///
    /// - Parameter url: URL of the MTL file to parse
    /// - Returns: Parsed MTLModule with its imports and parent module attached
    /// - Throws: MTLParseError if parsing fails, MTLResourceError if a file cannot be read,
    ///   MTLModuleResolutionError if an imported or extended module is missing or cyclic
    public func parse(_ url: URL) async throws -> MTLModule {
        let loader = MTLModuleLoader(
            resolver: MTLModuleResolver(searchPaths: searchPaths),
            enableDebugging: enableDebugging
        )
        return try await loader.load(url)
    }

    /// Parses an MTL template file without loading the modules it imports and extends.
    ///
    /// The returned module records its location but lists its imports by name only.
    ///
    /// - Parameter url: URL of the MTL file to parse
    /// - Returns: Parsed MTLModule
    /// - Throws: MTLParseError if parsing fails, MTLResourceError if the file cannot be read
    public func parseWithoutLinking(_ url: URL) async throws -> MTLModule {
        debugPrint("Parsing MTL file: \(url.path)")

        // Read file
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            throw MTLResourceError.loadError("Could not read file: \(url.path)")
        }

        let module = try await parse(contents, filename: url.lastPathComponent)
        return module.located(at: url)
    }

    /// Attaches the imports and parent module to a module parsed from source text.
    ///
    /// - Parameters:
    ///   - module: The module returned by ``parse(_:filename:)``.
    ///   - location: The file the source came from, used to resolve relative imports;
    ///     pass `nil` to use only the search paths.
    /// - Returns: The module with its imports and parent module attached
    /// - Throws: MTLModuleResolutionError if an imported or extended module is missing or cyclic
    public func link(_ module: MTLModule, relativeTo location: URL? = nil) async throws -> MTLModule {
        let loader = MTLModuleLoader(
            resolver: MTLModuleResolver(searchPaths: searchPaths),
            enableDebugging: enableDebugging
        )
        return try await loader.link(module, relativeTo: location)
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
        let tokens = MTLStandaloneLines.apply(to: try await lexer.tokenize())

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

    /// Documentation comment waiting to be attached to the next declaration.
    private var pendingDocumentation: String?

    /// How many iterator bodies or `post` expressions enclose the expression being parsed.
    ///
    /// Inside them, calls without a receiver apply to the implicit `self`.
    private var implicitReceiverDepth = 0

    // MARK: - Initialization

    init(tokens: [MTLToken], enableDebugging: Bool = false) {
        self.tokens = tokens.filter { !$0.isWhitespace }  // Skip whitespace tokens
        self.enableDebugging = enableDebugging
    }

    // MARK: - Module Parsing

    func parseModule() throws -> MTLModule {
        debugPrint("Parsing module")

        // Parse the comments before the header, then the module header
        var encoding = skipModulePreamble() ?? MTLSyntax.defaultCharset
        let header = try parseModuleHeader()

        debugPrint("Module: \(header.name), URIs: \(header.metamodelURIs)")

        // Parse module contents
        var templates: OrderedDictionary<String, MTLTemplate> = [:]
        var queries: OrderedDictionary<String, MTLQuery> = [:]
        var macros: OrderedDictionary<String, MTLMacro> = [:]
        var templateOverloads: [MTLTemplate] = []
        var queryOverloads: [MTLQuery] = []
        var imports: [String] = []
        var extendsModule: String? = header.extends

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
                    try register(template, in: &templates, overloads: &templateOverloads)

                case .keyword("query"):
                    advance()  // Consume 'query' keyword
                    let query = try parseQuery()
                    try register(query, in: &queries, overloads: &queryOverloads)

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

            case .commentDirective(let text):
                advance()
                if let declared = declaredEncoding(in: text) {
                    encoding = declared
                }

            case .documentation(let text):
                advance()
                pendingDocumentation = text

            case .text:
                // Skip top-level text (whitespace, etc.)
                advance()

            default:
                throw error("Unexpected token in module scope: \(token.type)")
            }
        }

        // Build module
        // Note: the metamodel URIs are bound to registered packages when models are loaded
        let module = MTLModule(
            name: header.name,
            metamodels: [:],  // Empty - will be populated when models are loaded
            extends: extendsModule,
            imports: imports,
            templates: templates,
            queries: queries,
            macros: macros,
            encoding: encoding,
            metamodelURIs: header.metamodelURIs,
            templateOverloads: templateOverloads,
            queryOverloads: queryOverloads
        )

        debugPrint("Module parsing complete: \(templates.count) templates, \(queries.count) queries, \(macros.count) macros")

        return module
    }

    // MARK: - Template Parsing

    /// Parses a template declaration.
    /// Note: '[template' has already been consumed
    private func parseTemplate() throws -> MTLTemplate {
        debugPrint("Parsing template")

        let documentation = pendingDocumentation
        pendingDocumentation = nil

        // Parse visibility, name, and parameters
        let signature = try parseTemplateSignature()

        // Parse the guard, post, and overrides clauses, which may come in any order
        let clauses = try parseTemplateClauses()

        // Expect ]
        try expect(.rightBracket)

        // Parse body
        let body = try parseTemplateBody()

        // Expect [/template]
        try expect(.leftBracket)
        try expect(.slash)
        try expectKeyword("template")
        try expect(.rightBracket)

        let markedMain = documentation?.contains(MTLSyntax.mainAnnotation) == true
            || body.statements.contains { ($0 as? MTLComment)?.value == MTLSyntax.mainAnnotation }

        return MTLTemplate(
            name: signature.name,
            visibility: signature.visibility,
            parameters: signature.parameters,
            guard: clauses.guardCondition,
            post: clauses.post,
            body: body,
            isMain: markedMain,
            overrides: clauses.overrides,
            documentation: documentation
        )
    }

    /// Parses template signature: [visibility] name(param1 : Type1, ...) or name()
    private func parseTemplateSignature() throws -> (name: String, visibility: MTLVisibility, parameters: [MTLVariable]) {
        // Parse optional visibility; a keyword followed by '(' is the template name instead
        var visibility: MTLVisibility = .public
        if case .keyword(let word) = current()?.type,
           let declared = MTLVisibility(rawValue: word),
           peek()?.type != .leftParen {
            visibility = declared
            advance()
        }

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

        let parameters = try parseParameterList()
        return (name, visibility, parameters)
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

        case .commentDirective(let text), .documentation(let text):
            advance()
            return MTLComment(value: text)

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
        case .comment(let text):
            // Comment: [-- text]
            advance()
            try expect(.rightBracket)
            return MTLComment(value: text)

        case .keyword(let keyword):
            // Check if this is a statement keyword
            switch keyword {
            case "if" where !isConditionalExpressionAhead():
                advance()  // Consume the keyword
                return try parseIfStatement()
            case "for":
                advance()  // Consume the keyword
                return try parseForStatement()
            case "let" where !isLetExpressionAhead():
                advance()  // Consume the keyword
                return try parseLetStatement()
            case "file":
                advance()  // Consume the keyword
                return try parseFileStatement()
            case "protected":
                advance()  // Consume the keyword
                return try parseProtectedArea()
            default:
                if let invocation = try parseMacroInvocationWithBody() {
                    return invocation
                }
                // Not a statement keyword, treat as expression
                return try parseExpressionStatementBody()
            }

        case .slash:
            // Expression statement: [/expr]
            advance()
            let expr = try parseExpression()
            try expect(.rightBracket)
            return MTLExpressionStatement(expression: expr)

        default:
            if let invocation = try parseMacroInvocationWithBody() {
                return invocation
            }
            // Expression statement: [expr/] or [expr]
            return try parseExpressionStatementBody()
        }
    }

    /// Parses an expression followed by an optional '/' and the closing bracket.
    private func parseExpressionStatementBody() throws -> MTLExpressionStatement {
        let expr = try parseExpression()

        // Check for / before ]
        if current()?.type == .slash {
            advance()
        }

        try expect(.rightBracket)
        return MTLExpressionStatement(expression: expr)
    }

    // MARK: - Expression Parsing

    /// Parses an expression with operator precedence.
    private func parseExpression() throws -> MTLExpression {
        return try parseImpliesExpression()
    }

    /// Parses logical OR expression (lowest precedence).
    private func parseLogicalOrExpression() throws -> MTLExpression {
        var left = try parseLogicalAndExpression()

        while true {
            let op: AQLBinaryExpression.Operator
            switch current()?.type {
            case .keyword("or"): op = .or
            case .keyword("xor"): op = .xor
            default: return left
            }
            advance()
            let right = try parseLogicalAndExpression()
            left = MTLExpression(
                AQLBinaryExpression(left: left.aqlExpression, op: op, right: right.aqlExpression)
            )
        }
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
        var left = try parseUnaryExpression()

        while true {
            switch current()?.type {
            case .operator("*"):
                advance()
                let right = try parseUnaryExpression()
                left = MTLExpression(
                    AQLBinaryExpression(left: left.aqlExpression, op: .multiply, right: right.aqlExpression)
                )
            case .operator("/"), .slash where peek()?.type != .rightBracket:
                // The lexer reports '/' as a slash token; a slash before ']' ends the directive instead
                advance()
                let right = try parseUnaryExpression()
                left = MTLExpression(
                    AQLBinaryExpression(left: left.aqlExpression, op: .divide, right: right.aqlExpression)
                )
            case .keyword("mod"):
                advance()
                let right = try parseUnaryExpression()
                left = MTLExpression(
                    AQLBinaryExpression(left: left.aqlExpression, op: .mod, right: right.aqlExpression)
                )
            case .keyword("div"):
                // Integer division has no binary operator in AQL, so it is a call on the dividend
                advance()
                let right = try parseUnaryExpression()
                left = MTLExpression(
                    AQLCallExpression(source: left.aqlExpression, methodName: "div", arguments: [right.aqlExpression])
                )
            default:
                return left
            }
        }
    }

    /// Parses unary expression (not, -).
    private func parseUnaryExpression() throws -> MTLExpression {
        switch current()?.type {
        case .keyword("not"):
            advance()
            let operand = try parseUnaryExpression()  // Right-associative
            return MTLExpression(
                AQLUnaryExpression(op: .not, operand: operand.aqlExpression)
            )
        case .operator("-"):
            // Check if this is unary minus or binary subtract
            // Unary minus only appears before primary expressions
            advance()
            let operand = try parseUnaryExpression()  // Right-associative
            return MTLExpression(
                AQLUnaryExpression(op: .negate, operand: operand.aqlExpression)
            )
        default:
            return try parseNavigationExpression()
        }
    }

    /// Parses navigation expression (obj.prop, obj->operation()).
    private func parseNavigationExpression() throws -> MTLExpression {
        var expr = try parsePrimaryExpression()

        while true {
            switch current()?.type {
            case .dot:
                // Property navigation or method call: obj.prop or obj.method(args)
                advance()

                // Get property/method name (allow keywords as property names)
                let propName: String
                switch current()?.type {
                case .identifier(let name):
                    propName = name
                case .keyword(let name):
                    // Allow keywords as property/method names (e.g., oclIsKindOf)
                    propName = name
                default:
                    throw error("Expected property name after '.'")
                }
                advance()

                // Check for method call: obj.method(args)
                if current()?.type == .leftParen {
                    let args = try parseCallArguments()
                    expr = makeInvocation(name: propName, receiver: expr.aqlExpression, arguments: args)
                } else {
                    expr = MTLExpression(
                        AQLNavigationExpression(source: expr.aqlExpression, property: propName)
                    )
                }

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
        case "indexOf": operation = .indexOf
        default:
            // Any other operation becomes a generic call on the collection
            return try parseGenericCollectionOperation(named: opName, source: source)
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

        // Operations that take a single argument (not an iterator pattern)
        if operation == .indexOf {
            try expect(.leftParen)
            let argExpr = try parseExpression()
            try expect(.rightParen)
            return MTLExpression(
                AQLCollectionExpression(
                    source: source.aqlExpression,
                    operation: operation,
                    body: argExpr.aqlExpression
                )
            )
        }

        // Operations that need iterator and body: select, reject, collect, any, forAll, exists
        try expect(.leftParen)

        // Parse iterator variable: x | body, x : Type | body, or an implicit iterator
        let header = try parseLambdaHeader()
        let iterator = header?.name ?? MTLSyntax.selfVariable
        let usesImplicitIterator = header == nil
        if usesImplicitIterator { implicitReceiverDepth += 1 }
        defer { if usesImplicitIterator { implicitReceiverDepth -= 1 } }

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

    /// Parses primary expression (literals, variables, calls, parentheses).
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

        // Null literal
        case .keyword("null"):
            advance()
            return MTLExpression(AQLLiteralExpression(value: nil))

        // Conditional expression: if c then a else b endif
        case .keyword("if"):
            advance()
            return try parseConditionalExpression()

        // Let expression: let x = e in body
        case .keyword("let"):
            advance()
            return try parseLetExpression()

        // Variable, qualified name, call, or collection literal
        case .identifier(let name):
            return try parseNameExpression(name)

        case .keyword(let keyword):
            // Some keywords can be used as variable or operation names in expressions
            return try parseNameExpression(keyword)

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

    /// Parses a for statement: [for (item : Type | collection) separator(sep) before(b) after(a)][/for]
    ///
    /// The binding may use `|` or `in` after the optional type, or be omitted
    /// altogether (`[for (collection)]`), in which case the iterator is `self`.
    private func parseForStatement() throws -> MTLForStatement {
        // Already consumed 'for' keyword
        debugPrint("Parsing for statement")

        try expect(.leftParen)

        let variable: MTLVariable
        let collectionExpr: MTLExpression
        if isForBindingAhead() {
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
            var varType = MTLSyntax.anyType  // Default type
            if case .colon = current()?.type {
                advance()  // Consume ':'
                varType = try parseTypeName()
            }

            // Parse the 'in' keyword or '|' that introduces the collection
            switch current()?.type {
            case .keyword("in"), .pipe:
                advance()
            default:
                throw error("Expected 'in' keyword or '|' in for loop")
            }

            variable = MTLVariable(name: varName, type: varType)
            collectionExpr = try parseExpression()
        } else {
            variable = MTLVariable(name: MTLSyntax.selfVariable, type: MTLSyntax.anyType)
            collectionExpr = try parseExpression()
        }

        try expect(.rightParen)

        // Parse optional separator, before, and after clauses in any order
        var separator: MTLExpression? = nil
        var before: MTLExpression? = nil
        var after: MTLExpression? = nil
        while let clause = forClauseName() {
            advance()  // Consume the clause name
            try expect(.leftParen)
            let value = try parseExpression()
            try expect(.rightParen)
            switch clause {
            case "separator": separator = value
            case "before": before = value
            default: after = value
            }
        }

        try expect(.rightBracket)

        // Parse body
        let body = try parseBlock(until: ["/for"])

        // Expect closing [/for]
        try expect(.slash)
        try expectKeyword("for")
        try expect(.rightBracket)

        let binding = MTLBinding(variable: variable, initExpression: collectionExpr)

        return MTLForStatement(binding: binding, separator: separator, before: before, after: after, body: body)
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
                        if let keyword = closingTagName(peek(2)) {
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
        var mode = MTLOpenMode.overwrite
        var modeExpression: MTLExpression? = nil
        if case .comma = current()?.type {
            advance()  // Consume comma
            (mode, modeExpression) = try parseFileMode()
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

        return MTLFileStatement(url: urlExpr, mode: mode, modeExpression: modeExpression, charset: charset, body: body)
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

        // Acceleo spells the prefixes as startTagPrefix(...) and endTagPrefix(...) clauses
        try parseProtectedAreaClauses(startTagPrefix: &startTagPrefix, endTagPrefix: &endTagPrefix)

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

        let documentation = pendingDocumentation
        pendingDocumentation = nil

        // Parse optional visibility (default: public)
        var visibility = MTLVisibility.public
        if case .keyword(let kw) = current()?.type,
           let vis = MTLVisibility(rawValue: kw),
           peek()?.type != .leftParen {
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
        let parameters = try parseParameterList()

        // Parse return type: : ReturnType
        try expect(.colon)
        let returnType = try parseTypeName()

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
            documentation: documentation
        )
    }

    /// Parses a macro: [macro name(params, bodyParam : Body)]...[/macro]
    private func parseMacro() throws -> MTLMacro {
        // Already consumed 'macro' keyword
        debugPrint("Parsing macro")

        let documentation = pendingDocumentation
        pendingDocumentation = nil

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
        let allParameters = try parseParameterList()
        let bodyParameter = allParameters.first { $0.type == MTLSyntax.macroBodyType }?.name
        let parameters = allParameters.filter { $0.type != MTLSyntax.macroBodyType }

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
            documentation: documentation
        )
    }

    /// Parses the rest of an import declaration: [import qualified::name/]
    ///
    /// '[import' has already been consumed.
    private func parseImport() throws -> String {
        let name = try parseQualifiedName(describing: "module name")
        try finishDeclaration()
        return name
    }

    /// Parses the rest of an extends declaration: [extends qualified::name/]
    ///
    /// '[extends' has already been consumed.
    private func parseExtends() throws -> String {
        let name = try parseQualifiedName(describing: "module name")
        try finishDeclaration()
        return name
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

// MARK: - Lexer: Comment Directives and Operand Detection

extension MTLLexer {

    /// The text that opens a documentation comment after the opening bracket.
    private static let documentationOpen = "[**"

    /// The text that closes a documentation comment.
    private static let documentationClose = "**/]"

    /// The text that opens a comment directive after the opening bracket.
    private static let commentOpen = "[comment"

    /// The text that closes a line comment directive.
    private static let lineCommentClose = "/]"

    /// The text that closes a block comment directive.
    private static let blockCommentClose = "[/comment]"

    /// Recognises and consumes a complete comment directive at the current position.
    ///
    /// Three forms are recognised: documentation comments (`[** ... **/]`),
    /// line comments (`[comment text /]`), and block comments
    /// (`[comment] ... [/comment]`). The whole construct, including its
    /// brackets, becomes a single token, so the text inside is never tokenized.
    ///
    /// - Parameter tokens: The token list that receives the comment token (and
    ///   any pending text).
    /// - Returns: `true` if a comment directive was consumed.
    /// - Throws: `MTLParseError` if the comment is not terminated.
    func lexCommentDirective(_ tokens: inout [MTLToken]) throws -> Bool {
        let remaining = input[position...]
        let tokenLine = line
        let tokenColumn = column

        if remaining.hasPrefix(Self.documentationOpen) {
            let body = remaining.dropFirst(Self.documentationOpen.count)
            guard let end = body.range(of: Self.documentationClose) else {
                throw parseError("Unterminated documentation comment", line: tokenLine, column: tokenColumn)
            }
            let text = String(body[..<end.lowerBound])
            flushPendingText(&tokens)
            consume(Self.documentationOpen.count + text.count + Self.documentationClose.count)
            tokens.append(MTLToken(type: .documentation(text), line: tokenLine, column: tokenColumn))
            return true
        }

        guard remaining.hasPrefix(Self.commentOpen) else { return false }
        let afterKeyword = remaining.dropFirst(Self.commentOpen.count)
        guard let next = afterKeyword.first, next.isWhitespace || next == "]" || next == "/" else {
            return false
        }

        let trimmed = afterKeyword.drop(while: { $0.isWhitespace })
        if trimmed.first == "]" {
            let body = trimmed.dropFirst()
            guard let end = body.range(of: Self.blockCommentClose) else {
                throw parseError("Unterminated comment block", line: tokenLine, column: tokenColumn)
            }
            let text = String(body[..<end.lowerBound])
            flushPendingText(&tokens)
            consume(remaining.distance(from: remaining.startIndex, to: end.upperBound))
            tokens.append(MTLToken(type: .commentDirective(text), line: tokenLine, column: tokenColumn))
            return true
        }

        guard let end = afterKeyword.range(of: Self.lineCommentClose) else {
            throw parseError("Comment must be terminated by '/]'", line: tokenLine, column: tokenColumn)
        }
        let text = String(afterKeyword[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        flushPendingText(&tokens)
        consume(remaining.distance(from: remaining.startIndex, to: end.upperBound))
        tokens.append(MTLToken(type: .commentDirective(text), line: tokenLine, column: tokenColumn))
        return true
    }

    /// Emits any text accumulated in text mode as a text token.
    ///
    /// - Parameter tokens: The token list that receives the text token.
    private func flushPendingText(_ tokens: inout [MTLToken]) {
        guard !textBuffer.isEmpty else { return }
        tokens.append(MTLToken(type: .text(textBuffer), line: line, column: column - textBuffer.count))
        textBuffer = ""
    }

    /// Advances over the given number of characters, tracking line and column.
    ///
    /// - Parameter count: The number of characters to consume.
    private func consume(_ count: Int) {
        for _ in 0..<count { advance() }
    }

    /// Whether the given token ends an operand, so that a following minus sign is binary.
    ///
    /// - Parameter token: The previously emitted token, if any.
    /// - Returns: `true` if a `-` after the token denotes subtraction.
    func endsOperand(_ token: MTLToken?) -> Bool {
        switch token?.type {
        case .identifier, .integerLiteral, .realLiteral, .stringLiteral, .booleanLiteral,
             .rightParen, .rightBrace:
            return true
        case .keyword(let word):
            return !Self.operatorKeywords.contains(word)
        default:
            return false
        }
    }

    /// Keywords after which an operand (rather than an operator) is expected.
    private static let operatorKeywords: Set<String> = [
        "and", "or", "not", "xor", "implies", "in", "mod", "div", "then", "else", "if", "let", "elseif"
    ]
}

// MARK: - Syntax Parser: Module Structure

extension MTLSyntaxParser {

    /// Skips the text and comments before the module header.
    ///
    /// - Returns: The encoding declared by an `[comment encoding = X /]` comment, if any.
    fileprivate func skipModulePreamble() -> String? {
        var encoding: String?
        while let token = current() {
            switch token.type {
            case .text, .documentation:
                advance()
            case .commentDirective(let text):
                advance()
                if let declared = declaredEncoding(in: text) {
                    encoding = declared
                }
            case .leftBracket where peek()?.type != nil && isLineComment(at: position):
                advance()
                advance()
                advance()
            default:
                return encoding
            }
        }
        return encoding
    }

    /// Whether the tokens at the given index form a `[-- text]` comment.
    private func isLineComment(at index: Int) -> Bool {
        guard index + 2 < tokens.count else { return false }
        if case .comment = tokens[index + 1].type, tokens[index + 2].type == .rightBracket {
            return true
        }
        return false
    }

    /// Extracts the encoding from the text of an `encoding = X` comment.
    ///
    /// - Parameter text: The comment text.
    /// - Returns: The declared encoding, or `nil` if the comment declares none.
    fileprivate func declaredEncoding(in text: String) -> String? {
        let parts = text.split(separator: "=", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard parts.count == 2, parts[0] == MTLSyntax.encodingDeclaration, !parts[1].isEmpty else {
            return nil
        }
        return parts[1]
    }

    /// Parses the module header: `[module name('uri', ...) extends other::module/]`.
    ///
    /// - Returns: The module name, the metamodel URIs, and the name of the extended module, if any.
    /// - Throws: `MTLParseError` if the header is malformed.
    fileprivate func parseModuleHeader() throws -> (name: String, metamodelURIs: [String], extends: String?) {
        try expect(.leftBracket)
        try expectKeyword("module")

        let name = try parseQualifiedName(describing: "module name")

        try expect(.leftParen)
        var uris: [String] = []
        while case .stringLiteral(let uri) = current()?.type {
            uris.append(uri)
            advance()
            guard case .comma = current()?.type else { break }
            advance()
        }
        guard !uris.isEmpty else {
            throw error("Expected module URI string literal")
        }
        try expect(.rightParen)

        var parent: String?
        if case .keyword("extends") = current()?.type {
            advance()
            parent = try parseQualifiedName(describing: "module name")
        }

        try finishDeclaration()
        return (name, uris, parent)
    }

    /// Consumes the optional `/` and the closing bracket of a one-line declaration.
    fileprivate func finishDeclaration() throws {
        if case .slash = current()?.type {
            advance()
        }
        try expect(.rightBracket)
    }

    /// Parses a name made of segments separated by `::`.
    ///
    /// - Parameter description: What the name denotes, for error messages.
    /// - Returns: The segments joined by `::`.
    fileprivate func parseQualifiedName(describing description: String) throws -> String {
        var segments: [String] = [try parseNameSegment(describing: description)]
        while case .doubleColon = current()?.type {
            advance()
            segments.append(try parseNameSegment(describing: description))
        }
        return segments.joined(separator: MTLSyntax.qualifiedNameSeparator)
    }

    /// Parses one identifier, accepting keywords as names.
    private func parseNameSegment(describing description: String) throws -> String {
        switch current()?.type {
        case .identifier(let id), .keyword(let id):
            advance()
            return id
        default:
            throw error("Expected \(description)")
        }
    }

    /// Parses a type name such as `String`, `ecore::EClass`, or `Sequence(EClass)`.
    ///
    /// - Returns: The type as written, with qualification and element types.
    fileprivate func parseTypeName() throws -> String {
        var name = try parseQualifiedName(describing: "type name")
        if case .leftParen = current()?.type {
            advance()
            var arguments: [String] = [try parseTypeName()]
            while case .comma = current()?.type {
                advance()
                arguments.append(try parseTypeName())
            }
            try expect(.rightParen)
            name += "(" + arguments.joined(separator: ", ") + ")"
        }
        return name
    }

    /// Parses a parameter list: `(name : Type, other : Type)`.
    ///
    /// - Returns: The declared parameters in order.
    fileprivate func parseParameterList() throws -> [MTLVariable] {
        try expect(.leftParen)
        var parameters: [MTLVariable] = []

        if current()?.type != .rightParen {
            while true {
                let parameterName = try parseNameSegment(describing: "parameter name")
                try expect(.colon)
                let parameterType = try parseTypeName()
                parameters.append(MTLVariable(name: parameterName, type: parameterType))

                guard case .comma = current()?.type else { break }
                advance()
            }
        }

        try expect(.rightParen)
        return parameters
    }

    /// Parses the clauses after a template's parameters, in any order.
    ///
    /// The clauses are the guard (`? (condition)` or `guard (condition)`),
    /// `post (expression)`, and `overrides name`.
    fileprivate func parseTemplateClauses() throws -> (guardCondition: MTLExpression?, post: MTLExpression?, overrides: String?) {
        var guardCondition: MTLExpression?
        var post: MTLExpression?
        var overrides: String?

        clauses: while true {
            switch current()?.type {
            case .questionMark, .keyword("guard"):
                guard guardCondition == nil else { throw error("Duplicate guard in template header") }
                advance()
                try expect(.leftParen)
                guardCondition = try parseExpression()
                try expect(.rightParen)

            case .keyword("post"):
                guard post == nil else { throw error("Duplicate post in template header") }
                advance()
                try expect(.leftParen)
                implicitReceiverDepth += 1
                defer { implicitReceiverDepth -= 1 }
                post = try parseExpression()
                try expect(.rightParen)

            case .keyword("overrides"):
                guard overrides == nil else { throw error("Duplicate overrides in template header") }
                advance()
                overrides = try parseQualifiedName(describing: "name of the overridden template")

            default:
                break clauses
            }
        }
        return (guardCondition, post, overrides)
    }

    /// Adds a template to the module, treating a different parameter signature as an overload.
    ///
    /// - Throws: `MTLParseError` if a template of the same name and parameter types exists.
    fileprivate func register(
        _ template: MTLTemplate,
        in templates: inout OrderedDictionary<String, MTLTemplate>,
        overloads: inout [MTLTemplate]
    ) throws {
        guard let existing = templates[template.name] else {
            templates[template.name] = template
            return
        }
        let signature = template.parameters.map(\.type)
        let known = [existing] + overloads.filter { $0.name == template.name }
        if known.contains(where: { $0.parameters.map(\.type) == signature }) {
            throw error("Duplicate template: \(template.name)")
        }
        overloads.append(template)
    }

    /// Adds a query to the module, treating a different parameter signature as an overload.
    ///
    /// - Throws: `MTLParseError` if a query of the same name and parameter types exists.
    fileprivate func register(
        _ query: MTLQuery,
        in queries: inout OrderedDictionary<String, MTLQuery>,
        overloads: inout [MTLQuery]
    ) throws {
        guard let existing = queries[query.name] else {
            queries[query.name] = query
            return
        }
        let signature = query.parameters.map(\.type)
        let known = [existing] + overloads.filter { $0.name == query.name }
        if known.contains(where: { $0.parameters.map(\.type) == signature }) {
            throw error("Duplicate query: \(query.name)")
        }
        overloads.append(query)
    }
}

// MARK: - Syntax Parser: Expressions

extension MTLSyntaxParser {

    /// Parses `implies`, the loosest binding operator, which associates to the right.
    fileprivate func parseImpliesExpression() throws -> MTLExpression {
        let left = try parseLogicalOrExpression()
        guard case .keyword("implies") = current()?.type else { return left }
        advance()
        let right = try parseImpliesExpression()
        return MTLExpression(
            AQLBinaryExpression(left: left.aqlExpression, op: .implies, right: right.aqlExpression)
        )
    }

    /// Whether the `if` at the current position starts a conditional expression.
    ///
    /// A conditional expression has a `then` before the end of the directive.
    fileprivate func isConditionalExpressionAhead() -> Bool {
        isKeywordAhead("then")
    }

    /// Whether the `let` at the current position starts a let expression.
    ///
    /// A let expression has an `in` before the end of the directive.
    fileprivate func isLetExpressionAhead() -> Bool {
        isKeywordAhead("in")
    }

    /// Looks for a keyword outside parentheses before the end of the directive.
    private func isKeywordAhead(_ keyword: String) -> Bool {
        var depth = 0
        var index = position + 1
        while index < tokens.count {
            switch tokens[index].type {
            case .leftParen: depth += 1
            case .rightParen: depth -= 1
            case .keyword(keyword) where depth == 0: return true
            case .rightBracket, .eof: return false
            default: break
            }
            index += 1
        }
        return false
    }

    /// Parses the rest of `if condition then a else b endif`; `if` is already consumed.
    fileprivate func parseConditionalExpression() throws -> MTLExpression {
        let condition = try parseExpression()
        try expectKeyword("then")
        let thenExpression = try parseExpression()
        try expectKeyword("else")
        let elseExpression = try parseExpression()
        try expectKeyword("endif")
        return MTLExpression(
            AQLConditionalExpression(
                condition: condition.aqlExpression,
                thenExpression: thenExpression.aqlExpression,
                elseExpression: elseExpression.aqlExpression
            )
        )
    }

    /// Parses the rest of `let x : T = e, y = f in body`; `let` is already consumed.
    fileprivate func parseLetExpression() throws -> MTLExpression {
        var bindings: [(String, any AQLExpression)] = []
        while true {
            let name = try parseNameSegment(describing: "variable name")
            if case .colon = current()?.type {
                advance()
                _ = try parseTypeName()
            }
            try expect(.operator("="))
            bindings.append((name, try parseExpression().aqlExpression))
            guard case .comma = current()?.type else { break }
            advance()
        }
        try expectKeyword("in")
        let body = try parseExpression()
        return MTLExpression(AQLLetExpression(bindings: bindings, body: body.aqlExpression))
    }

    /// Parses a name, a qualified name, a call, or a collection literal.
    ///
    /// The current token must be the identifier or keyword `first`.
    fileprivate func parseNameExpression(_ first: String) throws -> MTLExpression {
        if MTLSyntax.collectionTypeNames.contains(first), peek()?.type == .leftBrace {
            return try parseCollectionLiteral(kind: first)
        }

        if peek()?.type == .leftParen {
            advance()  // Consume the name
            let arguments = try parseCallArguments()
            return makeBareInvocation(name: first, arguments: arguments)
        }

        advance()
        var name = first
        while case .doubleColon = current()?.type {
            advance()
            name += MTLSyntax.qualifiedNameSeparator + (try parseNameSegment(describing: "name after '::'"))
        }
        return MTLExpression(AQLVariableExpression(name: name))
    }

    /// Parses `Kind{element, element}`.
    private func parseCollectionLiteral(kind: String) throws -> MTLExpression {
        advance()  // Consume the kind
        try expect(.leftBrace)
        var elements: [any AQLExpression] = []
        if current()?.type != .rightBrace {
            while true {
                elements.append(try parseExpression().aqlExpression)
                guard case .comma = current()?.type else { break }
                advance()
            }
        }
        try expect(.rightBrace)
        return MTLExpression(MTLCollectionLiteralExpression(kind: kind, elements: elements))
    }

    /// Parses `(argument, argument)`, where an argument may be a lambda such as `x | body`.
    fileprivate func parseCallArguments() throws -> [any AQLExpression] {
        try expect(.leftParen)
        var arguments: [any AQLExpression] = []
        if current()?.type != .rightParen {
            while true {
                arguments.append(try parseCallArgument())
                guard case .comma = current()?.type else { break }
                advance()
            }
        }
        try expect(.rightParen)
        return arguments
    }

    /// Parses one call argument, which is a lambda or an expression.
    private func parseCallArgument() throws -> any AQLExpression {
        if let header = try parseLambdaHeader() {
            let body = try parseExpression()
            return MTLLambdaExpression(iterator: header.name, iteratorType: header.type, body: body.aqlExpression)
        }
        return try parseExpression().aqlExpression
    }

    /// Parses the `x |` or `x : Type |` that starts a lambda, if one is present.
    ///
    /// - Returns: The iterator name and type, or `nil` (with nothing consumed) if there is no lambda header.
    fileprivate func parseLambdaHeader() throws -> (name: String, type: String?)? {
        let saved = position
        let name: String
        switch current()?.type {
        case .identifier(let id), .keyword(let id):
            name = id
            advance()
        default:
            return nil
        }

        var type: String?
        if case .colon = current()?.type {
            advance()
            guard let parsed = try? parseTypeName() else {
                position = saved
                return nil
            }
            type = parsed
        }

        guard case .pipe = current()?.type else {
            position = saved
            return nil
        }
        advance()
        return (name, type)
    }

    /// Parses the arguments of a `->name(...)` operation that has no dedicated AQL node.
    fileprivate func parseGenericCollectionOperation(named name: String, source: MTLExpression) throws -> MTLExpression {
        var arguments: [any AQLExpression] = []
        if current()?.type == .leftParen {
            arguments = try parseCallArguments()
        }
        return MTLExpression(
            AQLCallExpression(source: source.aqlExpression, methodName: name, arguments: arguments)
        )
    }

    /// Builds the node for `receiver.name(arguments)`.
    ///
    /// OCL type operations become plain AQL calls. Every other name becomes an
    /// invocation that is resolved against the module's templates, queries, and
    /// macros at run time before falling back to the AQL library.
    fileprivate func makeInvocation(
        name: String,
        receiver: (any AQLExpression)?,
        arguments: [any AQLExpression]
    ) -> MTLExpression {
        let call = AQLCallExpression(source: receiver, methodName: name, arguments: arguments)
        if MTLSyntax.typeOperationNames.contains(name) {
            return MTLExpression(call)
        }
        return MTLExpression(
            MTLInvocationExpression(name: name, receiver: receiver, arguments: arguments, fallback: call)
        )
    }

    /// Builds the node for a call without an explicit receiver: `name(arguments)`.
    ///
    /// Inside an iterator body or `post` expression, and for OCL type
    /// operations, the receiver is the implicit `self`.
    private func makeBareInvocation(name: String, arguments: [any AQLExpression]) -> MTLExpression {
        let implicitSelf = AQLVariableExpression(name: MTLSyntax.selfVariable)
        if MTLSyntax.typeOperationNames.contains(name) {
            return makeInvocation(name: name, receiver: implicitSelf, arguments: arguments)
        }
        let appliesToSelf = implicitReceiverDepth > 0 && !MTLSyntax.standaloneFunctionNames.contains(name)
        return makeInvocation(name: name, receiver: appliesToSelf ? implicitSelf : nil, arguments: arguments)
    }
}

// MARK: - Syntax Parser: Statements

extension MTLSyntaxParser {

    /// The name of the closing tag a token denotes, if it can name one.
    fileprivate func closingTagName(_ token: MTLToken?) -> String? {
        switch token?.type {
        case .keyword(let name), .identifier(let name): return name
        default: return nil
        }
    }

    /// Parses `[name(args)]body[/name]` if the directive at the current position is one.
    ///
    /// The directive is a macro invocation with body when the call is closed
    /// by `]` rather than `/]` and a matching `[/name]` follows.
    ///
    /// - Returns: The invocation, or `nil` (with nothing consumed) if the directive is not one.
    fileprivate func parseMacroInvocationWithBody() throws -> MTLMacroInvocation? {
        guard let name = closingTagName(current()), peek()?.type == .leftParen,
              let closeIndex = indexOfMatchingParenthesis(from: position + 1),
              closeIndex + 1 < tokens.count, tokens[closeIndex + 1].type == .rightBracket,
              hasClosingTag(named: name, from: closeIndex + 2) else {
            return nil
        }

        advance()  // Consume the name
        let arguments = try parseCallArguments().map { MTLExpression($0) }
        try expect(.rightBracket)

        let body = try parseBlock(until: ["/\(name)"])

        try expect(.slash)
        guard closingTagName(current()) == name else {
            throw error("Expected closing tag '[/\(name)]'")
        }
        advance()
        try expect(.rightBracket)

        return MTLMacroInvocation(macroName: name, arguments: arguments, bodyContent: body)
    }

    /// The index of the parenthesis that closes the one at `start`.
    private func indexOfMatchingParenthesis(from start: Int) -> Int? {
        var depth = 0
        var index = start
        while index < tokens.count {
            switch tokens[index].type {
            case .leftParen: depth += 1
            case .rightParen:
                depth -= 1
                if depth == 0 { return index }
            case .eof: return nil
            default: break
            }
            index += 1
        }
        return nil
    }

    /// Whether a `[/name]` tag occurs at or after the given index.
    private func hasClosingTag(named name: String, from start: Int) -> Bool {
        var index = start
        while index + 3 < tokens.count {
            if tokens[index].type == .leftBracket, tokens[index + 1].type == .slash,
               closingTagName(tokens[index + 2]) == name, tokens[index + 3].type == .rightBracket {
                return true
            }
            index += 1
        }
        return false
    }

    /// Whether the `for` header at the current position names an iterator variable.
    fileprivate func isForBindingAhead() -> Bool {
        switch current()?.type {
        case .identifier, .keyword:
            switch peek()?.type {
            case .colon, .pipe, .keyword("in"): return true
            default: return false
            }
        default:
            return false
        }
    }

    /// The `separator`, `before`, or `after` clause at the current position, if any.
    fileprivate func forClauseName() -> String? {
        switch current()?.type {
        case .identifier(let name), .keyword(let name):
            guard ["separator", "before", "after"].contains(name), peek()?.type == .leftParen else { return nil }
            return name
        default:
            return nil
        }
    }

    /// Parses the mode argument of a `file` block.
    ///
    /// Literal modes (`false`, `true`, `'append'`, `append`, and so on) are
    /// resolved at parse time. Any other expression is kept for evaluation.
    ///
    /// - Returns: The literal mode (or `.overwrite`) and the expression to evaluate, if the mode is computed.
    fileprivate func parseFileMode() throws -> (MTLOpenMode, MTLExpression?) {
        let following = peek()?.type
        if following == .comma || following == .rightParen {
            switch current()?.type {
            case .booleanLiteral(let append):
                advance()
                return (MTLOpenMode.mode(append: append), nil)
            case .stringLiteral(let name):
                guard let mode = MTLOpenMode(rawValue: name) else {
                    throw error("Invalid file mode '\(name)': expected 'overwrite', 'append', or 'create'")
                }
                advance()
                return (mode, nil)
            case .keyword(let word):
                if let mode = MTLOpenMode(rawValue: word) {
                    advance()
                    return (mode, nil)
                }
            default:
                break
            }
        }
        return (.overwrite, try parseExpression())
    }
}

// MARK: - Syntax Parser: Protected Areas

extension MTLSyntaxParser {

    /// Parses the optional `startTagPrefix(expr)` and `endTagPrefix(expr)` clauses of a protected area.
    ///
    /// - Parameters:
    ///   - startTagPrefix: Receives the start prefix expression if the clause is present.
    ///   - endTagPrefix: Receives the end prefix expression if the clause is present.
    /// - Throws: `MTLParseError` if a clause is malformed.
    fileprivate func parseProtectedAreaClauses(
        startTagPrefix: inout MTLExpression?,
        endTagPrefix: inout MTLExpression?
    ) throws {
        while case .identifier(let clause) = current()?.type, peek()?.type == .leftParen {
            guard clause == MTLSyntax.startTagPrefixClause || clause == MTLSyntax.endTagPrefixClause else {
                return
            }
            advance()
            try expect(.leftParen)
            let value = try parseExpression()
            try expect(.rightParen)
            if clause == MTLSyntax.startTagPrefixClause {
                startTagPrefix = value
            } else {
                endTagPrefix = value
            }
        }
    }
}
