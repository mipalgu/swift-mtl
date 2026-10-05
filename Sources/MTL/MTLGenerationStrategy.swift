//
//  MTLGenerationStrategy.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - MTL Generation Strategy

/// Protocol for MTL text generation output strategies.
///
/// Generation strategies abstract the destination and lifecycle of generated text,
/// enabling MTL templates to generate output to files, memory, or other targets
/// without changing the template execution logic.
///
/// ## Overview
///
/// MTL supports different generation strategies:
/// - **File system**: Write directly to files on disk
/// - **In-memory**: Accumulate text in memory for testing or programmatic access
/// - **Custom**: Implement custom strategies for databases, network, etc.
///
/// ## Strategy Lifecycle
///
/// Each file block in an MTL template follows this lifecycle:
/// 1. **Create writer**: `createWriter(url:mode:charset:indentation:)` is called
/// 2. **Template writes**: Template statements write to the returned writer
/// 3. **Finalize**: `finalizeWriter(_:)` is called to commit/save the output
///
/// ## Example Usage
///
/// ```swift
/// // File system strategy
/// let fileStrategy = MTLFileSystemStrategy(basePath: "/output")
/// let writer1 = try await fileStrategy.createWriter(
///     url: "models/Person.swift",
///     mode: .overwrite,
///     charset: "UTF-8",
///     indentation: MTLIndentation()
/// )
/// await writer1.writeLine("class Person {}")
/// try await fileStrategy.finalizeWriter(writer1)
/// // File written to /output/models/Person.swift
///
/// // In-memory strategy (for testing)
/// let memoryStrategy = MTLInMemoryStrategy()
/// let writer2 = try await memoryStrategy.createWriter(
///     url: "test.txt",
///     mode: .create,
///     charset: "UTF-8",
///     indentation: MTLIndentation()
/// )
/// await writer2.writeLine("Test output")
/// try await memoryStrategy.finalizeWriter(writer2)
/// let files = await memoryStrategy.getGeneratedFiles()
/// // files["test.txt"] == "Test output\n"
/// ```
///
/// - Note: Strategies are actors to ensure thread-safe concurrent file generation.
public protocol MTLGenerationStrategy: Sendable {

    /// Creates a new writer for the specified target.
    ///
    /// This method is called when a file block begins execution in an MTL template.
    /// The strategy should create and return a writer configured for the target URL.
    ///
    /// - Parameters:
    ///   - url: The target file path or identifier
    ///   - mode: The file opening mode (overwrite, append, create)
    ///   - charset: The character encoding (typically "UTF-8")
    ///   - indentation: The initial indentation for this writer
    ///
    /// - Returns: A new MTLWriter instance for the target
    ///
    /// - Throws: `MTLExecutionError.fileError` if the writer cannot be created
    @MainActor
    func createWriter(
        url: String,
        mode: MTLOpenMode,
        charset: String,
        indentation: MTLIndentation
    ) async throws -> MTLWriter

    /// Finalizes and commits the writer's content to its target.
    ///
    /// This method is called when a file block completes execution. The strategy
    /// should perform any necessary finalization (writing to disk, closing handles,
    /// etc.) and commit the writer's accumulated content.
    ///
    /// - Parameter writer: The writer to finalize
    ///
    /// - Throws: `MTLExecutionError.fileError` if finalization fails
    @MainActor
    func finalizeWriter(_ writer: MTLWriter) async throws

    /// Returns the current content of a target that already exists.
    ///
    /// The generator uses the content to preserve protected areas before it
    /// overwrites the target. The default implementation reports that no
    /// target exists.
    ///
    /// - Parameter url: The target file path or identifier
    ///
    /// - Returns: The existing content, or `nil` if the target does not exist
    @MainActor
    func existingContent(url: String) async -> String?

    /// Tells whether a file already exists at the given URL.
    ///
    /// Templates reach this through the `fileExists` service, and `create` mode
    /// blocks use it to decide whether to skip their body. The default
    /// implementation reports whether ``existingContent(url:)`` returns text.
    ///
    /// - Parameter url: The file URL, relative to the generation base path unless absolute.
    /// - Returns: `true` if a file exists at the URL.
    @MainActor
    func fileExists(url: String) async -> Bool

    /// The generator options this strategy applies.
    ///
    /// Templates read the force overwrite flag through the `forceOverwrite`
    /// service. The default implementation returns the default options.
    var generatorOptions: MTLGeneratorOptions { get }

