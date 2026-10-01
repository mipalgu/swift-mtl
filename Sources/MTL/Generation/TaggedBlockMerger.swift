//
//  TaggedBlockMerger.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - Emitted Region

/// The lines of a generated file that were produced by an `[emit]` block.
///
/// The merger uses emitted regions to union collected sets (such as imports
/// or includes) present in an existing file with those of the new text.
public struct MTLEmittedRegion: Sendable, Equatable, Hashable {

    /// The name of the collected set.
    public let name: String

    /// The zero-based index of the first line of the region.
    public let firstLine: Int

    /// The number of lines of the region (zero for an empty set).
    public let lineCount: Int

    /// Creates an emitted region.
    ///
    /// - Parameters:
    ///   - name: The name of the collected set.
    ///   - firstLine: The zero-based index of the first line of the region.
    ///   - lineCount: The number of lines of the region.
    public init(name: String, firstLine: Int, lineCount: Int) {
        self.name = name
        self.firstLine = firstLine
        self.lineCount = lineCount
    }
}

// MARK: - Tagged Block Merger

/// Merges freshly generated text into an existing file, block by block.
///
/// The merger is language-neutral and driven by an ``MTLMergeConfiguration``.
/// Blocks are matched by their normalised signature within the matching
/// parent, so the key of a block is its signature plus its nesting path.
///
/// ## Rules
///
/// - A matched block whose leading comment carries the keep tag, or carries
///   no generated tag, is preserved from the existing file.
/// - A matched block that carries the generated tag is replaced by the new
///   block.
/// - A new block that carries a tag and has no counterpart in the existing
///   file is added after the block that precedes it in the new text.
/// - An existing block that carries the generated tag but is no longer
///   generated is removed. Blocks that carry the keep tag or no tag stay.
/// - A block with a body is merged recursively when its body contains tagged
///   blocks; its header follows the same ownership rules and its closer is
///   kept. Other blocks are replaced or preserved as a whole.
/// - Lines of emitted regions in the existing file that are absent from the
///   new region are kept, so collected sets are unioned.
///
/// ## Example
///
/// ```swift
/// let merger = TaggedBlockMerger(configuration: configuration)
/// let merged = try merger.merge(existing: onDisk, generated: fresh)
/// ```
public struct TaggedBlockMerger: Sendable {

    /// The configuration that supplies tags, strategy and syntax.
    public let configuration: MTLMergeConfiguration

    /// Creates a merger.
    ///
    /// - Parameter configuration: The merge configuration to apply.
    public init(configuration: MTLMergeConfiguration) {
        self.configuration = configuration
    }

