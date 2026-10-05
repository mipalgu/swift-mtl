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

// MARK: - Diagnostics

/// A lexical problem found while reading template source text with recovery.
struct MTLLexicalProblem {
    /// The kind of problem.
    let code: MTLDiagnosticCode

    /// What is wrong.
    let message: String

    /// The line on which the offending text starts, counting from 1.
    let line: Int

    /// The column at which the offending text starts, counting from 1.
    let column: Int

    /// The UTF-8 offset at which the offending text starts.
    let offset: Int

    /// The UTF-8 offset just after the offending text.
    let endOffset: Int
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
    case invalid(String)            // text that is not a valid token, as written
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
    /// The value of ``endOffset`` while the lexer has not yet seen where the token ends.
    static let pendingEnd = -1

    let type: MTLTokenType

    /// The line on which the token starts, counting from 1.
    let line: Int

    /// The column at which the token starts, counting characters from 1.
    let column: Int

    /// The UTF-8 offset at which the token starts.
    let offset: Int

    /// The UTF-8 offset just after the token.
    var endOffset: Int

    init(type: MTLTokenType, line: Int, column: Int, offset: Int = 0, endOffset: Int? = nil) {
        self.type = type
        self.line = line
        self.column = column
        self.offset = offset
        self.endOffset = endOffset ?? offset
    }

    var isWhitespace: Bool { type.isWhitespace }
}

// MARK: - Lexer

extension MTLSyntax {
    /// The words that the MTL and AQL syntax reserve and that therefore cannot name a variable.
    ///
    /// This contains every keyword of the MTL lexer, the collection type names of AQL, and the
    /// name of the implicit receiver variable. Use it to check the names of global variables
    /// before binding them, since a reserved word cannot be read back with `[name/]`.
    public static var reservedWords: Set<String> {
        MTLLexer.keywords
            .union(AQLBuiltInType.collections)
            .union([selfVariable])
    }
}

/// Lexer for MTL with dual-mode tokenization.
///
/// The lexer operates in two modes:
/// - TEXT mode: Accumulates literal text until `[` is encountered
/// - DIRECTIVE mode: Standard tokenization inside `[...]` blocks
final class MTLLexer {

    // MARK: - Lexing Mode

    enum LexingMode {
        case text       // Outside directives, accumulate text
        case directive  // Inside directives, tokenize normally
    }

    // MARK: - Keywords

    /// The words of the AQL expression syntax together with those of the MTL template syntax.
    static let keywords: Set<String> = AQLSyntax.keywords.union(AQLSyntax.booleanLiterals).union([
        // Module and imports
        "module", "import", "extends",

        // Templates and queries
        "template", "query", "macro",

        // Visibility
        "public", "private", "protected",

        // Control flow
        "elseif", "for",

        // File operations
        "file",

        // Generation facilities (see MTLGenerationKeywords)
        MTLGenerationKeywords.emit, MTLGenerationKeywords.merge, MTLGenerationKeywords.layout,

        // Special
        "main", "post", "guard", "overrides",

        // Separators
        "separator",

        // File modes
        "overwrite", "append", "create",
    ])

    // MARK: - Operators

    static let operators: Set<String> = [
        "+", "-", "*", "/", "%",
        "=", "<>", "<", ">", "<=", ">=",
        "and", "or", "not", "xor", "implies",
        "->", "."
    ]

    // MARK: - Properties

    fileprivate let input: String
    fileprivate var position: String.Index
    fileprivate var line: Int = 1
    fileprivate var column: Int = 1

    /// The UTF-8 offset of ``position``.
    fileprivate var offset: Int = 0
    private var mode: LexingMode = .text
    fileprivate var textBuffer: String = ""

    /// Where the text in ``textBuffer`` started.
    fileprivate var textStart: Mark?
    private let enableDebugging: Bool

    /// Whether lexical problems are collected instead of thrown.
    fileprivate let recovering: Bool

    /// The lexical problems found so far, when ``recovering``.
    private(set) var problems: [MTLLexicalProblem] = []

    // MARK: - Initialization

    /// Creates a lexer.
    ///
    /// - Parameters:
    ///   - input: The template source.
    ///   - enableDebugging: Whether the lexer logs its progress.
    ///   - recovering: Whether lexical problems are collected in ``problems`` and replaced by
    ///     invalid tokens instead of being thrown.
    init(_ input: String, enableDebugging: Bool = false, recovering: Bool = false) {
        self.input = input
        self.position = input.startIndex
        self.enableDebugging = enableDebugging
        self.recovering = recovering
    }

    /// A position in the input.
    fileprivate struct Mark {
        let line: Int
        let column: Int
        let offset: Int
    }

    fileprivate func mark() -> Mark { Mark(line: line, column: column, offset: offset) }

    /// Records a lexical problem.
    ///
    /// - Parameters:
    ///   - code: The kind of problem.
    ///   - message: What is wrong.
    ///   - start: Where the offending text starts.
    fileprivate func report(_ code: MTLDiagnosticCode, _ message: String, from start: Mark) {
        problems.append(
            MTLLexicalProblem(
                code: code, message: message, line: start.line, column: start.column,
                offset: start.offset, endOffset: max(offset, start.offset)))
    }

    // MARK: - Tokenization

