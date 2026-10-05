//
//  MTLLayoutConverter.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - Layout Converter

/// Applies an ``MTLLayoutConfiguration`` to a text.
///
/// The converter works on Unicode scalars so that a `\r\n` line break is two
/// units, as it is in a file. It classifies every scalar once (code, comment,
/// literal or verbatim), moves openers, and then converts indentation.
struct MTLLayoutConverter {

    /// The configuration to apply.
    let configuration: MTLLayoutConfiguration

    /// The converted text and the correspondence between old and new lines.
    struct Result: Equatable {

        /// The converted text.
        var text: String

        /// The new index of every old line, plus one entry for the end of the text.
        ///
        /// An old line that was merged into its predecessor maps to the index
        /// of the next line that survived, so that `lineMap[a]..<lineMap[b]` is
        /// the converted range of the old lines `a..<b`.
        var lineMap: [Int]

        /// Maps an old line index to the new one.
        ///
        /// - Parameter line: A zero-based old line index.
        /// - Returns: The zero-based new line index (indices past the end map to the last entry).
        func newLine(forOld line: Int) -> Int {
            lineMap[min(max(line, 0), lineMap.count - 1)]
        }
    }

    /// Converts a text.
    ///
    /// - Parameters:
    ///   - text: The text in the source layout.
    ///   - verbatimLines: Ranges of zero-based line indices (counting `\n`)
    ///     whose text must not be changed or be moved into.
    /// - Returns: The converted text and its line map.
    func convert(_ text: String, verbatimLines: [Range<Int>] = []) -> Result {
        let scalars = Array(text.unicodeScalars)
        let lineStarts = Self.lineStarts(of: scalars)
        var lineMap = Array(0...lineStarts.count)
        guard !configuration.isIdentity else {
            return Result(text: text, lineMap: lineMap)
        }
        let lexed = Lexer(syntax: configuration.syntax, scalars: scalars)
            .classify(verbatim: Self.spans(of: verbatimLines, lineStarts: lineStarts, count: scalars.count))

        var output = scalars
        var kinds = lexed.kinds
        if configuration.openerPlacement == .sameLine {
            let moved = moveOpeners(scalars, lexed, lineStarts: lineStarts)
            output = moved.scalars
            kinds = moved.kinds
            lineMap = Self.lineMap(count: lineStarts.count, removed: moved.removedLines)
        }
        output = convertIndentation(output, kinds: kinds)
        var view = String.UnicodeScalarView()
        view.append(contentsOf: output)
        return Result(text: String(view), lineMap: lineMap)
    }

    // MARK: - Lines

    /// The offsets at which lines start, counting `\n` only.
    private static func lineStarts(of scalars: [Unicode.Scalar]) -> [Int] {
        var starts = [0]
        for (index, scalar) in scalars.enumerated() where scalar == "\n" {
            starts.append(index + 1)
        }
        return starts
    }