    /// Merges generated text into an existing file.
    ///
    /// Line endings are normalised to `\n`. If the existing text contains
    /// only whitespace, the generated text is returned unchanged.
    ///
    /// - Parameters:
    ///   - existing: The current content of the target file.
    ///   - generated: The freshly generated content.
    ///   - regions: The emitted regions of the generated content.
    /// - Returns: The merged content.
    /// - Throws: ``TaggedBlockError`` if either text has unbalanced braces.
    public func merge(
        existing: String,
        generated: String,
        regions: [MTLEmittedRegion] = []
    ) throws -> String {
        let old = Self.normalisedLineEndings(existing)
        let new = Self.normalisedLineEndings(generated)
        guard !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return new }
        let scanner = TaggedBlockScanner(configuration: configuration)
        let oldScan = try scanner.scan(old)
        let newScan = try scanner.scan(new)
        let root = TaggedBlock(
            signature: "", leadingComment: "", range: 0..<oldScan.characters.count,
            headerRange: 0..<0, bodyRange: 0..<oldScan.characters.count, children: oldScan.blocks)
        let newRoot = TaggedBlock(
            signature: "", leadingComment: "", range: 0..<newScan.characters.count,
            headerRange: 0..<0, bodyRange: 0..<newScan.characters.count, children: newScan.blocks)
        var merged = mergeBody(existing: root, old: oldScan, generated: newRoot, new: newScan)
        merged = unionRegions(in: merged, generated: new, regions: regions)
        return merged
    }

    // MARK: Block Merging

    private struct Item {
        var gap: String
        var text: String
    }

    private func mergeBody(
        existing: TaggedBlock, old: TaggedBlockScan,
        generated: TaggedBlock, new: TaggedBlockScan
    ) -> String {
        guard let oldBody = existing.bodyRange, let newBody = generated.bodyRange else {
            return old.text(existing.range)
        }
        let oldKeys = keys(of: existing.children)
        let newKeys = keys(of: generated.children)
        var oldIndexByKey: [String: Int] = [:]
        for (index, key) in oldKeys.enumerated() { oldIndexByKey[key] = index }
        var newIndexByKey: [String: Int] = [:]
        for (index, key) in newKeys.enumerated() { newIndexByKey[key] = index }

        // Existing blocks, in order, with the removal rule applied.
        var items: [(oldIndex: Int?, newIndex: Int?, item: Item)] = []
        var cursor = oldBody.lowerBound
        for (index, block) in existing.children.enumerated() {
            let gap = old.text(cursor..<block.range.lowerBound)
            cursor = block.range.upperBound
            if let newIndex = newIndexByKey[oldKeys[index]] {
                let text = mergedBlock(
                    existing: block, old: old, generated: generated.children[newIndex], new: new)
                items.append((index, newIndex, Item(gap: gap, text: text)))
            } else if isRemovable(block) {
                continue
            } else {
                items.append((index, nil, Item(gap: gap, text: old.text(block.range))))
            }
        }
        let tail = old.text(cursor..<oldBody.upperBound)

        // New tagged blocks without a counterpart are inserted after their predecessor.
        var anchor: Int?
        var newCursor = newBody.lowerBound
        for (index, block) in generated.children.enumerated() {
            let gap = new.text(newCursor..<block.range.lowerBound)
            newCursor = block.range.upperBound
            if let position = items.firstIndex(where: { $0.newIndex == index }) {
                anchor = position
            } else if oldIndexByKey[newKeys[index]] == nil, isTagged(block) {
                let insertion = (anchor ?? -1) + 1
                items.insert((nil, index, Item(gap: gap, text: new.text(block.range))), at: insertion)
                anchor = insertion
            }
        }

        return items.map { $0.item.gap + $0.item.text }.joined() + tail
    }

    private func mergedBlock(
        existing: TaggedBlock, old: TaggedBlockScan,
        generated: TaggedBlock, new: TaggedBlockScan
    ) -> String {
        let ownership = configuration.ownership(ofLeadingComment: existing.leadingComment)
        if ownership == .user { return old.text(existing.range) }
        let isContainer = existing.bodyRange != nil && generated.bodyRange != nil
            && (existing.children.contains(where: isTagged) || generated.children.contains(where: isTagged))
        if isContainer, let oldBody = existing.bodyRange, let newBody = generated.bodyRange {
            let headerSource: (TaggedBlockScan, Range<Int>) = ownership == .kept
                ? (old, existing.range.lowerBound..<oldBody.lowerBound)
                : (new, generated.range.lowerBound..<newBody.lowerBound)
            let body = mergeBody(existing: existing, old: old, generated: generated, new: new)
            let footer = old.text(oldBody.upperBound..<existing.range.upperBound)
            return headerSource.0.text(headerSource.1) + body + footer
        }
        return ownership == .kept ? old.text(existing.range) : new.text(generated.range)
    }

    private func isTagged(_ block: TaggedBlock) -> Bool {
        configuration.ownership(ofLeadingComment: block.leadingComment) != .user
    }

    private func isRemovable(_ block: TaggedBlock) -> Bool {
        configuration.ownership(ofLeadingComment: block.leadingComment) == .generated
    }

    private func keys(of blocks: [TaggedBlock]) -> [String] {
        var counts: [String: Int] = [:]
        return blocks.map { block in
            let occurrence = counts[block.signature, default: 0]
            counts[block.signature] = occurrence + 1
            return occurrence == 0 ? block.signature : "\(block.signature)#\(occurrence)"
        }
    }

    // MARK: Region Union

    private func unionRegions(
        in merged: String, generated: String, regions: [MTLEmittedRegion]
    ) -> String {
        guard !regions.isEmpty else { return merged }
        let generatedLines = generated.components(separatedBy: "\n")
        var lines = merged.components(separatedBy: "\n")
        for region in regions where region.lineCount > 0 {
            let end = min(generatedLines.count, region.firstLine + region.lineCount)
            guard region.firstLine < end else { continue }
            let regionLines = Array(generatedLines[region.firstLine..<end])
            lines = union(region: regionLines, into: lines)
        }
        return lines.joined(separator: "\n")
    }

    private func union(region: [String], into lines: [String]) -> [String] {
        let regionSet = Set(region.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        let matched = lines.indices.filter { regionSet.contains(lines[$0].trimmingCharacters(in: .whitespaces)) }
        guard let first = matched.first, let last = matched.last else {
            return insertRegion(region, into: lines)
        }
        func isBlank(_ index: Int) -> Bool { lines[index].trimmingCharacters(in: .whitespaces).isEmpty }
        var lower = first
        while lower > 0 && !isBlank(lower - 1) { lower -= 1 }
        var upper = last
        while upper + 1 < lines.count && !isBlank(upper + 1) { upper += 1 }
        var before: [String] = []
        var after: [String] = []
        for index in lower...upper {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || regionSet.contains(trimmed) { continue }
            if index < first { before.append(lines[index]) } else { after.append(lines[index]) }
        }
        return Array(lines[..<lower]) + before + region + after + Array(lines[(upper + 1)...])
    }

    private func insertRegion(_ region: [String], into lines: [String]) -> [String] {
        let scanner = TaggedBlockScanner(configuration: configuration)
        let text = lines.joined(separator: "\n")
        guard let scan = try? scanner.scan(text),
            let firstTagged = scan.blocks.first(where: isTagged)
        else {
            return lines + region
        }
        let lineIndex = scan.characters[..<firstTagged.range.lowerBound].filter { $0 == "\n" }.count
        return Array(lines[..<lineIndex]) + region + [""] + Array(lines[lineIndex...])
    }

    // MARK: Helpers

    /// Converts all line endings of a text to `\n`.
    ///
    /// - Parameter text: The text to normalise.
    /// - Returns: The text with `\r\n` and `\r` replaced by `\n`.
    public static func normalisedLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
