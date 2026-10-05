//
//  MTLLayoutConfiguration.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - Opener Placement

/// Where the token that opens a block is written.
///
/// The placement is a property of the text a template set generates and of
/// the layout a project wants. Templates emit one placement; a layout
/// configuration converts it to the other.
public enum MTLOpenerPlacement: String, Sendable, Codable, Equatable, Hashable, CaseIterable {

    /// The opener stands on a line of its own, as generated.
    ///
    /// The text is left as it is: this is the placement most template sets
    /// write, so selecting it requests no conversion.
    case ownLine

    /// An opener that stands alone on its line moves to the end of the
    /// preceding line, separated from it by one space.
    ///
    /// See ``MTLLayoutConfiguration`` for the exact rules.
    case sameLine
}

// MARK: - Layout Configuration

/// The layout conversion applied to generated text.
///
/// A layout configuration converts text that a template set writes in one
/// code style into another, using only lexical knowledge supplied as data. It
/// does two independent things:
///
/// - **Indentation.** Each occurrence of ``sourceIndent`` at the start of a
///   line is replaced by ``targetIndent``. Only the unbroken run of units at the
///   very start of a line is converted; text inside a line is never touched.
///   Lines that begin inside a multi-line string literal, and the text of
///   protected areas preserved from an existing file, are left alone. Lines
///   inside comments are converted, because their indentation is cosmetic.
/// - **Opener placement.** With ``MTLOpenerPlacement/sameLine``, an opener that
///   stands alone on its line moves to the end of the preceding line.
///
/// ## Opener placement rules
///
/// With ``MTLOpenerPlacement/sameLine``, an opener token (``MTLMergeSyntax/opener``)
/// is moved when all of the following hold:
///
/// 1. The token is code, not part of a comment or a string literal.
/// 2. Only spaces and tabs precede it on its line, and only spaces and tabs
///    follow it before a line break (`\n` or `\r\n`). A token at the very end
///    of the text without a line break is not moved.
/// 3. An earlier non-blank line exists. Blank lines between that line and
///    the token are removed.
/// 4. The last non-blank character of that earlier line is not one of the
///    ``MTLMergeSyntax/terminators`` (for a brace language this keeps a block
///    that follows a complete statement on its own line).
/// 5. That character is not itself an opener token, so two openers in a row are
///    never merged onto one line.
/// 6. That character is code, or the end of a closed block comment or string
///    literal. A line that ends in a line comment, inside a block comment that
///    continues onto the next line, or in a protected area is never joined.
///
/// A moved token replaces the trailing blanks of the earlier line, the
/// blank lines, the token's indentation and the blanks after it with a single
/// space followed by the token. The line break after the token is kept.
/// Everything else, including the indentation of the earlier line, is left
/// untouched.
///
/// ## Idempotence
///
/// Opener placement is idempotent. Indentation conversion is idempotent
/// whenever ``targetIndent`` does not itself start with ``sourceIndent``
/// (for example tabs to spaces, spaces to tabs, or four spaces to two). When it
/// does (for example two spaces to four), converting already converted text
/// converts it again, so the conversion must be applied exactly once to text
/// in the source layout. The generator does that by converting freshly
/// generated text before it is merged with an existing file.
///
/// ## Example
///
/// ```swift
/// let layout = MTLLayoutConfiguration(
///     sourceIndent: "\t", targetIndent: "    ", openerPlacement: .sameLine)
/// let converted = layout.convert("class A\n{\n\tvoid f()\n\t{\n\t}\n}\n")
/// // "class A {\n    void f() {\n    }\n}\n"
/// ```
public struct MTLLayoutConfiguration: Sendable, Equatable, Hashable {

    /// The indentation unit of the generated text.
    ///
    /// An empty unit disables indentation conversion.
    public var sourceIndent: String

    /// The indentation unit that replaces ``sourceIndent``.
    public var targetIndent: String

    /// Where openers are written in the converted text.
    public var openerPlacement: MTLOpenerPlacement

    /// The lexical conventions used to recognise comments, literals and openers.
    ///
    /// The comment delimiters, the quote characters, the terminators and the
    /// opener token are read from this value. It defaults to the brace
    /// conventions of ``MTLMergeSyntax/defaults(for:)``.
    public var syntax: MTLMergeSyntax

    /// The glob patterns of the files this configuration applies to.
    ///
    /// An empty list means that the configuration applies to every file. See
    /// ``applies(toFile:)``.
    public var filePatterns: [String]

