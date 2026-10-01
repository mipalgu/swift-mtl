//
//  TaggedBlockScanner.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - Tagged Block

/// A member of a source file together with its leading comment.
///
/// A block is a declaration-like unit found by the ``TaggedBlockScanner``:
/// a member that ends at a terminator, or a member with a body (delimited by
/// braces or by indentation) that may itself contain further blocks.
/// Offsets refer to the characters of the scanned text, where a character is
/// an extended grapheme cluster.
public struct TaggedBlock: Sendable, Equatable {

    /// The signature with whitespace normalised.
    ///
    /// For a block with a body this is the text from the first significant
    /// character up to the opener of the body. For a member without a body
    /// it is the text up to an initialiser (`=`) or the terminator.
    public let signature: String

    /// The text of the comments that immediately precede the block.
    public let leadingComment: String

    /// The characters occupied by the block, from the start of the line of
    /// its leading comment to the end of its last character.
    public let range: Range<Int>

    /// The characters of the header: the part of the block up to and
    /// including the opener of the body, or the whole block when it has no body.
    public let headerRange: Range<Int>

    /// The characters of the body between the opener and the closer, if the block has one.
    public let bodyRange: Range<Int>?

    /// The blocks found directly inside the body.
    public let children: [TaggedBlock]
}

// MARK: - Scan Result

/// The result of scanning a text for tagged blocks.
public struct TaggedBlockScan: Sendable, Equatable {

    /// The scanned text as an array of characters.
    public let characters: [Character]

    /// The top-level blocks, in source order.
    public let blocks: [TaggedBlock]

    /// Returns the text of a range of characters.
    ///
    /// - Parameter range: The range of character offsets.
    /// - Returns: The text within the range.
    public func text(_ range: Range<Int>) -> String {
        String(characters[range])
    }
}

// MARK: - Scanner Errors

/// Errors raised while scanning a text for blocks.
public enum TaggedBlockError: Error, Equatable, LocalizedError, Sendable {

    /// A brace was not matched by its counterpart.
    case unbalancedBraces(offset: Int)

    public var errorDescription: String? {
        switch self {
        case .unbalancedBraces(let offset):
            return "Unbalanced braces near character offset \(offset)"
        }
    }
}

// MARK: - Tagged Block Scanner

/// Extracts blocks, with their leading comments, from a source text.
///
/// The scanner is language-neutral. With the `braces` strategy it matches
/// braces while skipping string and character literals as well as line and
/// block comments, using the delimiters of the ``MTLMergeSyntax``. With the
/// `indentation` strategy it groups lines by indentation. In both cases a
/// block is a member (such as a method, a field or a nested type) preceded
/// by its leading comments, and blocks nest.
///
/// ## Example
///
/// ```swift
/// let configuration = MTLMergeConfiguration(
///     commentStart: "/**", commentEnd: "*/",
///     generatedTag: "@generated", keepTag: "@generated NOT")
/// let scan = try TaggedBlockScanner(configuration: configuration).scan(source)
/// for block in scan.blocks { print(block.signature) }
/// ```
public struct TaggedBlockScanner: Sendable {

    /// The configuration that supplies the strategy and the syntax.
    public let configuration: MTLMergeConfiguration

    /// Creates a scanner.
    ///
    /// - Parameter configuration: The merge configuration to scan with.
    public init(configuration: MTLMergeConfiguration) {
        self.configuration = configuration
    }

    /// Scans a text for blocks.
    ///
    /// - Parameter text: The text to scan; line endings should be `\n`.
    /// - Returns: The scan result with the top-level blocks.
    /// - Throws: ``TaggedBlockError`` if braces are unbalanced.
    public func scan(_ text: String) throws -> TaggedBlockScan {
        let characters = Array(text)
        let range = 0..<characters.count
        let blocks: [TaggedBlock]
        switch configuration.strategy {
        case .braces:
            blocks = try BraceScanner(characters: characters, syntax: configuration.syntax)
                .members(in: range)
        case .indentation:
            blocks = IndentationScanner(characters: characters, syntax: configuration.syntax)
                .members(in: range)
        }
        return TaggedBlockScan(characters: characters, blocks: blocks)
    }
}

// MARK: - Shared Lexical Helpers

