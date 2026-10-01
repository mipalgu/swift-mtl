//
//  MTLStandaloneLines.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - Standalone Line Rule

/// Applies the MOFM2T whitespace rule for block tags.
///
/// A line that contains nothing but block tags (`template`, `for`, `if`,
/// `elseif`, `else`, `let`, `file`, `protected`, `emit`, `collect`, macros with a
/// body, their closing tags, and comments) and white space produces no output: neither
/// its leading and trailing white space nor its line break is part of the
/// generated text. Lines that contain any other text, or an expression tag,
/// are left alone.
///
/// The rule works on the token stream, before parsing, so that the parser sees
/// the text as it will be generated.
enum MTLStandaloneLines {

    /// A piece of the token stream: text, or a bracketed tag with its tokens.
    private enum Atom {
        /// A run of text that ends at a line break or at the end of the text token.
        case text(String, token: MTLToken)
        /// A complete directive; `isBlock` tells whether it is a block tag.
        case tag(tokens: [MTLToken], isBlock: Bool)
    }

    /// Removes the lines that consist only of block tags and white space.
    ///
    /// - Parameter tokens: The tokens produced by the lexer, ending in `.eof`.
    /// - Returns: The tokens with the text of standalone block tag lines removed.
    static func apply(to tokens: [MTLToken]) -> [MTLToken] {
        guard let end = tokens.last else { return tokens }
        let body = Array(tokens.dropLast())
        let macroNames = bodyMacroNames(in: body)
        let atoms = atomise(body, macroNames: macroNames)

        var result: [MTLToken] = []
        var line: [Atom] = []

        func flush() {
            result.append(contentsOf: surviving(line))
            line.removeAll()
        }

        for atom in atoms {
            line.append(atom)
            if case .text(let value, _) = atom, value.last.map(isLineBreak) == true {
                flush()
            }
        }
        flush()

        result = mergingAdjacentText(result)
        result.append(end)
        return result
    }

    /// Joins neighbouring text tokens so that text remains one token per run.
    private static func mergingAdjacentText(_ tokens: [MTLToken]) -> [MTLToken] {
        var merged: [MTLToken] = []
        for token in tokens {
            if case .text(let addition) = token.type,
               let last = merged.last,
               case .text(let existing) = last.type {
                merged[merged.count - 1] = MTLToken(type: .text(existing + addition), line: last.line, column: last.column)
            } else {
                merged.append(token)
            }
        }
        return merged
    }

    // MARK: - Tokens to Atoms

    /// Splits the token stream into text pieces (one per line) and tags.
    private static func atomise(_ tokens: [MTLToken], macroNames: Set<String>) -> [Atom] {
        var atoms: [Atom] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            switch token.type {
            case .text(let value):
                for piece in lines(of: value) {
                    atoms.append(.text(piece, token: token))
                }
                index += 1
            case .leftBracket:
                var group = [token]
                index += 1
                while index < tokens.count {
                    group.append(tokens[index])
                    index += 1
                    if tokens[index - 1].type == .rightBracket { break }
                }
                atoms.append(.tag(tokens: group, isBlock: isBlockTag(group, macroNames: macroNames)))
            case .commentDirective, .documentation:
                atoms.append(.tag(tokens: [token], isBlock: true))
                index += 1
            default:
                atoms.append(.tag(tokens: [token], isBlock: false))
                index += 1
            }
        }
        return atoms
    }

    /// Whether a character ends a line (`\n`, or `\r\n`, which Swift treats as one character).
    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n"
    }

    /// Splits text after each line break, keeping the line breaks.
    private static func lines(of text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if isLineBreak(character) {
                pieces.append(current)
                current = ""
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    // MARK: - Tag Classification

    /// Collects the names of macros that are closed by a `[/name]` tag.
    private static func bodyMacroNames(in tokens: [MTLToken]) -> Set<String> {
        var names: Set<String> = []
        for index in tokens.indices where index + 3 < tokens.count {
            if tokens[index].type == .leftBracket,
               tokens[index + 1].type == .slash,
               case .identifier(let name) = tokens[index + 2].type,
               tokens[index + 3].type == .rightBracket {
                names.insert(name)
            }
        }
        return names
    }

    /// Whether the directive is a block tag for the purposes of the line rule.
    private static func isBlockTag(_ group: [MTLToken], macroNames: Set<String>) -> Bool {
        guard group.count >= 3, group.last?.type == .rightBracket else { return false }
        let first = group[1].type
        let endsWithSlash = group[group.count - 2].type == .slash

        switch first {
        case .comment:
            return true
        case .slash:
            return true
        case .keyword(let word):
            if MTLSyntax.declarationKeywords.contains(word) { return true }
            if MTLSyntax.continuationKeywords.contains(word) { return true }
            if MTLSyntax.silentStatementNames.contains(word), endsWithSlash,
               group[2].type == .leftParen { return true }
            if MTLSyntax.blockKeywords.contains(word) { return !endsWithSlash }
            return false
        case .identifier(let name):
            return !endsWithSlash && macroNames.contains(name)
        default:
            return false
        }
    }

    // MARK: - Line Filtering

    /// The tokens of a line that survive the rule.
    private static func surviving(_ line: [Atom]) -> [MTLToken] {
        var hasTag = false
        var onlyBlockTags = true
        var onlyWhitespace = true

        for atom in line {
            switch atom {
            case .text(let value, _):
                if !value.allSatisfy(\.isWhitespace) { onlyWhitespace = false }
            case .tag(_, let isBlock):
                hasTag = true
                if !isBlock { onlyBlockTags = false }
            }
        }

        let standalone = hasTag && onlyBlockTags && onlyWhitespace
        var tokens: [MTLToken] = []
        var pendingText: [(String, MTLToken)] = []

        func flushText() {
            guard !pendingText.isEmpty else { return }
            let first = pendingText[0].1
            let merged = pendingText.map(\.0).joined()
            tokens.append(MTLToken(type: .text(merged), line: first.line, column: first.column))
            pendingText.removeAll()
        }

        for atom in line {
            switch atom {
            case .text(let value, let token):
                if !standalone { pendingText.append((value, token)) }
            case .tag(let group, _):
                flushText()
                tokens.append(contentsOf: group)
            }
        }
        flushText()
        return tokens
    }
}
