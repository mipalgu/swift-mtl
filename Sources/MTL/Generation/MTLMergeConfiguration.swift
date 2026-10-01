//
//  MTLMergeConfiguration.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - Merge Strategy

/// The way in which block boundaries are found in a target file.
public enum MTLMergeStrategy: String, Sendable, Codable, Equatable, Hashable, CaseIterable {

    /// Blocks are delimited by matching braces.
    ///
    /// The scanner is aware of string and character literals as well as line
    /// and block comments, so braces inside them are ignored.
    case braces

    /// Blocks are delimited by indentation.
    ///
    /// A block starts at a line that ends with the block opener and extends
    /// over all following lines that are indented deeper.
    case indentation
}

// MARK: - Merge Syntax

/// The lexical conventions used to find blocks in a target file.
///
/// The syntax tells the scanner which text to skip (comments and literals)
/// and which characters end a member that has no braced body. The defaults
/// depend on the merge strategy and suit most languages; a template can
/// override any part through optional arguments of the `[merge]` declaration.
public struct MTLMergeSyntax: Sendable, Equatable, Hashable {

    /// Markers that start a comment running to the end of the line.
    public var lineComments: [String]

    /// Delimiters of comments that may span lines, as start and end pairs.
    public var blockComments: [BlockComment]

    /// The characters that delimit string and character literals.
    public var quotes: [Character]

    /// The characters that end a member without a braced body.
    ///
    /// A newline character ends a member at the end of its line unless the
    /// next significant character opens a body.
    public var terminators: [Character]

    /// The character that opens the body of a block.
    public var opener: Character

    /// A pair of delimiters of a block comment.
    public struct BlockComment: Sendable, Equatable, Hashable {

        /// The text that starts the comment.
        public var start: String

        /// The text that ends the comment.
        public var end: String

        /// Creates a pair of block comment delimiters.
        ///
        /// - Parameters:
        ///   - start: The text that starts the comment.
        ///   - end: The text that ends the comment.
        public init(start: String, end: String) {
            self.start = start
            self.end = end
        }
    }

    /// Creates a syntax description.
    ///
    /// - Parameters:
    ///   - lineComments: Markers that start a comment running to the end of the line.
    ///   - blockComments: Delimiters of comments that may span lines.
    ///   - quotes: The characters that delimit string and character literals.
    ///   - terminators: The characters that end a member without a braced body.
    ///   - opener: The character that opens the body of a block.
    public init(
        lineComments: [String],
        blockComments: [BlockComment],
        quotes: [Character],
        terminators: [Character],
        opener: Character
    ) {
        self.lineComments = lineComments
        self.blockComments = blockComments
        self.quotes = quotes
        self.terminators = terminators
        self.opener = opener
    }

    /// The default syntax for the given strategy.
    ///
    /// - Parameter strategy: The merge strategy.
    /// - Returns: Brace-oriented conventions (slash comments, semicolon
    ///   terminators) for `.braces`; hash comments and a colon opener for
    ///   `.indentation`.
    public static func defaults(for strategy: MTLMergeStrategy) -> MTLMergeSyntax {
        switch strategy {
        case .braces:
            return MTLMergeSyntax(
                lineComments: ["//"],
                blockComments: [BlockComment(start: "/*", end: "*/")],
                quotes: ["\"", "'"],
                terminators: [";"],
                opener: "{"
            )
        case .indentation:
            return MTLMergeSyntax(
                lineComments: ["#"],
                blockComments: [],
                quotes: ["\"", "'"],
                terminators: [],
                opener: ":"
            )
        }
    }
}

// MARK: - Merge Configuration

/// The tagged-block merge configuration declared by a template module.
///
/// A module declares its configuration with
/// `[merge ('/**', '*/', '@generated', '@generated NOT', 'braces')/]`. When a
/// generated file already exists, the generator merges the new text into the
/// existing file: blocks whose leading comment carries the keep tag, or that
/// carry no generated tag at all, are preserved; blocks that carry the
/// generated tag are replaced; new generated blocks are added; and generated
/// blocks that are no longer produced are removed.
///
/// The configuration is language-neutral. Everything that is specific to a
/// target language, such as the tags and the comment delimiters, is supplied
/// by the template.
public struct MTLMergeConfiguration: Sendable, Equatable, Hashable {