/// Lexical helpers shared by the scanning strategies.
private struct LexicalReader {

    let characters: [Character]
    let syntax: MTLMergeSyntax

    func hasPrefix(_ marker: String, at index: Int, limit: Int) -> Bool {
        let marker = Array(marker)
        guard !marker.isEmpty, index + marker.count <= limit else { return false }
        for offset in 0..<marker.count where characters[index + offset] != marker[offset] {
            return false
        }
        return true
    }

    /// The index after the comment starting at `index`, or nil if none starts there.
    func commentEnd(at index: Int, limit: Int) -> Int? {
        for marker in syntax.lineComments where hasPrefix(marker, at: index, limit: limit) {
            var end = index
            while end < limit && characters[end] != "\n" { end += 1 }
            return end
        }
        for pair in syntax.blockComments where hasPrefix(pair.start, at: index, limit: limit) {
            var end = index + pair.start.count
            while end < limit {
                if hasPrefix(pair.end, at: end, limit: limit) { return end + pair.end.count }
                end += 1
            }
            return limit
        }
        return nil
    }

    /// The index after the literal starting at `index`, or nil if none starts there.
    func literalEnd(at index: Int, limit: Int) -> Int? {
        let quote = characters[index]
        guard syntax.quotes.contains(quote) else { return nil }
        let triple = String(repeating: quote, count: 3)
        if hasPrefix(triple, at: index, limit: limit) {
            var end = index + 3
            while end < limit {
                if characters[end] == "\\" { end += 2; continue }
                if hasPrefix(triple, at: end, limit: limit) { return end + 3 }
                end += 1
            }
            return limit
        }
        var end = index + 1
        while end < limit {
            let character = characters[end]
            if character == "\\" { end += 2; continue }
            if character == quote { return end + 1 }
            if character == "\n" { return nil }
            end += 1
        }
        return nil
    }

    /// The start of the line containing `index`.
    func lineStart(of index: Int) -> Int {
        var start = index
        while start > 0 && characters[start - 1] != "\n" { start -= 1 }
        return start
    }

    /// Whether only blanks lie between the start of the line and `index`.
    func startsLine(at index: Int) -> Bool {
        var cursor = index
        while cursor > 0 && characters[cursor - 1] != "\n" {
            cursor -= 1
            if !characters[cursor].isWhitespace { return false }
        }
        return true
    }

    /// Collapses runs of whitespace into single spaces.
    func normalised(_ range: Range<Int>) -> String {
        var result = ""
        var pendingSpace = false
        for character in characters[range] {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
            } else {
                if pendingSpace { result.append(" ") }
                pendingSpace = false
                result.append(character)
            }
        }
        return result
    }
}

// MARK: - Brace Strategy

private struct BraceScanner {

    let reader: LexicalReader
    var characters: [Character] { reader.characters }
    var syntax: MTLMergeSyntax { reader.syntax }

    init(characters: [Character], syntax: MTLMergeSyntax) {
        self.reader = LexicalReader(characters: characters, syntax: syntax)
    }

