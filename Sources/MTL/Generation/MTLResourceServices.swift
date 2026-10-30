//
// MTLResourceServices.swift
// MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation

// MARK: - Service Names

/// The names of the services that give templates access to text resources.
public enum MTLResourceServiceName {
    /// The service `resourceText('path')`, which returns the text of a resource file.
    public static let resourceText = "resourceText"

    /// The service `resourceExists('path')`, which tells whether a resource file exists.
    public static let resourceExists = "resourceExists"

    /// The separators accepted between the components of a resource path.
    public static let pathSeparators: Set<Character> = ["/", "\\"]

    /// The path component that names the parent directory, which resource paths must not use.
    public static let parentDirectory = ".."

    /// The path component that names the current directory, which resource paths may use.
    public static let currentDirectory = "."

    /// The character that ends a drive name on Windows, which resource paths must not contain.
    public static let driveSeparator: Character = ":"
}

// MARK: - Errors

/// The problems found when reading text resources from templates.
///
/// Each case carries the resource path as the template gave it.
public enum MTLResourceServicesError: Error, LocalizedError, Equatable, Sendable {
    /// The path is empty, absolute, names a drive or leads out of the resource roots.
    case invalidPath(String)

    /// No root contains a regular file at the path.
    case notFound(String)

    /// The file at the path is not valid UTF-8 text.
    case notText(String)

    /// A description of the problem that names the resource path.
    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            return "Invalid resource path '\(path)': expected a relative path that stays below the resource roots"
        case .notFound(let path):
            return "Resource '\(path)' not found in any resource root"
        case .notText(let path):
            return "Resource '\(path)' is not UTF-8 text"
        }
    }
}

// MARK: - Resource Services

/// Gives templates access to text files shipped alongside them.
///
/// Text that a generator emits unchanged, such as support headers or licence files, can be kept
/// as plain files next to the templates instead of being written into a template. The services
/// look a relative path up in each root directory in turn and use the first regular file found.
///
/// Once the instance is registered with ``MTLGenerator/register(_:)``, two standalone services
/// are available:
/// - `resourceText('path')` returns the content of the file as text, exactly as stored, and fails
///   if no root contains the file or the file is not UTF-8 text.
/// - `resourceExists('path')` returns `true` if a root contains a regular file at the path.
///
/// Paths are relative and use `/` (or `\`) between their components. A path that is empty,
/// absolute, names a drive, or contains a `..` component is rejected, so templates cannot read
/// files outside the roots through these services.
///
/// ## Example
///
/// ```swift
/// let module = try await MTLParser().parse(templateURL)
/// let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy(), options: .standard)
/// generator.register(MTLResourceServices(module: module))
/// ```
///
/// With the template directory as a root, `[file ('a.h', false, 'UTF-8')][resourceText('support/a.h')/][/file]`
/// writes `support/a.h` from beside the template verbatim.
public struct MTLResourceServices: AQLServiceProvider {
    /// The directories that resource paths are resolved against, in search order.
    public let roots: [URL]

    /// Creates the services for a list of root directories.
    ///
    /// - Parameter roots: The directories to search, in order.
    public init(roots: [URL]) {
        self.roots = roots
    }

    /// Creates the services with the directory of a module as the first root.
    ///
    /// The directory that the module was parsed from is searched first, followed by the given
    /// roots. A module parsed from text without a file location contributes no root.
    ///
    /// - Parameters:
    ///   - module: The module whose directory is searched first.
    ///   - roots: Further directories to search, in order (default: none).
    public init(module: MTLModule, roots: [URL] = []) {
        let moduleRoot = module.location.map { [$0.deletingLastPathComponent()] } ?? []
        self.init(roots: moduleRoot + roots)
    }

    /// Finds the file that a resource path refers to.
    ///
    /// - Parameter path: The relative resource path.
    /// - Returns: The URL of the first regular file found below a root, or `nil` if there is none.
    /// - Throws: ``MTLResourceServicesError/invalidPath(_:)`` if the path is empty, absolute,
    ///   names a drive or contains a `..` component.
    public func url(of path: String) throws -> URL? {
        let components = try Self.components(of: path)
        let fileManager = FileManager.default
        for root in roots {
            let candidate = components.reduce(root) { $0.appendingPathComponent($1) }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    /// Tells whether a resource file exists.
    ///
    /// - Parameter path: The relative resource path.
    /// - Returns: `true` if a root contains a regular file at the path.
    /// - Throws: ``MTLResourceServicesError/invalidPath(_:)`` if the path is not a valid resource path.
    public func exists(_ path: String) throws -> Bool {
        try url(of: path) != nil
    }

    /// Reads the text of a resource file.
    ///
    /// - Parameter path: The relative resource path.
    /// - Returns: The content of the file, exactly as stored.
    /// - Throws: ``MTLResourceServicesError/invalidPath(_:)`` if the path is not a valid resource
    ///   path, ``MTLResourceServicesError/notFound(_:)`` if no root contains the file, and
    ///   ``MTLResourceServicesError/notText(_:)`` if the file is not UTF-8 text.
    public func text(at path: String) throws -> String {
        guard let url = try url(of: path) else { throw MTLResourceServicesError.notFound(path) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw MTLResourceServicesError.notFound(path)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw MTLResourceServicesError.notText(path)
        }
        return text
    }

    /// The services offered to templates: `resourceText` and `resourceExists`.
    public var services: [AQLService] {
        let services = self
        return [
            AQLService(MTLResourceServiceName.resourceText, receiver: .standalone, arity: 1) { call in
                try services.text(at: try call.string(0))
            },
            AQLService(MTLResourceServiceName.resourceExists, receiver: .standalone, arity: 1) { call in
                try services.exists(try call.string(0))
            },
        ]
    }

    /// Splits a resource path into the components to append to a root.
    ///
    /// - Parameter path: The relative resource path.
    /// - Returns: The components, without empty and current directory components.
    /// - Throws: ``MTLResourceServicesError/invalidPath(_:)`` if the path is empty, absolute,
    ///   names a drive or contains a parent directory component.
    private static func components(of path: String) throws -> [String] {
        let separators = MTLResourceServiceName.pathSeparators
        guard let first = path.first, !separators.contains(first),
            !path.contains(MTLResourceServiceName.driveSeparator)
        else {
            throw MTLResourceServicesError.invalidPath(path)
        }
        let components = path.split(whereSeparator: { separators.contains($0) }).map(String.init)
        guard !components.contains(MTLResourceServiceName.parentDirectory) else {
            throw MTLResourceServicesError.invalidPath(path)
        }
        let kept = components.filter { $0 != MTLResourceServiceName.currentDirectory }
        guard !kept.isEmpty else { throw MTLResourceServicesError.invalidPath(path) }
        return kept
    }
}