    /// Receives the text a generation run wrote outside any file block.
    ///
    /// The generator calls this once, when the run finishes. The default implementation stores
    /// the text as if it were a file named ``MTLStandardOutput/fileName``, which is what
    /// in-memory strategies expect. Strategies that write to disk override it to avoid creating
    /// such a file.
    ///
    /// - Parameter text: The complete text written outside any file block
    ///
    /// - Throws: `MTLExecutionError.fileError` if the text cannot be stored
    @MainActor
    func writeStandardOutput(_ text: String) async throws
}

extension MTLGenerationStrategy {

    @MainActor
    public func writeStandardOutput(_ text: String) async throws {
        let writer = try await createWriter(
            url: MTLStandardOutput.fileName,
            mode: .overwrite,
            charset: "UTF-8",
            indentation: MTLIndentation()
        )
        await writer.write(text, indent: false)
        try await finalizeWriter(writer)
    }

    @MainActor
    public func existingContent(url: String) async -> String? {
        return nil
    }

    @MainActor
    public func fileExists(url: String) async -> Bool {
        return await existingContent(url: url) != nil
    }

    public var generatorOptions: MTLGeneratorOptions {
        MTLGeneratorOptions()
    }
}

// MARK: - MTL File System Strategy

/// File system-based generation strategy that writes to disk.
///
/// This strategy writes generated text directly to the file system, creating
/// directories as needed and handling file modes (overwrite, append, create).
///
/// ## Overview
///
/// Features:
/// - **Automatic directory creation**: Creates parent directories if they don't exist
/// - **File mode handling**: Supports overwrite, append, and create modes
/// - **Base path resolution**: Resolves relative paths against a configurable base path
/// - **Character encoding**: Supports configurable character encodings
///
/// ## File Modes
///
/// - `.overwrite`: Replace existing file or create new
/// - `.append`: Append to existing file or create new
/// - `.create`: Create new file; if the file exists it is left untouched and nothing is written
///
/// ## Example Usage
///
/// ```swift
/// let strategy = MTLFileSystemStrategy(basePath: "/output")
///
/// let writer = try await strategy.createWriter(
///     url: "models/Person.swift",
///     mode: .overwrite,
///     charset: "UTF-8",
///     indentation: MTLIndentation()
/// )
///
/// await writer.writeLine("// Generated file")
/// await writer.writeLine("class Person {}")
///
/// try await strategy.finalizeWriter(writer)
/// // File written to /output/models/Person.swift
/// ```
///
/// - Note: This actor ensures thread-safe concurrent file operations.
public actor MTLFileSystemStrategy: MTLGenerationStrategy {

    // MARK: - Properties

    /// The base directory for resolving relative file paths.
    ///
    /// All relative URLs are resolved against this base path. Absolute URLs
    /// are used as-is.
    private let basePath: String

    /// Mapping from writers to their target file URLs.
    ///
    /// This tracks which file each writer is associated with so we can
    /// write to the correct location during finalization.
    private var writerFiles: [ObjectIdentifier: String] = [:]

    /// Mapping from writers to their file modes.
    ///
    /// This tracks the opening mode for each writer to determine how to
    /// handle existing files during finalization.
    private var writerModes: [ObjectIdentifier: MTLOpenMode] = [:]

    /// The character set of each open writer.
    private var writerCharsets: [ObjectIdentifier: MTLCharset] = [:]

    /// The options that control merging, redirection and line delimiters.
    private let options: MTLGeneratorOptions

    /// The post-processors applied to each file before it is written.
    private var postProcessors: [any MTLFilePostProcessor]

    /// Where the text written outside any file block goes.
    private let standardOutputSink: MTLStandardOutputSink

    /// The text written outside any file block during the latest run.
    ///
    /// Only populated when the strategy was created with ``MTLStandardOutputSink/capture``;
    /// otherwise this is `nil`.
    public private(set) var standardOutput: String?

    // MARK: - Initialisation

    /// Creates a new file system strategy with the specified base path.
    ///
    /// - Parameters:
    ///   - basePath: The base directory for file output (default: current directory)
    ///   - options: The options that control how existing files are treated (default: merge when
    ///     the module declares a merge, otherwise overwrite)
    ///   - postProcessors: Post-processors applied to each file, in order (default: none)
    ///   - standardOutput: What to do with text written outside any file block (default:
    ///     discard it; such text is never written to a file)
    public init(
        basePath: String = FileManager.default.currentDirectoryPath,
        options: MTLGeneratorOptions = MTLGeneratorOptions(),
        postProcessors: [any MTLFilePostProcessor] = [],
        standardOutput: MTLStandardOutputSink = .discard
    ) {
        self.basePath = basePath
        self.options = options
        self.postProcessors = postProcessors
        self.standardOutputSink = standardOutput
    }

    @MainActor
    public func writeStandardOutput(_ text: String) async throws {
        switch standardOutputSink {
        case .discard:
            break
        case .capture:
            await storeStandardOutput(text)
        case .handler(let handle):
            await handle(text)
        }
    }

    private func storeStandardOutput(_ text: String) {
        standardOutput = text
    }

    /// Attaches a post-processor that runs after all previously attached ones.
    ///
    /// - Parameter processor: The post-processor to append
    public func addPostProcessor(_ processor: any MTLFilePostProcessor) {
        postProcessors.append(processor)
    }

    // MARK: - MTLGenerationStrategy

    @MainActor
    public func createWriter(
        url: String,
        mode: MTLOpenMode,
        charset: String,
        indentation: MTLIndentation
    ) async throws -> MTLWriter {
        let resolvedCharset = try MTLCharset.resolve(charset)
        let writer = MTLWriter(indentation: indentation)
        let writerId = ObjectIdentifier(writer)

        // Resolve the target path
        let targetPath = resolveFilePath(url)

        // For append mode, load existing content
        if mode == .append, let existingContent = resolvedCharset.read(atPath: targetPath) {
            await writer.write(existingContent, indent: false)
        }

        // Store writer metadata
        await storeWriterMetadata(
            writerId: writerId, path: targetPath, mode: mode, charset: resolvedCharset)

        return writer
    }

    @MainActor
    public func finalizeWriter(_ writer: MTLWriter) async throws {
        let writerId = ObjectIdentifier(writer)

        guard let targetPath = await getWriterPath(writerId) else {
            throw MTLExecutionError.fileError("Writer not registered")
        }

        // Get the accumulated content
        let content = await writer.getContent()
        let mode = await getWriterMode(writerId)
        let charset = await getWriterCharset(writerId)

        // A create-mode file never replaces an existing file
        if mode == .create && FileManager.default.fileExists(atPath: targetPath) {
            await removeWriterMetadata(writerId: writerId)
            return
        }

        // Merge, redirect and post-process
        let existing: String? =
            mode == .overwrite ? charset.read(atPath: targetPath) : nil
        let outcome = try await MTLOutputPreparation.prepare(
            path: targetPath,
            content: content,
            existing: existing,
            mergeConfiguration: await writer.mergeConfiguration,
            regions: await writer.emittedRegions,
            layout: await writer.layoutRequest,
            options: options,
            postProcessors: postProcessors
        )

        if let outcome {
            // Create parent directory if needed
            let parentDir = (outcome.path as NSString).deletingLastPathComponent
            if !parentDir.isEmpty && !FileManager.default.fileExists(atPath: parentDir) {
                try FileManager.default.createDirectory(
                    atPath: parentDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            }

            // Write to file
            let data: Data
            do {
                data = try charset.encode(outcome.content, path: outcome.path)
            } catch {
                await removeWriterMetadata(writerId: writerId)
                throw error
            }
            do {
                try data.write(to: URL(fileURLWithPath: outcome.path), options: .atomic)
            } catch {
                throw MTLExecutionError.fileError("Failed to write file \(outcome.path): \(error)")
            }
        }

        // Clean up writer metadata
        await removeWriterMetadata(writerId: writerId)
    }

    @MainActor
    public func existingContent(url: String) async -> String? {
        let path = resolveFilePath(url)
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return MTLCharset.readDetecting(atPath: path)
    }

    @MainActor
    public func fileExists(url: String) async -> Bool {
        return FileManager.default.fileExists(atPath: resolveFilePath(url))
    }

    nonisolated public var generatorOptions: MTLGeneratorOptions {
        options
    }

    // MARK: - Private Helpers

    /// Retrieves the mode for a writer.
    private func getWriterMode(_ writerId: ObjectIdentifier) -> MTLOpenMode? {
        return writerModes[writerId]
    }

    private func getWriterCharset(_ writerId: ObjectIdentifier) -> MTLCharset {
        return writerCharsets[writerId] ?? .utf8
    }

    /// Resolves a file URL against the base path.
    nonisolated private func resolveFilePath(_ url: String) -> String {
        if url.hasPrefix("/") || url.hasPrefix("~") {
            // Absolute path
            return (url as NSString).expandingTildeInPath
        } else {
            // Relative path - resolve against base
            return (basePath as NSString).appendingPathComponent(url)
        }
    }

    /// Stores metadata for a writer.
    private func storeWriterMetadata(
        writerId: ObjectIdentifier, path: String, mode: MTLOpenMode, charset: MTLCharset
    ) {
        writerFiles[writerId] = path
        writerModes[writerId] = mode
        writerCharsets[writerId] = charset
    }

    /// Retrieves the file path for a writer.
    private func getWriterPath(_ writerId: ObjectIdentifier) -> String? {
        return writerFiles[writerId]
    }

    /// Removes metadata for a writer.
    private func removeWriterMetadata(writerId: ObjectIdentifier) {
        writerFiles.removeValue(forKey: writerId)
        writerModes.removeValue(forKey: writerId)
        writerCharsets.removeValue(forKey: writerId)
    }
}

// MARK: - MTL In-Memory Strategy

/// In-memory generation strategy for testing and programmatic access.
///
/// This strategy accumulates generated text in memory rather than writing to
/// files, making it ideal for unit tests, previews, and scenarios where the
/// generated text needs to be processed programmatically.
///
/// ## Overview
///
/// Features:
/// - **No file system access**: All output stored in memory
/// - **File simulation**: Maintains separate buffers per "file"
/// - **Mode handling**: Simulates append mode by concatenating to existing buffer
/// - **Retrieval**: Generated files can be accessed via `getGeneratedFiles()`
///
/// ## Example Usage
///
/// ```swift
/// let strategy = MTLInMemoryStrategy()
///
/// // Generate multiple "files"
/// let writer1 = try await strategy.createWriter(
///     url: "file1.txt",
///     mode: .create,
///     charset: "UTF-8",
///     indentation: MTLIndentation()
/// )
/// await writer1.writeLine("Content 1")
/// try await strategy.finalizeWriter(writer1)
///
/// let writer2 = try await strategy.createWriter(
///     url: "file2.txt",
///     mode: .create,
///     charset: "UTF-8",
///     indentation: MTLIndentation()
/// )
/// await writer2.writeLine("Content 2")
/// try await strategy.finalizeWriter(writer2)
///
/// // Retrieve all generated content
/// let files = await strategy.getGeneratedFiles()
/// print(files["file1.txt"])  // "Content 1\n"
/// print(files["file2.txt"])  // "Content 2\n"
/// ```
///
/// - Note: This actor ensures thread-safe concurrent access to the in-memory buffers.
public actor MTLInMemoryStrategy: MTLGenerationStrategy {

    // MARK: - Properties

    /// Storage for generated file contents, keyed by file path.
    private var files: [String: String] = [:]

    /// Mapping from writers to their target file paths.
    private var writerFiles: [ObjectIdentifier: String] = [:]

    /// Mapping from writers to their file modes.
    private var writerModes: [ObjectIdentifier: MTLOpenMode] = [:]

    /// The character set of each open writer.
    private var writerCharsets: [ObjectIdentifier: MTLCharset] = [:]

    /// The options that control merging, redirection and line delimiters.
    private let options: MTLGeneratorOptions

    /// The post-processors applied to each file before it is stored.
    private var postProcessors: [any MTLFilePostProcessor]

    // MARK: - Initialisation

    /// Creates a new in-memory generation strategy.
    ///
    /// - Parameters:
    ///   - options: The options that control how existing files are treated (default: merge when
    ///     the module declares a merge, otherwise overwrite)
    ///   - postProcessors: Post-processors applied to each file, in order (default: none)
    public init(
        options: MTLGeneratorOptions = MTLGeneratorOptions(),
        postProcessors: [any MTLFilePostProcessor] = []
    ) {
        self.options = options
        self.postProcessors = postProcessors
    }

    /// Attaches a post-processor that runs after all previously attached ones.
    ///
    /// - Parameter processor: The post-processor to append
    public func addPostProcessor(_ processor: any MTLFilePostProcessor) {
        postProcessors.append(processor)
    }

    /// Stores content as an existing file, as if it had been generated earlier.
    ///
    /// - Parameters:
    ///   - content: The content of the file
    ///   - path: The path or identifier of the file
    public func setFile(_ content: String, at path: String) {
        files[path] = content
    }

    // MARK: - MTLGenerationStrategy

    @MainActor
    public func createWriter(
        url: String,
        mode: MTLOpenMode,
        charset: String,
        indentation: MTLIndentation
    ) async throws -> MTLWriter {
        let resolvedCharset = try MTLCharset.resolve(charset)
        let writer = MTLWriter(indentation: indentation)
        let writerId = ObjectIdentifier(writer)

        // For append mode, load existing content
        if mode == .append, let existingContent = await getFile(url) {
            await writer.write(existingContent, indent: false)
        }

        // Store writer metadata
        await storeWriterMetadata(writerId: writerId, path: url, mode: mode, charset: resolvedCharset)

        return writer
    }

    @MainActor
    public func finalizeWriter(_ writer: MTLWriter) async throws {
        let writerId = ObjectIdentifier(writer)

        guard let targetPath = await getWriterPath(writerId) else {
            throw MTLExecutionError.fileError("Writer not registered")
        }

        // Get the accumulated content
        let content = await writer.getContent()
        let mode = await getWriterMode(writerId)
        let charset = await getWriterCharset(writerId)

        // A create-mode file never replaces an existing file
        if mode == .create, await fileExists(targetPath) {
            await removeWriterMetadata(writerId: writerId)
            return
        }

        // Merge, redirect and post-process
        let outcome = try await MTLOutputPreparation.prepare(
            path: targetPath,
            content: content,
            existing: mode == .overwrite ? await getFile(targetPath) : nil,
            mergeConfiguration: await writer.mergeConfiguration,
            regions: await writer.emittedRegions,
            layout: await writer.layoutRequest,
            options: options,
            postProcessors: postProcessors
        )

        // Store in memory, once the content is known to be representable
        if let outcome {
            do {
                _ = try charset.encode(outcome.content, path: outcome.path)
            } catch {
                await removeWriterMetadata(writerId: writerId)
                throw error
            }
            await storeFile(path: outcome.path, content: outcome.content)
        }

        // Clean up writer metadata
        await removeWriterMetadata(writerId: writerId)
    }

    // MARK: - Public API

    /// Returns all generated files and their contents.
    ///
    /// - Returns: A dictionary mapping file paths to their generated content
    public func getGeneratedFiles() -> [String: String] {
        return files
    }

    /// Clears all generated files from memory.
    public func clear() {
        files.removeAll()
    }

    // MARK: - Private Helpers

    /// Checks if a file exists in memory.
    private func fileExists(_ path: String) -> Bool {
        return files[path] != nil
    }

    /// Retrieves a file from memory.
    private func getFile(_ path: String) -> String? {
        return files[path]
    }

    /// Stores a file in memory.
    private func storeFile(path: String, content: String) {
        files[path] = content
    }

    /// Stores metadata for a writer.
    private func storeWriterMetadata(
        writerId: ObjectIdentifier, path: String, mode: MTLOpenMode, charset: MTLCharset
    ) {
        writerFiles[writerId] = path
        writerModes[writerId] = mode
        writerCharsets[writerId] = charset
    }

    /// Retrieves the mode for a writer.
    private func getWriterMode(_ writerId: ObjectIdentifier) -> MTLOpenMode? {
        return writerModes[writerId]
    }

    private func getWriterCharset(_ writerId: ObjectIdentifier) -> MTLCharset {
        return writerCharsets[writerId] ?? .utf8
    }

    @MainActor
    public func existingContent(url: String) async -> String? {
        return await getFile(url)
    }

    @MainActor
    public func fileExists(url: String) async -> Bool {
        return await fileExists(url)
    }

    nonisolated public var generatorOptions: MTLGeneratorOptions {
        options
    }

    /// Retrieves the file path for a writer.
    private func getWriterPath(_ writerId: ObjectIdentifier) -> String? {
        return writerFiles[writerId]
    }

    /// Removes metadata for a writer.
    private func removeWriterMetadata(writerId: ObjectIdentifier) {
        writerFiles.removeValue(forKey: writerId)
        writerModes.removeValue(forKey: writerId)
        writerCharsets.removeValue(forKey: writerId)
    }
}
