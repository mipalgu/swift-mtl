//
//  MTLGeneratorOptions.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - Generator Options

/// Options that control how generated files are written.
///
/// Options are supplied to a generation strategy. They decide what happens
/// when a target file already exists and how the generated text is finished
/// before it is written.
///
/// ## Existing Files
///
/// When a `[file]` block overwrites a file that already exists:
/// - with ``forceOverwrite`` the generated text replaces the file;
/// - otherwise, with a ``redirectionPattern``, the generated text is written
///   to a file alongside the original, which is left untouched;
/// - otherwise, if the module declares `[merge]`, the generated text is
///   merged into the existing file;
/// - otherwise the generated text replaces the file.
///
/// ## Example
///
/// ```swift
/// let options = MTLGeneratorOptions(redirectionPattern: ".{0}.new")
/// let strategy = MTLFileSystemStrategy(basePath: "/output", options: options)
/// ```
public struct MTLGeneratorOptions: Sendable, Equatable {

    /// The placeholder for the file name in a redirection pattern.
    public static let redirectionPlaceholder = "{0}"

    /// Whether generated text replaces existing files without merging or redirection.
    public var forceOverwrite: Bool

    /// A pattern for the name of a file written alongside an existing file.
    ///
    /// The placeholder `{0}` stands for the name of the target file,
    /// including its extension. For example, `.{0}.new` redirects
    /// `src/Library.java` to `src/.Library.java.new`. The pattern applies only
    /// when the target exists, and no file is written if the generated text
    /// equals the existing content.
    public var redirectionPattern: String?

    /// The layout conversion applied to generated files.
    ///
    /// When set, it overrides the module's `[layout]` declaration: the module
    /// declaration is ignored, and the file patterns of this configuration decide
    /// which files are converted. A `[file]` block can still opt out with
    /// `'layout=false'`. The conversion runs on freshly generated text before it
    /// is merged with an existing file, because the existing file is already in
    /// the target layout.
    public var layout: MTLLayoutConfiguration?

    /// The line delimiter written to files (default: `"\n"`).
    ///
    /// Generated text uses `\n` internally; the delimiter is substituted
    /// after merging and post-processing.
    public var lineDelimiter: String

    /// Directories searched for template modules.
    ///
    /// Reserved for module resolution by import support; the generation
    /// strategies do not use it.
    public var templateSearchPaths: [String]

    /// Creates a set of generator options.
    ///
    /// - Parameters:
    ///   - forceOverwrite: Whether to replace existing files (default: `false`).
    ///   - redirectionPattern: A pattern for files written alongside existing files (default: `nil`).
    ///   - lineDelimiter: The line delimiter to write (default: `"\n"`).
    ///   - templateSearchPaths: Directories searched for template modules (default: empty).
    ///   - layout: A layout conversion that overrides the module's declaration (default: `nil`).
    public init(
        forceOverwrite: Bool = false,
        redirectionPattern: String? = nil,
        lineDelimiter: String = "\n",
        templateSearchPaths: [String] = [],
        layout: MTLLayoutConfiguration? = nil
    ) {
        self.layout = layout
        self.forceOverwrite = forceOverwrite
        self.redirectionPattern = redirectionPattern
        self.lineDelimiter = lineDelimiter
        self.templateSearchPaths = templateSearchPaths
    }

    /// Computes the path of the file written alongside an existing file.
    ///
    /// - Parameter path: The path of the target file.
    /// - Returns: The redirected path, or `nil` if no redirection pattern is set.
    public func redirectedPath(for path: String) -> String? {
        guard let pattern = redirectionPattern else { return nil }
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let redirected = pattern.replacingOccurrences(
            of: Self.redirectionPlaceholder, with: name)
        let directory = (path as NSString).deletingLastPathComponent
        return directory.isEmpty ? redirected : (directory as NSString).appendingPathComponent(redirected)
    }
}

// MARK: - File Post Processor