    /// Converts ranges of line indices to ranges of scalar offsets.
    private static func spans(of lines: [Range<Int>], lineStarts: [Int], count: Int) -> [Range<Int>] {
        lines.compactMap { range in
            let first = max(range.lowerBound, 0)
            guard first < lineStarts.count, first < range.upperBound else { return nil }
            let lower = lineStarts[first]
            let upper = range.upperBound < lineStarts.count ? lineStarts[range.upperBound] : count
            return lower < upper ? lower..<upper : nil
        }.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Builds the old to new line map from the indices of the removed lines.
    private static func lineMap(count: Int, removed: [Int]) -> [Int] {
        var map: [Int] = []
        var removedBefore = 0
        let sorted = removed.sorted()
        for line in 0...count {
            while removedBefore < sorted.count, sorted[removedBefore] < line { removedBefore += 1 }
            map.append(line - removedBefore)
        }
        return map
    }

    // MARK: - Lexical Classification

    /// The lexical class of a scalar.
    fileprivate enum Kind: UInt8 {
        case code
        case lineComment
        case blockComment
        case literal
        case verbatim
    }

    /// The classification of a whole text.
    fileprivate struct Lexed {

        /// The class of each scalar.
        var kinds: [Kind]

        /// Whether the scalar is the last of a closed block comment or literal.
        var closes: [Bool]
    }

    /// Classifies the scalars of a text as code, comments, literals or verbatim text.
    fileprivate struct Lexer {

        let lineComments: [[Unicode.Scalar]]
        let blockComments: [(start: [Unicode.Scalar], end: [Unicode.Scalar])]
        let quotes: Set<Unicode.Scalar>
        let scalars: [Unicode.Scalar]

        /// The scalar that escapes the next one inside a literal.
        private static let escape: Unicode.Scalar = "\\"

        init(syntax: MTLMergeSyntax, scalars: [Unicode.Scalar]) {
            lineComments = syntax.lineComments.map { Array($0.unicodeScalars) }.filter { !$0.isEmpty }
            blockComments = syntax.blockComments.map {
                (Array($0.start.unicodeScalars), Array($0.end.unicodeScalars))
            }.filter { !$0.start.isEmpty && !$0.end.isEmpty }
            quotes = Set(syntax.quotes.flatMap { $0.unicodeScalars })
            self.scalars = scalars
        }

        func classify(verbatim spans: [Range<Int>]) -> Lexed {
            var kinds = [Kind](repeating: .code, count: scalars.count)
            var closes = [Bool](repeating: false, count: scalars.count)
            var spanIndex = 0
            var i = 0
            func mark(_ range: Range<Int>, _ kind: Kind) {
                for k in range { kinds[k] = kind }
            }
            while i < scalars.count {
                if spanIndex < spans.count, i >= spans[spanIndex].lowerBound {
                    mark(i..<spans[spanIndex].upperBound, .verbatim)
                    i = spans[spanIndex].upperBound
                    spanIndex += 1
                    continue
                }
                let limit = spanIndex < spans.count ? spans[spanIndex].lowerBound : scalars.count
                if lineComments.contains(where: { hasPrefix($0, at: i, limit: limit) }) {
                    var end = i
                    while end < limit, scalars[end] != "\n", scalars[end] != "\r" { end += 1 }
                    mark(i..<end, .lineComment)
                    i = end
                } else if let pair = blockComments.first(where: { hasPrefix($0.start, at: i, limit: limit) }) {
                    var end = i + pair.start.count
                    var closed = false
                    while end < limit {
                        if hasPrefix(pair.end, at: end, limit: limit) {
                            end += pair.end.count
                            closed = true
                            break
                        }
                        end += 1
                    }
                    mark(i..<end, .blockComment)
                    if closed { closes[end - 1] = true }
                    i = end
                } else if quotes.contains(scalars[i]), let literal = literalEnd(at: i, limit: limit) {
                    mark(i..<literal.end, .literal)
                    if literal.closed { closes[literal.end - 1] = true }
                    i = literal.end
                } else {
                    i += 1
                }
            }
            return Lexed(kinds: kinds, closes: closes)
        }

        /// Finds the end of the literal that starts at an index, if there is one.
        private func literalEnd(at index: Int, limit: Int) -> (end: Int, closed: Bool)? {
            let quote = scalars[index]
            let triple = [Unicode.Scalar](repeating: quote, count: 3)
            if hasPrefix(triple, at: index, limit: limit) {
                var end = index + 3
                while end < limit {
                    if scalars[end] == Self.escape { end += 2; continue }
                    if hasPrefix(triple, at: end, limit: limit) { return (end + 3, true) }
                    end += 1
                }
                return (limit, false)
            }
            var end = index + 1
            while end < limit {
                let scalar = scalars[end]
                if scalar == Self.escape { end += 2; continue }
                if scalar == quote { return (end + 1, true) }
                if scalar == "\n" || scalar == "\r" { return nil }
                end += 1
            }
            return nil
        }

        /// Whether a marker occurs at an index without crossing the limit.
        func hasPrefix(_ marker: [Unicode.Scalar], at index: Int, limit: Int) -> Bool {
            guard index + marker.count <= limit else { return false }
            for offset in marker.indices where scalars[index + offset] != marker[offset] { return false }
            return true
        }
    }

    // MARK: - Opener Placement

    /// The scalars, classes and removed lines after moving openers.
    private struct Moved {
        var scalars: [Unicode.Scalar]
        var kinds: [Kind]
        var removedLines: [Int]
    }

    /// Moves every opener that stands alone on its line to the end of the previous line.
    private func moveOpeners(_ scalars: [Unicode.Scalar], _ lexed: Lexed, lineStarts: [Int]) -> Moved {
        let opener = Array(String(configuration.syntax.opener).unicodeScalars)
        let terminators = Set(configuration.syntax.terminators.flatMap { $0.unicodeScalars })
        let reader = Lexer(syntax: configuration.syntax, scalars: scalars)
        var moved = Moved(scalars: [], kinds: [], removedLines: [])
        guard !opener.isEmpty else { return Moved(scalars: scalars, kinds: lexed.kinds, removedLines: []) }
        var current = 0
        var i = 0

        func lineIndex(of offset: Int) -> Int {
            var low = 0
            var high = lineStarts.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if lineStarts[middle] <= offset { low = middle } else { high = middle - 1 }
            }
            return low
        }

        while i < scalars.count {
            guard lexed.kinds[i] == .code, reader.hasPrefix(opener, at: i, limit: scalars.count),
                let end = lineEnd(after: i + opener.count, in: scalars),
                let begin = lineStart(before: i, in: scalars)
            else {
                i += 1
                continue
            }
            let previous = begin - 1
            let standsAlone =
                lexed.kinds[begin..<i].allSatisfy { $0 == .code }
                && lexed.kinds[(i + opener.count)..<end].allSatisfy { $0 == .code }
            let followsStatement = terminators.contains(scalars[previous])
            let followsOpener =
                begin >= opener.count && lexed.kinds[previous] == .code
                && Array(scalars[(begin - opener.count)..<begin]) == opener
            let joinable = lexed.kinds[previous] == .code || lexed.closes[previous]
            if standsAlone, !followsStatement, !followsOpener, joinable {
                moved.scalars.append(contentsOf: scalars[current..<begin])
                moved.kinds.append(contentsOf: lexed.kinds[current..<begin])
                let replacement: [Unicode.Scalar] = [" "] + opener
                moved.scalars.append(contentsOf: replacement)
                moved.kinds.append(contentsOf: [Kind](repeating: .code, count: replacement.count))
                current = end
                let first = lineIndex(of: begin - 1) + 1
                let last = lineIndex(of: i)
                if first <= last { moved.removedLines.append(contentsOf: first...last) }
            }
            i = end + 1
        }
        moved.scalars.append(contentsOf: scalars[current...])
        moved.kinds.append(contentsOf: lexed.kinds[current...])
        return moved
    }

