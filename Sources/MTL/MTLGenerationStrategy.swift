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
/// - `.create`: Create new file, fail if exists
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

    // MARK: - Initialisation

    /// Creates a new file system strategy with the specified base path.
    ///
    /// - Parameter basePath: The base directory for file output (default: current directory)
    public init(basePath: String = FileManager.default.currentDirectoryPath) {
        self.basePath = basePath
    }

    // MARK: - MTLGenerationStrategy

    @MainActor
    public func createWriter(
        url: String,
        mode: MTLOpenMode,
        charset: String,
        indentation: MTLIndentation
    ) async throws -> MTLWriter {
        let writer = MTLWriter(indentation: indentation)
        let writerId = ObjectIdentifier(writer)

        // Resolve the target path
        let targetPath = resolveFilePath(url)

        // For append mode, load existing content
        if mode == .append && FileManager.default.fileExists(atPath: targetPath) {
            if let existingContent = try? String(contentsOfFile: targetPath, encoding: .utf8) {
                await writer.write(existingContent, indent: false)
            }
        }

        // For create mode, check that file doesn't exist
        if mode == .create && FileManager.default.fileExists(atPath: targetPath) {
            throw MTLExecutionError.fileError("File already exists: \(targetPath)")
        }

        // Store writer metadata
        await storeWriterMetadata(writerId: writerId, path: targetPath, mode: mode)

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

        // Create parent directory if needed
        let parentDir = (targetPath as NSString).deletingLastPathComponent
        if !parentDir.isEmpty && !FileManager.default.fileExists(atPath: parentDir) {
            try FileManager.default.createDirectory(
                atPath: parentDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Write to file
        do {
            try content.write(toFile: targetPath, atomically: true, encoding: .utf8)
        } catch {
            throw MTLExecutionError.fileError("Failed to write file \(targetPath): \(error)")
        }

        // Clean up writer metadata
        await removeWriterMetadata(writerId: writerId)
    }

    // MARK: - Private Helpers

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
    private func storeWriterMetadata(writerId: ObjectIdentifier, path: String, mode: MTLOpenMode) {
        writerFiles[writerId] = path
        writerModes[writerId] = mode
    }

    /// Retrieves the file path for a writer.
    private func getWriterPath(_ writerId: ObjectIdentifier) -> String? {
        return writerFiles[writerId]
    }

    /// Removes metadata for a writer.
    private func removeWriterMetadata(writerId: ObjectIdentifier) {
        writerFiles.removeValue(forKey: writerId)
        writerModes.removeValue(forKey: writerId)
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

    // MARK: - Initialisation

    /// Creates a new in-memory generation strategy.
    public init() {}

    // MARK: - MTLGenerationStrategy

    @MainActor
    public func createWriter(
        url: String,
        mode: MTLOpenMode,
        charset: String,
        indentation: MTLIndentation
    ) async throws -> MTLWriter {
        let writer = MTLWriter(indentation: indentation)
        let writerId = ObjectIdentifier(writer)

        // For append mode, load existing content
        if mode == .append, let existingContent = await getFile(url) {
            await writer.write(existingContent, indent: false)
        }

        // For create mode, check that file doesn't exist
        let exists = await fileExists(url)
        if mode == .create && exists {
            throw MTLExecutionError.fileError("File already exists: \(url)")
        }

        // Store writer metadata
        await storeWriterMetadata(writerId: writerId, path: url)

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

        // Store in memory
        await storeFile(path: targetPath, content: content)

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
    private func storeWriterMetadata(writerId: ObjectIdentifier, path: String) {
        writerFiles[writerId] = path
    }

    /// Retrieves the file path for a writer.
    private func getWriterPath(_ writerId: ObjectIdentifier) -> String? {
        return writerFiles[writerId]
    }

    /// Removes metadata for a writer.
    private func removeWriterMetadata(writerId: ObjectIdentifier) {
        writerFiles.removeValue(forKey: writerId)
    }
}