/// A step that transforms the content of a generated file before it is written.
///
/// Post-processors run in the order in which they were attached to the
/// generation strategy, after any merge with an existing file and before the
/// line delimiter is applied. Typical uses are code formatting and header
/// insertion.
///
/// ## Example
///
/// ```swift
/// struct TrailingWhitespaceTrimmer: MTLFilePostProcessor {
///     func process(_ content: String, path: String) async throws -> String {
///         content.split(separator: "\n", omittingEmptySubsequences: false)
///             .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
///             .joined(separator: "\n")
///     }
/// }
/// ```
public protocol MTLFilePostProcessor: Sendable {

    /// Transforms the content of a file.
    ///
    /// - Parameters:
    ///   - content: The content about to be written, with `\n` line endings.
    ///   - path: The path or identifier of the target file.
    /// - Returns: The content to write.
    /// - Throws: Any error, which aborts the generation of the file.
    func process(_ content: String, path: String) async throws -> String
}

// MARK: - Layout Request

/// How the layout conversion applies to one generated file.
struct MTLLayoutRequest: Sendable, Equatable {

    /// The layout declared by the module, if any.
    var declaration: MTLLayoutConfiguration?

    /// Whether the file has not opted out with `'layout=false'`.
    var enabled = true

    /// The URL of the file as written in the `file` block, matched against file patterns.
    var fileURL = ""

    /// The lines of the generated text that hold preserved protected areas.
    var verbatimLines: [Range<Int>] = []
}

// MARK: - Output Preparation

/// The steps that turn a finished writer into the text and path to store.
enum MTLOutputPreparation {

    /// The outcome of preparing a file for output.
    struct Outcome: Equatable {

        /// The path to write to, possibly redirected.
        var path: String

        /// The content to write.
        var content: String
    }

    /// Merges, redirects and post-processes the content of a finished writer.
    ///
    /// - Parameters:
    ///   - path: The path of the target file.
    ///   - content: The generated content.
    ///   - existing: The current content of the target file, if it exists and is being overwritten.
    ///   - mergeConfiguration: The module's merge configuration, if any.
    ///   - regions: The emitted regions of the generated content.
    ///   - layout: How the layout conversion applies to the file.
    ///   - options: The generator options.
    ///   - postProcessors: The post-processors to apply, in order.
    /// - Returns: The path and content to write, or `nil` if nothing needs to be written.
    /// - Throws: ``TaggedBlockError`` or any error thrown by a post-processor.
    static func prepare(
        path: String,
        content: String,
        existing: String?,
        mergeConfiguration: MTLMergeConfiguration?,
        regions: [MTLEmittedRegion],
        layout: MTLLayoutRequest = MTLLayoutRequest(),
        options: MTLGeneratorOptions,
        postProcessors: [any MTLFilePostProcessor]
    ) async throws -> Outcome? {
        var target = path
        var content = content
        var regions = regions
        if layout.enabled, let configuration = options.layout ?? layout.declaration,
            !configuration.isIdentity,
            configuration.applies(toFile: layout.fileURL.isEmpty ? path : layout.fileURL)
        {
            let converted = MTLLayoutConverter(configuration: configuration)
                .convert(content, verbatimLines: layout.verbatimLines)
            content = converted.text
            regions = regions.map { region in
                let first = converted.newLine(forOld: region.firstLine)
                let end = converted.newLine(forOld: region.firstLine + region.lineCount)
                return MTLEmittedRegion(name: region.name, firstLine: first, lineCount: max(0, end - first))
            }
        }
        var result = content
        if let existing, !options.forceOverwrite {
            if let redirected = options.redirectedPath(for: path) {
                target = redirected
                if TaggedBlockMerger.normalisedLineEndings(existing)
                    == TaggedBlockMerger.normalisedLineEndings(content)
                {
                    return nil
                }
            } else if let mergeConfiguration {
                result = try TaggedBlockMerger(configuration: mergeConfiguration)
                    .merge(
                        existing: existing,
                        generated: TaggedBlockMerger.normalisedLineEndings(content),
                        regions: regions)
            }
        }
        for processor in postProcessors {
            result = try await processor.process(result, path: target)
        }
        if options.lineDelimiter != "\n" {
            result = TaggedBlockMerger.normalisedLineEndings(result)
            result = result.replacingOccurrences(of: "\n", with: options.lineDelimiter)
        }
        return Outcome(path: target, content: result)
    }
}