    /// Finds the line break that follows an index when only blanks lie between.
    ///
    /// - Returns: The offset of the `\n`, or of the `\r` of a `\r\n`; `nil` if other text
    ///   (or the end of the text, or a lone `\r`) comes first.
    private func lineEnd(after index: Int, in scalars: [Unicode.Scalar]) -> Int? {
        var k = index
        while k < scalars.count {
            switch scalars[k] {
            case "\n": return k
            case "\r": return k + 1 < scalars.count && scalars[k + 1] == "\n" ? k : nil
            case " ", "\t": k += 1
            default: return nil
            }
        }
        return nil
    }

    /// Finds the end of the last non-blank text before an index on an earlier line.
    ///
    /// - Returns: The offset just after the last non-blank scalar, or `nil` if the
    ///   index is not preceded by blanks and at least one line break and then text.
    private func lineStart(before index: Int, in scalars: [Unicode.Scalar]) -> Int? {
        var k = index - 1
        var sawLineFeed = false
        while k >= 0 {
            let scalar = scalars[k]
            if scalar == "\n" {
                if k > 0 && scalars[k - 1] == "\r" { k -= 1 }
                sawLineFeed = true
            } else if scalar != " " && scalar != "\t" {
                return sawLineFeed ? k + 1 : nil
            }
            k -= 1
        }
        return nil
    }

    // MARK: - Indentation

    /// Replaces each leading source indentation unit by the target unit.
    private func convertIndentation(_ scalars: [Unicode.Scalar], kinds: [Kind]) -> [Unicode.Scalar] {
        let source = Array(configuration.sourceIndent.unicodeScalars)
        let target = Array(configuration.targetIndent.unicodeScalars)
        guard !source.isEmpty, source != target else { return scalars }
        var result: [Unicode.Scalar] = []
        result.reserveCapacity(scalars.count)
        var i = 0
        var atLineStart = true
        while i < scalars.count {
            if atLineStart {
                atLineStart = false
                if kinds[i] != .literal, kinds[i] != .verbatim {
                    while i + source.count <= scalars.count, scalars[i..<(i + source.count)].elementsEqual(source) {
                        result.append(contentsOf: target)
                        i += source.count
                    }
                    if i >= scalars.count { break }
                }
            }
            let scalar = scalars[i]
            result.append(scalar)
            atLineStart = scalar == "\n" || scalar == "\r"
            i += 1
        }
        return result
    }
}