    func members(in range: Range<Int>) throws -> [TaggedBlock] {
        var blocks: [TaggedBlock] = []
        var comments: [Range<Int>] = []
        var index = range.lowerBound
        let limit = range.upperBound
        while index < limit {
            if characters[index].isWhitespace { index += 1; continue }
            if let end = reader.commentEnd(at: index, limit: limit) {
                comments.append(index..<end)
                index = end
                continue
            }
            guard let member = try scanMember(from: index, limit: limit) else { break }
            let leadStart = comments.first?.lowerBound ?? index
            let start = reader.startsLine(at: leadStart) ? reader.lineStart(of: leadStart) : leadStart
            let leading = comments.map { String(characters[$0]).trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            let signatureEnd = member.signatureEnd
            let signature = reader.normalised(index..<signatureEnd)
            let children: [TaggedBlock]
            if let body = member.body {
                children = try members(in: body)
            } else {
                children = []
            }
            let headerEnd = member.body?.lowerBound ?? member.end
            blocks.append(TaggedBlock(
                signature: signature,
                leadingComment: leading,
                range: start..<member.end,
                headerRange: start..<headerEnd,
                bodyRange: member.body,
                children: children
            ))
            comments = []
            index = member.next
        }
        return blocks
    }

    private struct Member {
        var end: Int
        var next: Int
        var signatureEnd: Int
        var body: Range<Int>?
    }

    private func scanMember(from start: Int, limit: Int) throws -> Member? {
        var index = start
        var depth = 0
        var lastCode = start
        var signatureEnd: Int?
        let terminators = syntax.terminators
        let newlineTerminates = terminators.contains("\n")
        while index < limit {
            let character = characters[index]
            if let end = reader.commentEnd(at: index, limit: limit) {
                index = end
                continue
            }
            if let end = reader.literalEnd(at: index, limit: limit) {
                index = end
                lastCode = end
                continue
            }
            switch character {
            case "(", "[":
                depth += 1
            case ")", "]":
                depth = max(0, depth - 1)
            case "=" where depth == 0 && signatureEnd == nil:
                let previous = index > start ? characters[index - 1] : " "
                let following = index + 1 < limit ? characters[index + 1] : " "
                if following != "=" && !"=!<>".contains(previous) { signatureEnd = lastCode }
            case syntax.opener:
                let close = try matchingBrace(from: index, limit: limit)
                if depth == 0 {
                    var end = close + 1
                    var probe = end
                    while probe < limit && (characters[probe] == " " || characters[probe] == "\t") {
                        probe += 1
                    }
                    if probe < limit, terminators.contains(characters[probe]),
                        characters[probe] != "\n"
                    {
                        end = probe + 1
                    }
                    return Member(
                        end: end, next: end, signatureEnd: signatureEnd ?? lastCode,
                        body: (index + 1)..<close)
                }
                index = close
                lastCode = close + 1
            case "}":
                throw TaggedBlockError.unbalancedBraces(offset: index)
            case "\n":
                if newlineTerminates && depth == 0 && index > start && lastCode > start
                    && !nextSignificantIs(syntax.opener, after: index, limit: limit)
                {
                    return leaf(start: start, end: lastCode, signatureEnd: signatureEnd, next: index)
                }
            default:
                if terminators.contains(character) && depth == 0 && character != "\n" {
                    return leaf(
                        start: start, end: index + 1, signatureEnd: signatureEnd ?? index,
                        next: index + 1)
                }
            }
            if !character.isWhitespace { lastCode = index + 1 }
            index += 1
        }
        return nil
    }

    private func leaf(start: Int, end: Int, signatureEnd: Int?, next: Int) -> Member {
        Member(end: end, next: next, signatureEnd: signatureEnd ?? end, body: nil)
    }

    private func nextSignificantIs(_ target: Character, after index: Int, limit: Int) -> Bool {
        var cursor = index + 1
        while cursor < limit {
            if characters[cursor].isWhitespace { cursor += 1; continue }
            if let end = reader.commentEnd(at: cursor, limit: limit) { cursor = end; continue }
            return characters[cursor] == target
        }
        return false
    }

    private func matchingBrace(from open: Int, limit: Int) throws -> Int {
        var depth = 0
        var index = open
        while index < limit {
            if let end = reader.commentEnd(at: index, limit: limit) { index = end; continue }
            if let end = reader.literalEnd(at: index, limit: limit) { index = end; continue }
            let character = characters[index]
            if character == syntax.opener {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        throw TaggedBlockError.unbalancedBraces(offset: open)
    }
}

// MARK: - Indentation Strategy

private struct IndentationScanner {

    let reader: LexicalReader
    var characters: [Character] { reader.characters }
    var syntax: MTLMergeSyntax { reader.syntax }

    init(characters: [Character], syntax: MTLMergeSyntax) {
        self.reader = LexicalReader(characters: characters, syntax: syntax)
    }

    private struct Line {
        var start: Int
        var end: Int
        var indent: Int
        var isBlank: Bool
        var isComment: Bool
    }

    private func lines(in range: Range<Int>) -> [Line] {
        var result: [Line] = []
        var start = range.lowerBound
        while start < range.upperBound {
            var end = start
            while end < range.upperBound && characters[end] != "\n" { end += 1 }
            var indent = 0
            var cursor = start
            while cursor < end && (characters[cursor] == " " || characters[cursor] == "\t") {
                indent += characters[cursor] == "\t" ? 4 : 1
                cursor += 1
            }
            let isBlank = cursor == end
            let isComment = !isBlank && reader.commentEnd(at: cursor, limit: end) != nil
                && reader.commentEnd(at: cursor, limit: end) == end
            result.append(Line(start: start, end: end, indent: indent, isBlank: isBlank, isComment: isComment))
            start = end + 1
        }
        return result
    }

    func members(in range: Range<Int>) -> [TaggedBlock] {
        let all = lines(in: range)
        guard let base = all.first(where: { !$0.isBlank && !$0.isComment })?.indent else { return [] }
        var blocks: [TaggedBlock] = []
        var comments: [Line] = []
        var index = 0
        while index < all.count {
            let line = all[index]
            if line.isBlank { index += 1; continue }
            if line.isComment { comments.append(line); index += 1; continue }
            if line.indent != base { index += 1; continue }
            var last = index
            var next = index + 1
            while next < all.count {
                let candidate = all[next]
                if candidate.isBlank { next += 1; continue }
                if candidate.indent > base { last = next; next += 1; continue }
                break
            }
            let headerLine = headerEnd(in: all, from: index, to: last)
            let startOffset = comments.first?.start ?? line.start
            let leading = comments
                .map { String(characters[$0.start..<$0.end]).trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            let end = all[last].end
            var body: Range<Int>?
            var children: [TaggedBlock] = []
            var headerRange = startOffset..<end
            var signatureEnd = all[headerLine ?? last].end
            if let headerLine, headerLine < last {
                let bodyStart = all[headerLine + 1].start
                body = bodyStart..<end
                headerRange = startOffset..<bodyStart
                children = members(in: bodyStart..<end)
                signatureEnd = openerIndex(in: all[headerLine])
            } else if headerLine != nil {
                signatureEnd = openerIndex(in: all[last])
            } else if let equals = assignmentIndex(in: line) {
                signatureEnd = equals
            }
            let firstCode = line.start + line.indent
            blocks.append(TaggedBlock(
                signature: reader.normalised(firstCode..<max(firstCode, signatureEnd)),
                leadingComment: leading,
                range: startOffset..<end,
                headerRange: headerRange,
                bodyRange: body,
                children: children
            ))
            comments = []
            index = next
        }
        return blocks
    }

    private func codeEnd(of line: Line) -> Int {
        var index = line.start + line.indent
        var depthEnd = line.end
        while index < line.end {
            if let end = reader.literalEnd(at: index, limit: line.end) { index = end; continue }
            if reader.commentEnd(at: index, limit: line.end) != nil { depthEnd = index; break }
            index += 1
        }
        var end = depthEnd
        while end > line.start && characters[end - 1].isWhitespace { end -= 1 }
        return end
    }

    private func headerEnd(in all: [Line], from first: Int, to last: Int) -> Int? {
        var depth = 0
        for index in first...last {
            let line = all[index]
            var cursor = line.start + line.indent
            let end = codeEnd(of: line)
            while cursor < end {
                if let literal = reader.literalEnd(at: cursor, limit: end) { cursor = literal; continue }
                switch characters[cursor] {
                case "(", "[", "{": depth += 1
                case ")", "]", "}": depth = max(0, depth - 1)
                default: break
                }
                cursor += 1
            }
            if depth == 0 && end > line.start && characters[end - 1] == syntax.opener { return index }
        }
        return nil
    }

    private func openerIndex(in line: Line) -> Int {
        codeEnd(of: line) - 1
    }

    private func assignmentIndex(in line: Line) -> Int? {
        var index = line.start + line.indent
        var depth = 0
        while index < line.end {
            if let literal = reader.literalEnd(at: index, limit: line.end) { index = literal; continue }
            let character = characters[index]
            if "([{".contains(character) { depth += 1 }
            if ")]}".contains(character) { depth = max(0, depth - 1) }
            if character == "=" && depth == 0 {
                let previous = index > line.start ? characters[index - 1] : " "
                let following = index + 1 < line.end ? characters[index + 1] : " "
                if following != "=" && !"=!<>".contains(previous) { return index }
            }
            index += 1
        }
        return nil
    }
}