    func tokenize() throws -> [MTLToken] {
        var tokens: [MTLToken] = []

        while position < input.endIndex {
            let before = tokens.count
            switch mode {
            case .text:
                try tokenizeText(&tokens)
            case .directive:
                try tokenizeDirective(&tokens)
            }
            for index in before..<tokens.count where tokens[index].endOffset == MTLToken.pendingEnd {
                tokens[index].endOffset = offset
            }
        }

        // Flush any remaining text
        flushPendingText(&tokens)

        tokens.append(MTLToken(type: .eof, line: line, column: column, offset: offset))

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
            flushPendingText(&tokens)

            // Switch to directive mode
            mode = .directive
            tokens.append(
                MTLToken(
                    type: .leftBracket, line: line, column: column, offset: offset,
                    endOffset: MTLToken.pendingEnd))
            advance()
        } else {
            // Accumulate text
            if textBuffer.isEmpty { textStart = mark() }
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
        let tokenOffset = offset

        // Comments
        if char == "-" && peek() == "-" {
            try tokenizeComment(&tokens)
            return
        }

        // Right bracket - switch back to text mode
        if char == "]" {
            tokens.append(MTLToken(type: .rightBracket, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
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
        let tokenOffset = offset
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

        tokens.append(MTLToken(type: .comment(comment.trimmingCharacters(in: .whitespaces)), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
    }

    private func tokenizeString(_ tokens: inout [MTLToken]) throws {
        let tokenLine = line
        let tokenColumn = column
        let tokenOffset = offset
        let startPosition = position
        let start = mark()
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
                    tokens.append(MTLToken(type: .stringLiteral(string), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
                    return
                }
            } else if char == "\\" {
                // Escape sequences
                advance()
                guard position < input.endIndex else {
                    try unterminatedString(&tokens, from: start, at: startPosition)
                    return
                }
                let escaped = input[position]
                switch escaped {
                case "n": string.append("\n")
                case "t": string.append("\t")
                case "r": string.append("\r")
                case "b": string.append("\u{08}")
                case "f": string.append("\u{0C}")
                case "\\": string.append("\\")
                case "'": string.append("'")
                case "\"": string.append("\"")
                case "u":
                    string.append(try unicodeEscape(line: tokenLine, column: tokenColumn, start: start))
                    continue
                default: string.append(escaped)
                }
                advance()
            } else {
                string.append(char)
                advance()
            }
        }

        try unterminatedString(&tokens, from: start, at: startPosition)
    }

    /// Handles a string literal that runs to the end of the input.
    ///
    /// When recovering, the string is cut short at the end of its line (or the next `]`), and
    /// the text is returned as an invalid token so that lexing can continue after it.
    ///
    /// - Parameters:
    ///   - tokens: The token list that receives the invalid token.
    ///   - start: Where the string started.
    ///   - startPosition: The index of the opening quote.
    /// - Throws: A parse error unless recovering.
    private func unterminatedString(
        _ tokens: inout [MTLToken], from start: Mark, at startPosition: String.Index
    ) throws {
        guard recovering else {
            throw parseError("Unterminated string literal", line: start.line, column: start.column)
        }
        position = startPosition
        line = start.line
        column = start.column
        offset = start.offset
        advance()
        while position < input.endIndex, !input[position].isNewline, input[position] != "]" {
            advance()
        }
        report(.unterminatedString, "Unterminated string literal", from: start)
        tokens.append(
            MTLToken(
                type: .invalid(String(input[startPosition..<position])), line: start.line,
                column: start.column, offset: start.offset, endOffset: MTLToken.pendingEnd))
    }

    /// Reads the code unit(s) of a `\uXXXX` escape, with the cursor on the `u`.
    ///
    /// A high surrogate followed by an escaped low surrogate combines into one character; an
    /// unpaired surrogate becomes the replacement character. On return the cursor is after the
    /// last hexadecimal digit consumed.
    ///
    /// - Parameters:
    ///   - line: The line on which the enclosing string starts.
    ///   - column: The column at which the enclosing string starts.
    /// - Returns: The character the escape denotes.
    /// - Throws: A parse error when fewer than four hexadecimal digits follow.
    private func unicodeEscape(line: Int, column: Int, start: Mark) throws -> Character {
        struct MalformedEscape: Error {}
        func codeUnit() throws -> UInt32 {
            advance()  // the 'u'
            var value: UInt32 = 0
            for _ in 0..<4 {
                guard position < input.endIndex, let digit = input[position].hexDigitValue else {
                    throw MalformedEscape()
                }
                value = value * 16 + UInt32(digit)
                advance()
            }
            return value
        }
        do {
            return try decodeEscape(codeUnit)
        } catch is MalformedEscape {
            guard recovering else {
                throw parseError("Malformed unicode escape in string literal", line: line, column: column)
            }
            report(.malformedEscape, "Malformed unicode escape in string literal", from: start)
            return "\u{FFFD}"
        }
    }

    /// Decodes the escape that starts at the cursor, combining a surrogate pair.
    ///
    /// - Parameter codeUnit: Reads one `\uXXXX` code unit.
    /// - Returns: The character the escape denotes.
    /// - Throws: Whatever `codeUnit` throws.
    private func decodeEscape(_ codeUnit: () throws -> UInt32) throws -> Character {
        let first = try codeUnit()
        if (0xD800...0xDBFF).contains(first), position < input.endIndex, input[position] == "\\" {
            let resume = (position, self.line, self.column, self.offset)
            advance()
            if position < input.endIndex, input[position] == "u" {
                let second = try codeUnit()
                if (0xDC00...0xDFFF).contains(second),
                    let scalar = Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00))
                {
                    return Character(scalar)
                }
            }
            (position, self.line, self.column, self.offset) = resume
            return "\u{FFFD}"
        }
        return Unicode.Scalar(first).map(Character.init) ?? "\u{FFFD}"
    }

    private func tokenizeNumber(_ tokens: inout [MTLToken]) throws {
        let tokenLine = line
        let tokenColumn = column
        let tokenOffset = offset
        let mark = mark()
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
                try invalidNumber(&tokens, "Invalid real number: \(number)", text: number, from: mark)
                return
            }
            tokens.append(MTLToken(type: .realLiteral(value), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
        } else {
            guard let value = Int(number) else {
                try invalidNumber(&tokens, "Invalid integer: \(number)", text: number, from: mark)
                return
            }
            tokens.append(MTLToken(type: .integerLiteral(value), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
        }
    }

    /// Handles a number that cannot be represented.
    ///
    /// - Parameters:
    ///   - tokens: The token list that receives the invalid token when recovering.
    ///   - message: What is wrong.
    ///   - text: The number as written.
    ///   - start: Where the number started.
    /// - Throws: A parse error unless recovering.
    private func invalidNumber(
        _ tokens: inout [MTLToken], _ message: String, text: String, from start: Mark
    ) throws {
        guard recovering else { throw parseError(message, line: start.line, column: start.column) }
        report(.invalidNumber, message, from: start)
        tokens.append(
            MTLToken(
                type: .invalid(text), line: start.line, column: start.column, offset: start.offset,
                endOffset: MTLToken.pendingEnd))
    }

    private func tokenizeIdentifierOrKeyword(_ tokens: inout [MTLToken]) throws {
        let tokenLine = line
        let tokenColumn = column
        let tokenOffset = offset
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
            tokens.append(MTLToken(type: .booleanLiteral(true), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
        } else if identifier == "false" {
            tokens.append(MTLToken(type: .booleanLiteral(false), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
        } else if Self.keywords.contains(identifier) {
            tokens.append(MTLToken(type: .keyword(identifier), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
        } else {
            tokens.append(MTLToken(type: .identifier(identifier), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
        }
    }

    private func tokenizeOperatorOrPunctuation(_ tokens: inout [MTLToken]) throws {
        let tokenLine = line
        let tokenColumn = column
        let tokenOffset = offset
        let char = input[position]

        // Multi-character operators
        if char == "-" && peek() == ">" {
            tokens.append(MTLToken(type: .operator("->"), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
            advance()
            return
        }

        if char == "<" && peek() == ">" {
            tokens.append(MTLToken(type: .operator("<>"), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
            advance()
            return
        }

        if char == "<" && peek() == "=" {
            tokens.append(MTLToken(type: .operator("<="), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
            advance()
            return
        }

        if char == ">" && peek() == "=" {
            tokens.append(MTLToken(type: .operator(">="), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
            advance()
            return
        }

        // Single-character tokens
        switch char {
        case "/":
            tokens.append(MTLToken(type: .slash, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        case "(":
            tokens.append(MTLToken(type: .leftParen, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        case ")":
            tokens.append(MTLToken(type: .rightParen, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        case ",":
            tokens.append(MTLToken(type: .comma, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        case ":":
            if peek() == ":" {
                tokens.append(MTLToken(type: .doubleColon, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
                advance()
            } else {
                tokens.append(MTLToken(type: .colon, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            }
            advance()
        case "{":
            tokens.append(MTLToken(type: .leftBrace, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        case "}":
            tokens.append(MTLToken(type: .rightBrace, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        case ".":
            tokens.append(MTLToken(type: .dot, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        case "|":
            tokens.append(MTLToken(type: .pipe, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        case "?":
            tokens.append(MTLToken(type: .questionMark, line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        case "+", "-", "*", "=", "<", ">":
            tokens.append(MTLToken(type: .operator(String(char)), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            advance()
        default:
            guard recovering else {
                throw parseError("Unexpected character: '\(char)'", line: tokenLine, column: tokenColumn)
            }
            let start = mark()
            advance()
            report(.invalidCharacter, "Unexpected character: '\(char)'", from: start)
            tokens.append(
                MTLToken(
                    type: .invalid(String(char)), line: tokenLine, column: tokenColumn,
                    offset: tokenOffset, endOffset: MTLToken.pendingEnd))
        }
    }

    // MARK: - Helper Methods

    private func advance() {
        guard position < input.endIndex else { return }

        let char = input[position]
        if char == "\n" || char == "\r\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        offset += char.utf8.count

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

// MARK: - Syntax Highlighting

extension MTLSyntax {
    /// Splits MTL template source into tokens for syntax highlighting.
    ///
    /// This never fails and does not parse. Template text, the brackets of directives, comments,
    /// keywords, identifiers, literals, operators, and punctuation each come back as tokens
    /// of the matching kind. Text that is not valid MTL comes back as ``SourceTokenKind/invalid``
    /// tokens. Blanks inside directives belong to no token.
    ///
    /// - Parameter source: The MTL template source.
    /// - Returns: The tokens in order, without an end-of-input token.
    public static func tokens(in source: String) -> [SourceToken] {
        let table = LineTable(source)
        let lexer = MTLLexer(source, recovering: true)
        let tokens = (try? lexer.tokenize()) ?? []
        return tokens.compactMap { token in
            guard let kind = token.type.highlightKind else { return nil }
            return SourceToken(
                kind: kind, range: table.range(fromUTF8Offset: token.offset, to: token.endOffset))
        }
    }
}

extension MTLTokenType {
    /// The kind of highlighting token that corresponds to this token, or `nil` for tokens
    /// that cover no text.
    var highlightKind: SourceTokenKind? {
        switch self {
        case .text: return .text
        case .leftBracket, .rightBracket: return .directive
        case .commentDirective: return .comment
        case .documentation: return .documentation
        case .whitespace, .newline, .eof: return nil
        default: return aqlKind.highlightKind
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
        let tokens = MTLStandaloneLines.apply(to: try lexer.tokenize())

        debugPrint("Tokenization complete: \(tokens.count) tokens")

        // Parse
        let parser = MTLSyntaxParser(
            tokens: tokens, lineTable: LineTable(source), enableDebugging: enableDebugging)
        return try parser.parseModule()
    }

    /// Parses MTL template source code, collecting the problems instead of stopping at the first.
    ///
    /// Parsing recovers at the boundaries of directives (skipping to the end of the directive,
    /// or to the matching closing tag of a block) and of templates, queries, and macros, so
    /// that one mistake does not hide the rest of the text. Constructs that cannot be parsed
    /// are left out of the module. Unlike ``parse(_:filename:)``, nothing is thrown.
    ///
    /// - Parameters:
    ///   - source: MTL template source code.
    ///   - filename: The name of the file, recorded as the document of each diagnostic.
    /// - Returns: The module (if its header could be read), the problems ordered by position,
    ///   and the outline of the module.
    public func parseDiagnosing(_ source: String, filename: String) async -> MTLParseResult {
        let table = LineTable(source)
        let lexer = MTLLexer(source, enableDebugging: enableDebugging, recovering: true)
        let tokens = MTLStandaloneLines.apply(to: (try? lexer.tokenize()) ?? [])
        let parser = MTLSyntaxParser(
            tokens: tokens, lineTable: table, recovering: true, enableDebugging: enableDebugging)
        let module = (try? parser.parseModuleRecovering()) ?? nil

        let lexical = lexer.problems.map { problem in
            SourceDiagnostic(
                severity: .error, code: problem.code.rawValue, message: problem.message,
                range: table.range(fromUTF8Offset: problem.offset, to: problem.endOffset),
                document: filename)
        }
        let lexicalStarts = Set(lexical.compactMap { $0.range?.start.utf8Offset })
        let syntactic = parser.diagnostics.filter {
            !lexicalStarts.contains($0.range?.start.utf8Offset ?? -1)
        }.map { diagnostic in
            var located = diagnostic
            located.document = filename
            return located
        }
        let diagnostics = (lexical + syntactic).sorted {
            ($0.range?.start.utf8Offset ?? 0) < ($1.range?.start.utf8Offset ?? 0)
        }
        return MTLParseResult(module: module, diagnostics: diagnostics, outline: parser.outlineNodes)
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
final class MTLSyntaxParser {

    // MARK: - Properties

    fileprivate let tokens: [MTLToken]

    /// The tokens as the AQL grammar reads them, index for index parallel to ``tokens``.
    fileprivate let aqlTokens: [AQLToken]
    fileprivate var position: Int = 0
    private let enableDebugging: Bool

    /// Converts offsets to positions.
    fileprivate let lineTable: LineTable

    /// Whether syntax problems are collected and skipped instead of thrown.
    fileprivate let recovering: Bool

    /// The problems found while recovering, in the order found.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// The declarations found while recovering.
    fileprivate var outline: [OutlineNode] = []

    /// The outline of the module found by ``parseModuleRecovering()``.
    var outlineNodes: [OutlineNode] { outline }

    /// The most recent problem that a parse method reported by throwing.
    fileprivate var lastFailure: MTLFailure?

    /// The range of the name of the declaration being parsed.
    fileprivate var declarationNameRange: SourceRange?

    /// The identifiers that outline nodes already use.
    fileprivate var outlineIdentifiers: Set<String> = []

    /// Documentation comment waiting to be attached to the next declaration.
    private var pendingDocumentation: String?

    /// How many iterator bodies or `post` expressions enclose the expression being parsed.
    ///
    /// Inside them, calls without a receiver apply to the implicit `self`.
    private var implicitReceiverDepth = 0

    // MARK: - Initialization

    /// Creates a parser.
    ///
    /// - Parameters:
    ///   - tokens: The tokens of the source text, ending with the end-of-file token.
    ///   - lineTable: The line table of the source text.
    ///   - recovering: Whether syntax problems are collected and skipped instead of thrown.
    ///   - enableDebugging: Whether the parser logs its progress.
    init(
        tokens: [MTLToken], lineTable: LineTable, recovering: Bool = false,
        enableDebugging: Bool = false
    ) {
        let significant = tokens.filter { !$0.isWhitespace }  // Skip whitespace tokens
        self.tokens = significant
        self.aqlTokens = significant.map { $0.aqlToken(using: lineTable) }
        self.lineTable = lineTable
        self.recovering = recovering
        self.enableDebugging = enableDebugging
    }

    // MARK: - Module Parsing

    /// Parses the module, stopping at the first syntax error.
    ///
    /// - Returns: The module.
    /// - Throws: ``MTLParseError`` for the first problem found.
    func parseModule() throws -> MTLModule {
        guard let module = try parseModuleRecovering() else {
            throw error("Expected module header")
        }
        return module
    }

    /// Parses the module, skipping what it cannot parse when ``recovering``.
    ///
    /// - Returns: The module, or `nil` when recovering and the module header is malformed.
    /// - Throws: ``MTLParseError`` for the first problem found unless recovering.
    func parseModuleRecovering() throws -> MTLModule? {
        debugPrint("Parsing module")

        // Parse the comments before the header, then the module header
        var encoding = skipModulePreamble() ?? MTLSyntax.defaultCharset
        let headerStart = position
        let header: ModuleHeader?
        if recovering {
            do {
                header = try parseModuleHeader()
            } catch let failure as MTLParseError {
                recordFailure(failure)
                skipDirective(from: headerStart)
                header = nil
            }
        } else {
            header = try parseModuleHeader()
        }

        if let header {
            debugPrint("Module: \(header.name), URIs: \(header.metamodelURIs)")
        }

        // Parse module contents
        var templates: OrderedDictionary<String, MTLTemplate> = [:]
        var queries: OrderedDictionary<String, MTLQuery> = [:]
        var macros: OrderedDictionary<String, MTLMacro> = [:]
        var templateOverloads: [MTLTemplate] = []
        var queryOverloads: [MTLQuery] = []
        var imports: [String] = []
        var extendsModule: String? = header?.extends
        var mergeConfiguration: MTLMergeConfiguration? = nil
        var layoutConfiguration: MTLLayoutConfiguration? = nil
        var members: [OutlineNode] = []

        // Parse top-level declarations
        while let token = current(), token.type != .eof {
            debugPrint("Parsing token: \(token.type)")
            let declarationStart = position
            var declarationParsed = false

            do {
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
                        let template = try parseTemplate(from: declarationStart)
                        declarationParsed = true
                        members.append(outlineNode(for: template, from: declarationStart))
                        try register(
                            template, in: &templates, overloads: &templateOverloads,
                            nameRange: declarationNameRange)

                    case .keyword("query"):
                        advance()  // Consume 'query' keyword
                        let query = try parseQuery(from: declarationStart)
                        declarationParsed = true
                        members.append(outlineNode(for: query, from: declarationStart))
                        try register(
                            query, in: &queries, overloads: &queryOverloads,
                            nameRange: declarationNameRange)

                    case .keyword("macro"):
                        advance()  // Consume 'macro' keyword
                        let macro = try parseMacro(from: declarationStart)
                        declarationParsed = true
                        members.append(outlineNode(for: macro, from: declarationStart))
                        if macros[macro.name] != nil {
                            throw error(
                                "Duplicate macro: \(macro.name)", code: .duplicateDeclaration,
                                range: declarationNameRange)
                        }
                        macros[macro.name] = macro

                    case .keyword("import"):
                        advance()  // Consume 'import' keyword
                        let nameStart = position
                        let importModule = try parseImport()
                        imports.append(importModule)
                        members.append(
                            outlineNode(
                                .importDeclaration, name: importModule, from: declarationStart,
                                nameStart: nameStart))

                    case .keyword("extends"):
                        advance()  // Consume 'extends' keyword
                        let nameStart = position
                        extendsModule = try parseExtends()
                        members.append(
                            outlineNode(
                                .extendsDeclaration, name: extendsModule ?? "", from: declarationStart,
                                nameStart: nameStart))

                    case .keyword(MTLGenerationKeywords.merge):
                        advance()  // Consume 'merge' keyword
                        if mergeConfiguration != nil { throw error("Duplicate merge declaration", code: .duplicateDeclaration) }
                        mergeConfiguration = try parseMergeDeclaration()

                    case .keyword(MTLGenerationKeywords.layout):
                        advance()  // Consume 'layout' keyword
                        if layoutConfiguration != nil { throw error("Duplicate layout declaration", code: .duplicateDeclaration) }
                        layoutConfiguration = try parseLayoutDeclaration()

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
            } catch let failure as MTLParseError where recovering {
                recordFailure(failure)
                pendingDocumentation = nil
                if !declarationParsed { skipDeclaration(from: declarationStart) }
            }
        }

        guard let header else {
            outline = members
            return nil
        }

        // Build module
        // Note: the metamodel URIs are bound to registered packages when models are loaded
        let significant = tokens.filter { $0.type != .eof }
        let moduleRange = significant.first.map { first in
            lineTable.range(fromUTF8Offset: first.offset, to: significant.last?.endOffset ?? first.endOffset)
        }
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
            queryOverloads: queryOverloads,
            mergeConfiguration: mergeConfiguration,
            layoutConfiguration: layoutConfiguration,
            origin: SourceOrigin(moduleRange)
        )

        if let moduleRange {
            outline = [
                OutlineNode(
                    id: "\(MTLOutlineKind.module.rawValue):\(header.name)",
                    kind: MTLOutlineKind.module.rawValue, name: header.name,
                    detail: header.metamodelURIs.joined(separator: ", "),
                    range: moduleRange, selectionRange: header.nameRange ?? moduleRange,
                    children: members)
            ]
        }

        debugPrint("Module parsing complete: \(templates.count) templates, \(queries.count) queries, \(macros.count) macros")

        return module
    }

    // MARK: - Template Parsing

    /// Parses a template declaration.
    /// Note: '[template' has already been consumed
    private func parseTemplate(from start: Int) throws -> MTLTemplate {
        debugPrint("Parsing template")

        let documentation = pendingDocumentation
        pendingDocumentation = nil

        // Parse visibility, name, and parameters
        let signature = try parseTemplateSignature()

        // Parse the guard, post, and overrides clauses, which may come in any order
        let clauses = try parseTemplateClauses()

        let nameRange = declarationNameRange

        // Expect ]
        try expect(.rightBracket)

        // Parse body
        let body = try parseTemplateBody()

        try expectClosingTag("template")
        declarationNameRange = nameRange

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
            documentation: documentation,
            origin: origin(from: start)
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
        declarationNameRange = current().map(tokenRange)
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
            if recovering, token.type == .eof {
                recordFailure(error("Unexpected end of file in template body"))
                break
            }

            // Check for closing tag
            if case .leftBracket = token.type {
                if case .slash = peek()?.type {
                    // This is the closing tag
                    break
                }
            }

            // Parse statement
            if let statement = try parseStatementRecovering() {
                statements.append(statement)
            }
        }

        return MTLBlock(statements: statements, inlined: true, origin: origin(of: statements))
    }

    // MARK: - Statement Parsing

    /// Parses a statement.
    private func parseStatement() throws -> any MTLStatement {
        guard let token = current() else {
            throw error("Unexpected end of file")
        }

        let start = position
        switch token.type {
        case .text(let textContent):
            advance()
            return MTLTextStatement(value: textContent, origin: origin(from: start))

        case .leftBracket:
            advance()
            return try parseDirectiveStatement(from: start)

        case .commentDirective(let text), .documentation(let text):
            advance()
            return MTLComment(value: text, origin: origin(from: start))

        default:
            throw error("Unexpected token in statement: \(token.type)")
        }
    }

    /// Parses a directive statement (inside [...])
    private func parseDirectiveStatement(from start: Int) throws -> any MTLStatement {
        guard let token = current() else {
            throw error("Unexpected end of directive")
        }

        switch token.type {
        case .comment(let text):
            // Comment: [-- text]
            advance()
            try expect(.rightBracket)
            return MTLComment(value: text, origin: origin(from: start))

        case .keyword(let keyword):
            // Check if this is a statement keyword
            switch keyword {
            case "if" where !isConditionalExpressionAhead():
                advance()  // Consume the keyword
                return try parseIfStatement(from: start)
            case "for":
                advance()  // Consume the keyword
                return try parseForStatement(from: start)
            case "let" where !isLetExpressionAhead():
                advance()  // Consume the keyword
                return try parseLetStatement(from: start)
            case "file":
                advance()  // Consume the keyword
                return try parseFileStatement(from: start)
            case "protected":
                advance()  // Consume the keyword
                return try parseProtectedArea(from: start)
            case MTLGenerationKeywords.collect:
                advance()  // Consume the keyword
                return try parseCollectStatement(from: start)
            case MTLGenerationKeywords.emit:
                advance()  // Consume the keyword
                return try parseEmitStatement(from: start)
            default:
                if let invocation = try parseMacroInvocationWithBody(from: start) {
                    return invocation
                }
                // Not a statement keyword, treat as expression
                return try parseExpressionStatementBody(from: start)
            }

        case .slash:
            // Expression statement: [/expr]
            advance()
            let expr = try parseExpression()
            try expect(.rightBracket)
            return MTLExpressionStatement(
                expression: expr, followedByLineBreak: nextTextStartsWithLineBreak(),
                origin: origin(from: start))

        default:
            if let invocation = try parseMacroInvocationWithBody(from: start) {
                return invocation
            }
            // Expression statement: [expr/] or [expr]
            return try parseExpressionStatementBody(from: start)
        }
    }

    /// Parses an expression followed by an optional '/' and the closing bracket.
    private func parseExpressionStatementBody(from start: Int) throws -> MTLExpressionStatement {
        let expr = try parseExpression()

        // Check for / before ]
        if current()?.type == .slash {
            advance()
        }

        try expect(.rightBracket)
        return MTLExpressionStatement(
            expression: expr, followedByLineBreak: nextTextStartsWithLineBreak(),
            origin: origin(from: start))
    }

    /// Whether the next token is text that begins with a line break.
    private func nextTextStartsWithLineBreak() -> Bool {
        if case .text(let text) = current()?.type, let first = text.first {
            return first.isNewline
        }
        return false
    }

    // MARK: - Expression Parsing

    /// Parses an expression with the AQL grammar.
    ///
    /// The expression ends before the first token that the AQL grammar cannot continue with.
    /// A `/` followed by `]` ends the expression instead of dividing.
    private func parseExpression() throws -> MTLExpression {
        try withAQLCursor { cursor in
            var delegate = MTLParserDelegate()
            return MTLExpression(try AQLParser.parseExpression(&cursor, delegate: &delegate))
        }
    }

    // MARK: - Control Flow Statements

    /// Parses an if statement: [if (condition)]...[elseif (cond)]...[else]...[/if]
    private func parseIfStatement(from start: Int) throws -> MTLIfStatement {
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
            elseBlock: elseBlock,
            origin: origin(from: start)
        )
    }

    /// Parses a for statement: [for (item : Type | collection) separator(sep) before(b) after(a)][/for]
    ///
    /// The binding may use `|` or `in` after the optional type, or be omitted
    /// altogether (`[for (collection)]`), in which case the iterator is `self`.
    private func parseForStatement(from start: Int) throws -> MTLForStatement {
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

        return MTLForStatement(
            binding: binding, separator: separator, before: before, after: after, body: body,
            origin: origin(from: start))
    }

    /// Parses a let statement: [let var : Type = expr]...[/let]
    private func parseLetStatement(from start: Int) throws -> MTLLetStatement {
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

        return MTLLetStatement(variables: variables, body: body, origin: origin(from: start))
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
                                return MTLBlock(statements: statements, inlined: true, origin: origin(of: statements))
                            }
                        }
                    }
                    // Check for continuation keyword: [elseif] or [else]
                    else if case .keyword(let keyword) = nextToken.type {
                        if terminators.contains(keyword) {
                            // Found keyword terminator
                            advance()  // Consume '['
                            return MTLBlock(statements: statements, inlined: true, origin: origin(of: statements))
                        }
                    }
                }
            }

            // Parse statement
            if let statement = try parseStatementRecovering() {
                statements.append(statement)
            }
        }

        throw error("Unexpected end of file while parsing block (expected one of: \(terminators.joined(separator: ", ")))")
    }

    // MARK: - Advanced Feature Parsing

    /// Parses a file statement: [file (url, mode, charset)]...[/file]
    private func parseFileStatement(from start: Int) throws -> MTLFileStatement {
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

        // Parse optional 'key=value' file options
        var options = MTLFileOptions()
        while case .comma = current()?.type {
            advance()  // Consume comma
            guard case .stringLiteral(let option) = current()?.type else {
                throw error("Expected a 'key=value' string literal as file option")
            }
            advance()
            try applyFileOption(option, to: &options)
        }

        try expect(.rightParen)
        try expect(.rightBracket)

        // Parse body
        let body = try parseBlock(until: ["/file"])

        // Expect closing [/file]
        try expect(.slash)
        try expectKeyword("file")
        try expect(.rightBracket)

        return MTLFileStatement(
            url: urlExpr, mode: mode, modeExpression: modeExpression, charset: charset,
            options: options, body: body, origin: origin(from: start))
    }

    /// Applies one `key=value` option of a `file` block.
    ///
    /// - Parameters:
    ///   - option: The option text.
    ///   - options: The options to update.
    /// - Throws: `MTLParseError` if the option is malformed or unknown.
    private func applyFileOption(_ option: String, to options: inout MTLFileOptions) throws {
        guard let separator = option.firstIndex(of: MTLFileOptionKeys.assignment) else {
            throw error("Expected key=value file option, got '\(option)'")
        }
        let key = String(option[..<separator])
        let value = String(option[option.index(after: separator)...])
        switch key {
        case MTLFileOptionKeys.merge:
            switch value {
            case MTLFileOptionKeys.enabled: options.merge = true
            case MTLFileOptionKeys.disabled: options.merge = false
            default: throw error("The '\(key)' file option needs 'true' or 'false', got '\(value)'")
            }
        case MTLFileOptionKeys.layout:
            switch value {
            case MTLFileOptionKeys.enabled: options.layout = true
            case MTLFileOptionKeys.disabled: options.layout = false
            default: throw error("The '\(key)' file option needs 'true' or 'false', got '\(value)'")
            }
        default:
            throw error("Unknown file option '\(key)'")
        }
    }

    /// Parses a protected area: [protected (id, startPrefix, endPrefix)]...[/protected]
    private func parseProtectedArea(from start: Int) throws -> MTLProtectedArea {
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

        return MTLProtectedArea(
            id: idExpr, startTagPrefix: startTagPrefix, endTagPrefix: endTagPrefix, body: body,
            origin: origin(from: start))
    }

    /// Parses a query: [query name(params) : ReturnType = expr/]
    private func parseQuery(from start: Int) throws -> MTLQuery {
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
        declarationNameRange = current().map(tokenRange)
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
            documentation: documentation,
            origin: origin(from: start)
        )
    }

    /// Parses a macro: [macro name(params, bodyParam : Body)]...[/macro]
    private func parseMacro(from start: Int) throws -> MTLMacro {
        // Already consumed 'macro' keyword
        debugPrint("Parsing macro")

        let documentation = pendingDocumentation
        pendingDocumentation = nil

        // Parse macro name (skip visibility - macros don't have visibility)
        let name: String
        declarationNameRange = current().map(tokenRange)
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

        let nameRange = declarationNameRange
        try expect(.rightBracket)

        // Parse body
        let body = try parseBlock(until: ["/macro"])

        // Expect closing [/macro]
        try expect(.slash)
        try expectKeyword("macro")
        try expect(.rightBracket)
        declarationNameRange = nameRange

        return MTLMacro(
            name: name,
            parameters: parameters,
            bodyParameter: bodyParameter,
            body: body,
            documentation: documentation,
            origin: origin(from: start)
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

    /// Builds the error for a problem at a token, remembering it for recovery.
    ///
    /// - Parameters:
    ///   - message: What is wrong.
    ///   - token: The token at which the problem is reported (default: the current token).
    ///   - code: The kind of problem (default: an unexpected token, or an unexpected end at the
    ///     end of the file).
    ///   - range: The range to report in the diagnostic (default: the range of the token).
    /// - Returns: The error to throw.
    fileprivate func error(
        _ message: String, token: MTLToken? = nil, code: MTLDiagnosticCode = .unexpectedToken,
        range: SourceRange? = nil
    ) -> MTLParseError {
        let errorToken = token ?? current()
        let atEnd = errorToken == nil || errorToken?.type == .eof
        let reported = range ?? (errorToken ?? tokens.last).map(tokenRange)
            ?? SourceRange(start: .start, end: .start)
        lastFailure = MTLFailure(
            code: atEnd && code == .unexpectedToken ? .unexpectedEnd : code, message: message,
            range: reported)
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

// MARK: - Syntax Parser: Positions and Recovery

/// A problem that a parse method reported by throwing, with where it is and what kind it is.
fileprivate struct MTLFailure {
    /// The kind of problem.
    let code: MTLDiagnosticCode

    /// What is wrong.
    let message: String

    /// Where the problem is.
    let range: SourceRange
}

/// The parts of a module header.
fileprivate struct ModuleHeader {
    /// The module name.
    let name: String

    /// The URIs of the metamodels.
    let metamodelURIs: [String]

    /// The name of the extended module, if any.
    let extends: String?

    /// Where the module name is written.
    let nameRange: SourceRange?
}

extension MTLSyntaxParser {

    /// The range of a token.
    fileprivate func tokenRange(_ token: MTLToken) -> SourceRange {
        lineTable.range(fromUTF8Offset: token.offset, to: token.endOffset)
    }

    /// The range from the token at an index to the last token read.
    ///
    /// - Parameter start: The index of the first token.
    /// - Returns: The range, or `nil` if no token has been read since the start.
    fileprivate func range(fromToken start: Int) -> SourceRange? {
        guard start >= 0, start < tokens.count, position > start, position - 1 < tokens.count else {
            return nil
        }
        return lineTable.range(fromUTF8Offset: tokens[start].offset, to: tokens[position - 1].endOffset)
    }

    /// The origin of the text from the token at an index to the last token read.
    fileprivate func origin(from start: Int) -> SourceOrigin {
        SourceOrigin(range(fromToken: start))
    }

    /// The origin that covers a list of statements.
    fileprivate func origin(of statements: [any MTLStatement]) -> SourceOrigin {
        SourceOrigin(SourceRange.union(of: statements.compactMap { $0.origin.range }))
    }

    /// The token that starts at an offset.
    fileprivate func token(atOffset offset: Int) -> MTLToken? {
        tokens.first { $0.offset == offset }
    }

    /// Remembers a problem for the diagnostics, unless the same problem is already known.
    ///
    /// - Parameter error: The error that was thrown.
    fileprivate func recordFailure(_ error: MTLParseError) {
        let failure = lastFailure ?? MTLFailure(
            code: .unexpectedToken, message: "\(error)",
            range: (current() ?? tokens.last).map(tokenRange) ?? SourceRange(start: .start, end: .start))
        let known = diagnostics.contains {
            $0.code == failure.code.rawValue
                && $0.range?.start.utf8Offset == failure.range.start.utf8Offset
        }
        if !known {
            diagnostics.append(
                SourceDiagnostic(
                    severity: .error, code: failure.code.rawValue, message: failure.message,
                    range: failure.range))
        }
    }

    // MARK: Skipping

    /// Skips the rest of the directive that started at a token.
    ///
    /// Reading resumes after the next `]`, or before the next `[` if that comes first.
    ///
    /// - Parameter start: The index of the token at which the directive started.
    fileprivate func skipDirective(from start: Int) {
        var index = max(position, start + 1)
        while index < tokens.count {
            switch tokens[index].type {
            case .rightBracket:
                position = index + 1
                return
            case .leftBracket, .eof:
                position = index
                return
            default:
                index += 1
            }
        }
        position = tokens.count
    }

    /// Skips what remains of a template, macro, or other declaration that cannot be parsed.
    ///
    /// Templates and macros are skipped up to their closing tag; other declarations up to the
    /// end of their directive.
    ///
    /// - Parameter start: The index of the `[` at which the declaration started.
    fileprivate func skipDeclaration(from start: Int) {
        defer { position = max(position, min(start + 1, tokens.count)) }
        if start + 1 < tokens.count, tokens[start].type == .leftBracket,
            case .keyword(let word) = tokens[start + 1].type,
            word == "template" || word == "macro",
            let end = closingTagEnd(named: word, from: max(position, start + 1))
        {
            position = end
            return
        }
        skipDirective(from: start)
    }

    /// Skips what remains of a statement that cannot be parsed.
    ///
    /// Statements that open a block are skipped up to their matching closing tag; other
    /// statements up to the end of their directive.
    ///
    /// - Parameter start: The index of the token at which the statement started.
    fileprivate func skipStatement(from start: Int) {
        defer { position = max(position, min(start + 1, tokens.count)) }
        if start + 1 < tokens.count, tokens[start].type == .leftBracket,
            case .keyword(let word) = tokens[start + 1].type,
            MTLSyntax.blockKeywords.contains(word), isBlockOpener(at: start, named: word),
            let end = closingTagEnd(named: word, from: max(position, start + 1))
        {
            position = end
            return
        }
        skipDirective(from: start)
    }

    /// Whether the directive at an index opens a block of the given kind.
    ///
    /// A directive closed by `/]`, and a conditional or let expression, do not open a block.
    ///
    /// - Parameters:
    ///   - index: The index of the `[` of the directive.
    ///   - word: The keyword after the bracket.
    fileprivate func isBlockOpener(at index: Int, named word: String) -> Bool {
        var depth = 0
        var cursor = index + 2
        while cursor < tokens.count {
            switch tokens[cursor].type {
            case .leftParen: depth += 1
            case .rightParen: depth -= 1
            case .keyword("then") where depth == 0 && word == "if": return false
            case .keyword("in") where depth == 0 && word == "let": return false
            case .rightBracket: return tokens[cursor - 1].type != .slash
            case .leftBracket, .eof: return false
            default: break
            }
            cursor += 1
        }
        return false
    }

    /// The index after the closing tag `[/name]` that matches the open construct.
    ///
    /// Nested openers of the same name are skipped.
    ///
    /// - Parameters:
    ///   - name: The keyword of the construct.
    ///   - from: The index from which to look.
    /// - Returns: The index after the closing tag, or `nil` if there is none.
    fileprivate func closingTagEnd(named name: String, from: Int) -> Int? {
        var depth = 0
        var index = from
        while index + 1 < tokens.count {
            if tokens[index].type == .leftBracket {
                if tokens[index + 1].type == .slash {
                    if index + 3 < tokens.count, closingTagName(tokens[index + 2]) == name,
                        tokens[index + 3].type == .rightBracket
                    {
                        if depth == 0 { return index + 4 }
                        depth -= 1
                    }
                } else if case .keyword(name) = tokens[index + 1].type,
                    isBlockOpener(at: index, named: name)
                {
                    depth += 1
                }
            }
            index += 1
        }
        return nil
    }

    /// Parses a statement, skipping it and noting the problem when recovering.
    ///
    /// - Returns: The statement, or `nil` if it was skipped.
    /// - Throws: ``MTLParseError`` unless recovering.
    fileprivate func parseStatementRecovering() throws -> (any MTLStatement)? {
        let start = position
        guard recovering else { return try parseStatement() }
        do {
            return try parseStatement()
        } catch let failure as MTLParseError {
            recordFailure(failure)
            skipStatement(from: start)
            return nil
        }
    }

    /// Consumes the closing tag of a template or macro, noting the problem when recovering.
    ///
    /// - Parameter name: The keyword of the construct.
    /// - Throws: ``MTLParseError`` unless recovering.
    fileprivate func expectClosingTag(_ name: String) throws {
        let start = position
        do {
            try expect(.leftBracket)
            try expect(.slash)
            try expectKeyword(name)
            try expect(.rightBracket)
        } catch let failure as MTLParseError where recovering {
            recordFailure(failure)
            position = closingTagEnd(named: name, from: position) ?? max(position, start)
        }
    }

    // MARK: Outline

    /// The outline node for a template.
    fileprivate func outlineNode(for template: MTLTemplate, from start: Int) -> OutlineNode {
        let main = template.isMain ? " \(MTLOutlineSyntax.mainMarker)" : ""
        let detail = "\(template.visibility.rawValue)\(main)(\(MTLOutlineSyntax.parameters(template.parameters)))"
        return outlineNode(
            .template, name: template.name, detail: detail, from: start,
            discriminator: template.parameters.map(\.type).joined(separator: ","))
    }

    /// The outline node for a query.
    fileprivate func outlineNode(for query: MTLQuery, from start: Int) -> OutlineNode {
        let detail = "\(query.visibility.rawValue)(\(MTLOutlineSyntax.parameters(query.parameters))) : \(query.returnType)"
        return outlineNode(
            .query, name: query.name, detail: detail, from: start,
            discriminator: query.parameters.map(\.type).joined(separator: ","))
    }

    /// The outline node for a macro.
    fileprivate func outlineNode(for macro: MTLMacro, from start: Int) -> OutlineNode {
        outlineNode(
            .macro, name: macro.name, detail: "(\(MTLOutlineSyntax.parameters(macro.parameters)))",
            from: start, discriminator: macro.parameters.map(\.type).joined(separator: ","))
    }

    /// The outline node for an `import` or `extends` declaration.
    ///
    /// - Parameters:
    ///   - kind: The kind of declaration.
    ///   - name: The name of the module.
    ///   - start: The index of the `[` of the declaration.
    ///   - nameStart: The index of the first token of the module name.
    fileprivate func outlineNode(
        _ kind: MTLOutlineKind, name: String, from start: Int, nameStart: Int
    ) -> OutlineNode {
        let whole = range(fromToken: start) ?? SourceRange(start: .start, end: .start)
        var last = position - 1
        while last > nameStart, tokens[last].type == .rightBracket || tokens[last].type == .slash {
            last -= 1
        }
        let selection = last >= nameStart && nameStart < tokens.count
            ? lineTable.range(fromUTF8Offset: tokens[nameStart].offset, to: tokens[last].endOffset)
            : whole
        return OutlineNode(
            id: uniqueOutlineID("\(kind.rawValue):\(name)", at: whole.start.utf8Offset),
            kind: kind.rawValue, name: name, range: whole, selectionRange: selection)
    }

    /// The outline node for a template, query, or macro.
    private func outlineNode(
        _ kind: MTLOutlineKind, name: String, detail: String, from start: Int, discriminator: String
    ) -> OutlineNode {
        let whole = range(fromToken: start) ?? SourceRange(start: .start, end: .start)
        return OutlineNode(
            id: uniqueOutlineID("\(kind.rawValue):\(name)(\(discriminator))", at: whole.start.utf8Offset),
            kind: kind.rawValue, name: name, detail: detail, range: whole,
            selectionRange: declarationNameRange ?? whole)
    }

    /// An identifier that no other outline node uses.
    private func uniqueOutlineID(_ base: String, at offset: Int) -> String {
        if outlineIdentifiers.insert(base).inserted { return base }
        let unique = "\(base)@\(offset)"
        outlineIdentifiers.insert(unique)
        return unique
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
        let tokenOffset = offset

        if remaining.hasPrefix(Self.documentationOpen) {
            let body = remaining.dropFirst(Self.documentationOpen.count)
            guard let end = body.range(of: Self.documentationClose) else {
                guard recovering else {
                    throw parseError("Unterminated documentation comment", line: tokenLine, column: tokenColumn)
                }
                flushPendingText(&tokens)
                let start = mark()
                consume(remaining.count)
                report(.unterminatedComment, "Unterminated documentation comment", from: start)
                tokens.append(
                    MTLToken(
                        type: .documentation(String(body)), line: tokenLine, column: tokenColumn,
                        offset: tokenOffset, endOffset: MTLToken.pendingEnd))
                return true
            }
            let text = String(body[..<end.lowerBound])
            flushPendingText(&tokens)
            consume(Self.documentationOpen.count + text.count + Self.documentationClose.count)
            tokens.append(MTLToken(type: .documentation(text), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
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
                guard recovering else {
                    throw parseError("Unterminated comment block", line: tokenLine, column: tokenColumn)
                }
                flushPendingText(&tokens)
                let start = mark()
                consume(remaining.count)
                report(.unterminatedComment, "Unterminated comment block", from: start)
                tokens.append(
                    MTLToken(
                        type: .commentDirective(String(body)), line: tokenLine, column: tokenColumn,
                        offset: tokenOffset, endOffset: MTLToken.pendingEnd))
                return true
            }
            let text = String(body[..<end.lowerBound])
            flushPendingText(&tokens)
            consume(remaining.distance(from: remaining.startIndex, to: end.upperBound))
            tokens.append(MTLToken(type: .commentDirective(text), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            return true
        }

        guard let end = afterKeyword.range(of: Self.lineCommentClose) else {
            guard recovering else {
                throw parseError("Comment must be terminated by '/]'", line: tokenLine, column: tokenColumn)
            }
            flushPendingText(&tokens)
            let start = mark()
            consume(remaining.count)
            report(.unterminatedComment, "Comment must be terminated by '/]'", from: start)
            tokens.append(
                MTLToken(
                    type: .commentDirective(String(afterKeyword)), line: tokenLine, column: tokenColumn,
                    offset: tokenOffset, endOffset: MTLToken.pendingEnd))
            return true
        }
        let text = String(afterKeyword[..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        flushPendingText(&tokens)
        consume(remaining.distance(from: remaining.startIndex, to: end.upperBound))
        tokens.append(MTLToken(type: .commentDirective(text), line: tokenLine, column: tokenColumn, offset: tokenOffset, endOffset: MTLToken.pendingEnd))
        return true
    }

    /// Emits any text accumulated in text mode as a text token.
    ///
    /// - Parameter tokens: The token list that receives the text token.
    fileprivate func flushPendingText(_ tokens: inout [MTLToken]) {
        guard !textBuffer.isEmpty else { return }
        let start = textStart ?? mark()
        tokens.append(
            MTLToken(
                type: .text(textBuffer), line: start.line, column: start.column, offset: start.offset,
                endOffset: offset))
        textBuffer = ""
        textStart = nil
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
            return !AQLSyntax.operandExpectingKeywords.contains(word)
        default:
            return false
        }
    }
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
    fileprivate func parseModuleHeader() throws -> ModuleHeader {
        try expect(.leftBracket)
        try expectKeyword("module")

        let nameStart = position
        let name = try parseQualifiedName(describing: "module name")
        let nameRange = range(fromToken: nameStart)

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
        return ModuleHeader(name: name, metamodelURIs: uris, extends: parent, nameRange: nameRange)
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
        try withAQLCursor { try AQLParser.parseQualifiedName(&$0, describing: description) }
    }

    /// Parses one identifier, accepting keywords as names.
    private func parseNameSegment(describing description: String) throws -> String {
        try withAQLCursor { try AQLParser.parseNameSegment(&$0, describing: description) }
    }

    /// Parses a type name such as `String`, `ecore::EClass`, or `Sequence(EClass)`.
    ///
    /// - Returns: The type as written, with qualification and element types.
    fileprivate func parseTypeName() throws -> String {
        try withAQLCursor { try AQLParser.parseTypeName(&$0) }
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
                guard guardCondition == nil else { throw error("Duplicate guard in template header", code: .duplicateDeclaration) }
                advance()
                try expect(.leftParen)
                guardCondition = try parseExpression()
                try expect(.rightParen)

            case .keyword("post"):
                guard post == nil else { throw error("Duplicate post in template header", code: .duplicateDeclaration) }
                advance()
                try expect(.leftParen)
                implicitReceiverDepth += 1
                defer { implicitReceiverDepth -= 1 }
                post = try parseExpression()
                try expect(.rightParen)

            case .keyword("overrides"):
                guard overrides == nil else { throw error("Duplicate overrides in template header", code: .duplicateDeclaration) }
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
        overloads: inout [MTLTemplate],
        nameRange: SourceRange? = nil
    ) throws {
        guard let existing = templates[template.name] else {
            templates[template.name] = template
            return
        }
        let signature = template.parameters.map(\.type)
        let known = [existing] + overloads.filter { $0.name == template.name }
        if known.contains(where: { $0.parameters.map(\.type) == signature }) {
            throw error("Duplicate template: \(template.name)", code: .duplicateDeclaration, range: nameRange)
        }
        overloads.append(template)
    }

    /// Adds a query to the module, treating a different parameter signature as an overload.
    ///
    /// - Throws: `MTLParseError` if a query of the same name and parameter types exists.
    fileprivate func register(
        _ query: MTLQuery,
        in queries: inout OrderedDictionary<String, MTLQuery>,
        overloads: inout [MTLQuery],
        nameRange: SourceRange? = nil
    ) throws {
        guard let existing = queries[query.name] else {
            queries[query.name] = query
            return
        }
        let signature = query.parameters.map(\.type)
        let known = [existing] + overloads.filter { $0.name == query.name }
        if known.contains(where: { $0.parameters.map(\.type) == signature }) {
            throw error("Duplicate query: \(query.name)", code: .duplicateDeclaration, range: nameRange)
        }
        overloads.append(query)
    }
}

// MARK: - Syntax Parser: Expressions

extension MTLSyntaxParser {

    /// Runs a read of the AQL grammar over the current tokens and moves past what it read.
    ///
    /// - Parameter body: The read, given a cursor at the current position.
    /// - Returns: What the read returned.
    /// - Throws: An MTL parse error for a syntax error of the AQL grammar.
    fileprivate func withAQLCursor<Result>(
        _ body: (inout AQLTokenCursor) throws -> Result
    ) throws -> Result {
        var cursor = AQLTokenCursor(
            tokens: aqlTokens, position: position, implicitReceiverDepth: implicitReceiverDepth,
            terminator: MTLParserDelegate.endsExpression)
        do {
            let result = try body(&cursor)
            position = cursor.position
            return result
        } catch let syntaxError as AQLSyntaxError {
            let diagnostic = syntaxError.diagnostic
            let range = diagnostic.range ?? SourceRange(start: .start, end: .start)
            let code: MTLDiagnosticCode = diagnostic.code == AQLDiagnosticCode.unexpectedEnd
                ? .unexpectedEnd : .unexpectedToken
            lastFailure = MTLFailure(code: code, message: diagnostic.message, range: range)
            let located = token(atOffset: range.start.utf8Offset)
            throw parseError(
                diagnostic.message, line: located?.line ?? range.start.line,
                column: located?.column ?? range.start.column)
        }
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

    /// Parses `(argument, argument)`, where an argument may be a lambda such as `x | body`.
    ///
    /// - Parameter operation: The name of the operation being called. Arguments of type
    ///   operations denote types.
    fileprivate func parseCallArguments(forOperation operation: String? = nil) throws -> [any AQLExpression] {
        try withAQLCursor { cursor in
            var delegate = MTLParserDelegate()
            return try AQLParser.parseCallArguments(&cursor, delegate: &delegate, forOperation: operation)
        }
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
    fileprivate func parseMacroInvocationWithBody(from start: Int) throws -> MTLMacroInvocation? {
        guard let name = closingTagName(current()), peek()?.type == .leftParen,
              let closeIndex = indexOfMatchingParenthesis(from: position + 1),
              closeIndex + 1 < tokens.count, tokens[closeIndex + 1].type == .rightBracket,
              hasClosingTag(named: name, from: closeIndex + 2) else {
            return nil
        }

        advance()  // Consume the name
        let arguments = try parseCallArguments(forOperation: name).map { MTLExpression($0) }
        try expect(.rightBracket)

        let body = try parseBlock(until: ["/\(name)"])

        try expect(.slash)
        guard closingTagName(current()) == name else {
            throw error("Expected closing tag '[/\(name)]'")
        }
        advance()
        try expect(.rightBracket)

        return MTLMacroInvocation(
            macroName: name, arguments: arguments, bodyContent: body, origin: origin(from: start))
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

// MARK: - Generation Facilities Parsing

/// Parsing of the deferred blocks and the merge declaration.
extension MTLSyntaxParser {

    /// Parses `[collect ('set', expression)/]`; the `collect` keyword is already consumed.
    fileprivate func parseCollectStatement(from start: Int) throws -> MTLCollectStatement {
        try expect(.leftParen)
        let setName = try parseExpression()
        try expect(.comma)
        let value = try parseExpression()
        try expect(.rightParen)
        if current()?.type == .slash { advance() }
        try expect(.rightBracket)
        return MTLCollectStatement(setName: setName, value: value, origin: origin(from: start))
    }

    /// Parses `[emit ('set') in(expr) separator(expr) once]...[/emit]`; the `emit` keyword is
    /// already consumed.
    fileprivate func parseEmitStatement(from start: Int) throws -> MTLEmitStatement {
        try expect(.leftParen)
        let setName = try parseExpression()
        try expect(.rightParen)

        var separator: MTLExpression? = nil
        var order: MTLExpression? = nil
        var rendersOnce = false
        clauses: while true {
            switch current()?.type {
            case .keyword(MTLGenerationKeywords.separator):
                advance()
                try expect(.leftParen)
                separator = try parseExpression()
                try expect(.rightParen)
            case .keyword("in"):
                advance()
                try expect(.leftParen)
                order = try parseExpression()
                try expect(.rightParen)
            case .identifier(MTLGenerationKeywords.once):
                advance()
                rendersOnce = true
            default:
                break clauses
            }
        }
        try expect(.rightBracket)

        let block = try parseBlock(until: ["/\(MTLGenerationKeywords.emit)"])
        try expect(.slash)
        try expectKeyword(MTLGenerationKeywords.emit)
        try expect(.rightBracket)

        return MTLEmitStatement(
            setName: setName, separator: separator, order: order, rendersOnce: rendersOnce,
            body: MTLBlock(statements: block.statements, inlined: true, origin: block.origin),
            origin: origin(from: start))
    }

    /// Parses `[merge (start, end, generatedTag, keepTag, strategy, options...)/]`;
    /// the `merge` keyword is already consumed.
    fileprivate func parseMergeDeclaration() throws -> MTLMergeConfiguration {
        try expect(.leftParen)
        var arguments: [String] = []
        while true {
            guard case .stringLiteral(let value) = current()?.type else {
                throw error("Expected a string literal in merge declaration")
            }
            arguments.append(value)
            advance()
            if current()?.type == .comma {
                advance()
            } else {
                break
            }
        }
        try expect(.rightParen)
        if current()?.type == .slash { advance() }
        try expect(.rightBracket)

        let required = 4
        guard arguments.count >= required else {
            throw error(
                "A merge declaration needs a comment start, a comment end, a generated tag and a keep tag"
            )
        }
        var strategy = MTLMergeStrategy.braces
        var optionStart = required
        if arguments.count > required, let named = MTLMergeStrategy(rawValue: arguments[required]) {
            strategy = named
            optionStart = required + 1
        } else if arguments.count > required, !arguments[required].contains(MTLMergeOptionKeys.assignment) {
            throw error("Unknown merge strategy '\(arguments[required])'")
        }

        var syntax = MTLMergeSyntax.defaults(for: strategy)
        var filePatterns: [String] = []
        for option in arguments[optionStart...] {
            guard let separator = option.firstIndex(of: MTLMergeOptionKeys.assignment) else {
                throw error("Expected key=value merge option, got '\(option)'")
            }
            let key = String(option[..<separator])
            let value = String(option[option.index(after: separator)...])
            switch key {
            case MTLMergeOptionKeys.lineComments:
                syntax.lineComments = value.split(separator: " ").map(String.init)
            case MTLMergeOptionKeys.blockComment:
                let parts = value.split(separator: " ").map(String.init)
                guard parts.count == 2 else {
                    throw error("A block comment option needs a start and an end delimiter")
                }
                syntax.blockComments = [MTLMergeSyntax.BlockComment(start: parts[0], end: parts[1])]
            case MTLMergeOptionKeys.quotes:
                syntax.quotes = Array(value)
            case MTLMergeOptionKeys.terminators:
                syntax.terminators = Array(value)
            case MTLMergeOptionKeys.opener:
                guard let opener = value.first, value.count == 1 else {
                    throw error("The opener option needs a single character")
                }
                syntax.opener = opener
            case MTLMergeOptionKeys.files:
                filePatterns = value.split(separator: MTLMergeOptionKeys.filePatternSeparator).map(String.init)
                guard !filePatterns.isEmpty else {
                    throw error("The files option needs at least one pattern")
                }
            default:
                throw error("Unknown merge option '\(key)'")
            }
        }
        return MTLMergeConfiguration(
            commentStart: arguments[0], commentEnd: arguments[1], generatedTag: arguments[2],
            keepTag: arguments[3], strategy: strategy, syntax: syntax, filePatterns: filePatterns)
    }

    /// Parses `[layout (option, ...)/]`, where every option is a `key=value` string;
    /// the `layout` keyword is already consumed.
    fileprivate func parseLayoutDeclaration() throws -> MTLLayoutConfiguration {
        try expect(.leftParen)
        var arguments: [String] = []
        while true {
            guard case .stringLiteral(let value) = current()?.type else {
                throw error("Expected a string literal in layout declaration")
            }
            arguments.append(value)
            advance()
            if current()?.type == .comma {
                advance()
            } else {
                break
            }
        }
        try expect(.rightParen)
        if current()?.type == .slash { advance() }
        try expect(.rightBracket)

        var layout = MTLLayoutConfiguration()
        for option in arguments {
            guard let separator = option.firstIndex(of: MTLMergeOptionKeys.assignment) else {
                throw error("Expected key=value layout option, got '\(option)'")
            }
            let key = String(option[..<separator])
            let value = String(option[option.index(after: separator)...])
            switch key {
            case MTLLayoutOptionKeys.indent:
                layout.sourceIndent = value
            case MTLLayoutOptionKeys.targetIndent:
                layout.targetIndent = value
            case MTLLayoutOptionKeys.opener:
                guard let placement = MTLOpenerPlacement(rawValue: value) else {
                    throw error("Unknown opener placement '\(value)'")
                }
                layout.openerPlacement = placement
            case MTLLayoutOptionKeys.openerToken:
                guard let token = value.first, value.count == 1 else {
                    throw error("The openerToken option needs a single character")
                }
                layout.syntax.opener = token
            case MTLLayoutOptionKeys.lineComments:
                layout.syntax.lineComments = value.split(separator: " ").map(String.init)
            case MTLLayoutOptionKeys.blockComment:
                let parts = value.split(separator: " ").map(String.init)
                guard parts.count == 2 else {
                    throw error("A block comment option needs a start and an end delimiter")
                }
                layout.syntax.blockComments = [MTLMergeSyntax.BlockComment(start: parts[0], end: parts[1])]
            case MTLLayoutOptionKeys.quotes:
                layout.syntax.quotes = Array(value)
            case MTLLayoutOptionKeys.terminators:
                layout.syntax.terminators = Array(value)
            case MTLLayoutOptionKeys.files:
                layout.filePatterns = value.split(separator: MTLMergeOptionKeys.filePatternSeparator)
                    .map(String.init)
                guard !layout.filePatterns.isEmpty else {
                    throw error("The files option needs at least one pattern")
                }
            default:
                throw error("Unknown layout option '\(key)'")
            }
        }
        return layout
    }
}