    /// Creates a layout configuration.
    ///
    /// - Parameters:
    ///   - sourceIndent: The indentation unit of the generated text (default: a tab).
    ///   - targetIndent: The indentation unit to write (default: a tab).
    ///   - openerPlacement: Where openers are written (default: ``MTLOpenerPlacement/ownLine``).
    ///   - syntax: The lexical conventions (default: the brace conventions).
    ///   - filePatterns: Glob patterns of the files to convert (default: all files).
    public init(
        sourceIndent: String = MTLLayoutConfiguration.defaultIndent,
        targetIndent: String = MTLLayoutConfiguration.defaultIndent,
        openerPlacement: MTLOpenerPlacement = .ownLine,
        syntax: MTLMergeSyntax = .defaults(for: .braces),
        filePatterns: [String] = []
    ) {
        self.sourceIndent = sourceIndent
        self.targetIndent = targetIndent
        self.openerPlacement = openerPlacement
        self.syntax = syntax
        self.filePatterns = filePatterns
    }

    /// The indentation unit used when none is given.
    public static let defaultIndent = "\t"

    /// Whether the configuration leaves every text unchanged.
    public var isIdentity: Bool {
        (sourceIndent.isEmpty || sourceIndent == targetIndent) && openerPlacement == .ownLine
    }

    /// Tells whether this configuration applies to the file with the given URL.
    ///
    /// Without file patterns every file matches. The pattern syntax is the one
    /// of ``MTLMergeConfiguration/applies(toFile:)``.
    ///
    /// - Parameter url: The URL of the file as written in the `file` block.
    /// - Returns: `true` if the file is to be converted.
    public func applies(toFile url: String) -> Bool {
        guard !filePatterns.isEmpty else { return true }
        return filePatterns.contains { MTLFileGlob.matches(pattern: $0, url: url) }
    }

    /// Converts the layout of a text.
    ///
    /// - Parameter text: The text in the source layout, with `\n` or `\r\n`
    ///   line breaks, which are preserved.
    /// - Returns: The text in the target layout.
    public func convert(_ text: String) -> String {
        MTLLayoutConverter(configuration: self).convert(text).text
    }
}

// MARK: - Layout Post Processor

/// A file post-processor that converts the layout of generated files.
///
/// The processor converts a file only if its path matches the file patterns of
/// the configuration. Attach it to a generation strategy to convert text after
/// merging; the generator's own ``MTLGeneratorOptions/layout`` option converts
/// before merging, which is usually what is wanted when files are regenerated.
public struct MTLLayoutPostProcessor: MTLFilePostProcessor {

    /// The layout configuration to apply.
    public let configuration: MTLLayoutConfiguration

    /// Creates a post-processor.
    ///
    /// - Parameter configuration: The layout configuration to apply.
    public init(configuration: MTLLayoutConfiguration) {
        self.configuration = configuration
    }

    /// Converts the layout of a file.
    ///
    /// - Parameters:
    ///   - content: The content about to be written.
    ///   - path: The path of the target file, matched against the file patterns.
    /// - Returns: The converted content, or the content itself if the
    ///   configuration does not apply to the path.
    public func process(_ content: String, path: String) async throws -> String {
        configuration.applies(toFile: path) ? configuration.convert(content) : content
    }
}

// MARK: - Layout Option Keys

/// The keys accepted as `key=value` arguments of the `[layout]` declaration.
///
/// ```mtl
/// [layout ('indent=\t', 'targetIndent=  ', 'opener=sameLine', 'files=*.java')/]
/// ```
///
/// Every argument is a string of the form `key=value`; unknown keys are
/// rejected by the parser.
public enum MTLLayoutOptionKeys {

    /// The indentation unit of the generated text (``MTLLayoutConfiguration/sourceIndent``).
    public static let indent = "indent"

    /// The indentation unit to write (``MTLLayoutConfiguration/targetIndent``).
    public static let targetIndent = "targetIndent"

    /// The opener placement, `ownLine` or `sameLine`.
    public static let opener = "opener"

    /// The opener token, a single character (default `{`).
    public static let openerToken = "openerToken"

    /// Space-separated line comment markers.
    public static let lineComments = MTLMergeOptionKeys.lineComments

    /// The block comment delimiters, separated by a space.
    public static let blockComment = MTLMergeOptionKeys.blockComment

    /// The characters that delimit string and character literals.
    public static let quotes = MTLMergeOptionKeys.quotes

    /// The characters that end a statement (a block never follows them on its own line).
    public static let terminators = MTLMergeOptionKeys.terminators

    /// Space-separated glob patterns restricting the declaration to matching files.
    public static let files = MTLMergeOptionKeys.files

    /// All recognised keys.
    public static let all: Set<String> = [
        indent, targetIndent, opener, openerToken, lineComments, blockComment, quotes, terminators,
        files,
    ]
}