    /// The text that starts a leading comment, for example `/**`.
    public let commentStart: String

    /// The text that ends a leading comment, or an empty string for comments
    /// that run to the end of the line.
    public let commentEnd: String

    /// The tag that marks a block as generated, for example `@generated`.
    public let generatedTag: String

    /// The tag that marks a block as edited by hand, for example
    /// `@generated NOT`.
    ///
    /// The keep tag takes precedence over the generated tag, so it may
    /// contain the generated tag as a prefix.
    public let keepTag: String

    /// How block boundaries are found.
    public let strategy: MTLMergeStrategy

    /// The lexical conventions used to find blocks.
    public let syntax: MTLMergeSyntax

    /// The glob patterns of the files this configuration applies to.
    ///
    /// An empty list means that the configuration applies to every file. See
    /// ``applies(toFile:)`` for the pattern syntax.
    public let filePatterns: [String]

    /// Creates a merge configuration.
    ///
    /// The declared comment delimiters are added to the comment markers of
    /// the syntax, so a leading comment is always recognised as a comment.
    ///
    /// - Parameters:
    ///   - commentStart: The text that starts a leading comment.
    ///   - commentEnd: The text that ends a leading comment, empty for line comments.
    ///   - generatedTag: The tag that marks a block as generated.
    ///   - keepTag: The tag that marks a block as edited by hand.
    ///   - strategy: How block boundaries are found (default: `.braces`).
    ///   - syntax: Overrides for the lexical conventions (default: the strategy defaults).
    ///   - filePatterns: Glob patterns of the files to merge (default: all files).
    public init(
        commentStart: String,
        commentEnd: String,
        generatedTag: String,
        keepTag: String,
        strategy: MTLMergeStrategy = .braces,
        syntax: MTLMergeSyntax? = nil,
        filePatterns: [String] = []
    ) {
        self.filePatterns = filePatterns
        self.commentStart = commentStart
        self.commentEnd = commentEnd
        self.generatedTag = generatedTag
        self.keepTag = keepTag
        self.strategy = strategy
        var resolved = syntax ?? .defaults(for: strategy)
        if !commentStart.isEmpty {
            if commentEnd.isEmpty {
                if !resolved.lineComments.contains(commentStart) {
                    resolved.lineComments.append(commentStart)
                }
            } else {
                let pair = MTLMergeSyntax.BlockComment(start: commentStart, end: commentEnd)
                if !resolved.blockComments.contains(pair) {
                    resolved.blockComments.append(pair)
                }
            }
        }
        self.syntax = resolved
    }

    /// The classification of a block by its leading comment.
    public enum Ownership: Sendable, Equatable {

        /// The block was generated and may be replaced.
        case generated

        /// The block was generated but edited by hand and must be kept.
        case kept

        /// The block carries no tag and belongs to the user.
        case user
    }

    /// Classifies a leading comment.
    ///
    /// - Parameter leadingComment: The text of the comment that precedes a block.
    /// - Returns: `.kept` if the comment contains the keep tag, otherwise
    ///   `.generated` if it contains the generated tag, otherwise `.user`.
    public func ownership(ofLeadingComment leadingComment: String) -> Ownership {
        if !keepTag.isEmpty && leadingComment.contains(keepTag) { return .kept }
        if !generatedTag.isEmpty && leadingComment.contains(generatedTag) { return .generated }
        return .user
    }

    /// Tells whether this configuration applies to the file with the given URL.
    ///
    /// Without file patterns every file matches. Otherwise the URL must match at
    /// least one pattern. In a pattern, `*` matches any run of characters except
    /// `/`, `**` matches any run of characters including `/`, and `?` matches
    /// exactly one character other than `/`. A pattern without `/` is matched
    /// against the last path component of the URL; a pattern with `/` is matched
    /// against the whole URL.
    ///
    /// - Parameter url: The URL of the file as written in the `file` block.
    /// - Returns: `true` if the file is to be merged.
    public func applies(toFile url: String) -> Bool {
        guard !filePatterns.isEmpty else { return true }
        return filePatterns.contains { MTLFileGlob.matches(pattern: $0, url: url) }
    }
}
