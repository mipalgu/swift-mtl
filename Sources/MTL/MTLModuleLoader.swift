//
//  MTLModuleLoader.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - Module Resolution Errors

/// Errors raised while locating and loading imported and extended modules.
public enum MTLModuleResolutionError: Error, LocalizedError, Equatable {

    /// No file exists for the named module.
    ///
    /// - `module`: The qualified module name as written in the import or extends declaration.
    /// - `searched`: The paths that were tried, in order.
    /// - `requiredBy`: The module whose declaration asked for it, if known.
    case notFound(module: String, searched: [String], requiredBy: String?)

    /// The modules import or extend each other in a cycle.
    ///
    /// The associated value lists the module files along the cycle, ending with the repeated one.
    case cycle([String])

    public var errorDescription: String? {
        switch self {
        case .notFound(let module, let searched, let requiredBy):
            let origin = requiredBy.map { " (required by module '\($0)')" } ?? ""
            let places = searched.isEmpty ? "no search location is configured" : "searched: " + searched.joined(separator: ", ")
            return "Module '\(module)' not found\(origin); \(places)"
        case .cycle(let path):
            return "Cyclic module dependency: " + path.joined(separator: " -> ")
        }
    }
}

// MARK: - Module Resolver

/// Maps qualified module names to module files.
///
/// A qualified name such as `common::naming::java` names the file
/// `common/naming/java.mtl`. Resolution tries the directory of the importing
/// file first, then each configured search path in order.
public struct MTLModuleResolver: Sendable, Equatable {

    /// The directories that qualified names are resolved against after the importing file's directory.
    public var searchPaths: [URL]

    /// Creates a resolver.
    ///
    /// - Parameter searchPaths: The directories to search after the importing file's directory.
    public init(searchPaths: [URL] = []) {
        self.searchPaths = searchPaths
    }

    /// The relative file path that a qualified module name denotes.
    ///
    /// - Parameter qualifiedName: The module name, with `::` between segments.
    /// - Returns: The path with directory separators and the module file extension.
    public func relativePath(for qualifiedName: String) -> String {
        qualifiedName
            .components(separatedBy: MTLSyntax.qualifiedNameSeparator)
            .joined(separator: "/") + "." + MTLSyntax.moduleFileExtension
    }

    /// Lists the files that may hold a module, in the order they are tried.
    ///
    /// - Parameters:
    ///   - qualifiedName: The module name, with `::` between segments.
    ///   - importingFile: The file whose declaration names the module, if known.
    /// - Returns: The candidate file URLs.
    public func candidates(for qualifiedName: String, relativeTo importingFile: URL?) -> [URL] {
        let relative = relativePath(for: qualifiedName)
        var directories: [URL] = []
        if let importingFile = importingFile {
            directories.append(importingFile.deletingLastPathComponent())
        }
        directories.append(contentsOf: searchPaths)
        return directories.map { $0.appendingPathComponent(relative) }
    }

    /// Finds the file for a module name.
    ///
    /// - Parameters:
    ///   - qualifiedName: The module name, with `::` between segments.
    ///   - importingFile: The file whose declaration names the module, if known.
    ///   - requiredBy: The name of the requiring module, for error messages.
    /// - Returns: The URL of the first existing candidate.
    /// - Throws: `MTLModuleResolutionError.notFound` if no candidate exists.
    public func locate(
        _ qualifiedName: String,
        relativeTo importingFile: URL?,
        requiredBy: String? = nil
    ) throws -> URL {
        let candidates = candidates(for: qualifiedName, relativeTo: importingFile)
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return found
        }
        throw MTLModuleResolutionError.notFound(
            module: qualifiedName,
            searched: candidates.map(\.path),
            requiredBy: requiredBy
        )
    }
}

// MARK: - Module Loader

/// Loads MTL modules together with the modules they import and extend.
///
/// The loader parses a module file, locates the modules named by its
/// `import` and `extends` declarations with an ``MTLModuleResolver``, loads
/// them recursively, and attaches them to the module so that their public and
/// protected templates and queries can be called. Each file is loaded once per
/// call, and cyclic dependencies are reported as errors.
public struct MTLModuleLoader: Sendable {

    /// The resolver that locates imported and extended modules in files.
    public let resolver: MTLModuleResolver

    /// The source that supplies imported and extended modules before the resolver is tried.
    public let moduleSource: (any MTLModuleSource)?

    private let enableDebugging: Bool

    /// Creates a loader.
    ///
    /// - Parameters:
    ///   - resolver: The resolver for imported and extended modules in files.
    ///   - moduleSource: A source that supplies modules from memory (default: none). It is
    ///     asked first; modules it does not know are looked up with the resolver.
    ///   - enableDebugging: Whether the parser logs its progress.
    public init(
        resolver: MTLModuleResolver = MTLModuleResolver(),
        moduleSource: (any MTLModuleSource)? = nil,
        enableDebugging: Bool = false
    ) {
        self.resolver = resolver
        self.moduleSource = moduleSource
        self.enableDebugging = enableDebugging
    }

    /// Loads a module file and everything it depends on.
    ///
    /// - Parameter url: The module file.
    /// - Returns: The module with its imports and parent module attached.
    /// - Throws: `MTLParseError` for syntax errors, `MTLResourceError` if a file cannot be read,
    ///   `MTLModuleResolutionError` if a dependency is missing or cyclic.
    public func load(_ url: URL) async throws -> MTLModule {
        var cache: [String: MTLModule] = [:]
        return try await load(url, requiredBy: nil, stack: [], cache: &cache)
    }

    /// Attaches the dependencies of a module that was parsed from source text.
    ///
    /// - Parameters:
    ///   - module: The parsed module.
    ///   - location: The file the module came from, used to resolve relative imports; may be `nil`.
    /// - Returns: The module with its imports and parent module attached.
    /// - Throws: As for ``load(_:)``.
    public func link(_ module: MTLModule, relativeTo location: URL? = nil) async throws -> MTLModule {
        var cache: [String: MTLModule] = [:]
        let stack = location.map { [Self.key(for: $0)] } ?? []
        return try await link(
            module.located(at: location ?? module.location), locationName: location?.path,
            stack: stack, cache: &cache)
    }

    // MARK: - Recursive Loading

    private func load(
        _ url: URL,
        requiredBy: String?,
        stack: [String],
        cache: inout [String: MTLModule]
    ) async throws -> MTLModule {
        let key = Self.key(for: url)
        if let cycleStart = stack.firstIndex(of: key) {
            throw MTLModuleResolutionError.cycle(Array(stack[cycleStart...]) + [key])
        }
        if let cached = cache[key] {
            return cached
        }

        let parsed = try await MTLParser(enableDebugging: enableDebugging).parseWithoutLinking(url)
        let linked = try await link(parsed, locationName: url.path, stack: stack + [key], cache: &cache)
        cache[key] = linked
        return linked
    }

    /// Loads a module that the module source supplied.
    private func load(
        text: String,
        location: String,
        stack: [String],
        cache: inout [String: MTLModule]
    ) async throws -> MTLModule {
        let key = Self.sourceKey(for: location)
        if let cycleStart = stack.firstIndex(of: key) {
            throw MTLModuleResolutionError.cycle(Array(stack[cycleStart...]) + [key])
        }
        if let cached = cache[key] {
            return cached
        }

        let parsed = try await MTLParser(enableDebugging: enableDebugging).parse(text, filename: location)
        let linked = try await link(parsed, locationName: location, stack: stack + [key], cache: &cache)
        cache[key] = linked
        return linked
    }

    /// Loads a module that another module imports or extends.
    ///
    /// The module source is asked first, then the resolver.
    private func resolve(
        _ name: String,
        for module: MTLModule,
        locationName: String?,
        stack: [String],
        cache: inout [String: MTLModule]
    ) async throws -> MTLModule {
        if let found = try await moduleSource?.source(forModule: name, importedFrom: locationName) {
            return try await load(
                text: found.text, location: found.location, stack: stack, cache: &cache)
        }
        let file = try resolver.locate(name, relativeTo: module.location, requiredBy: module.name)
        return try await load(file, requiredBy: module.name, stack: stack, cache: &cache)
    }

    private func link(
        _ module: MTLModule,
        locationName: String?,
        stack: [String],
        cache: inout [String: MTLModule]
    ) async throws -> MTLModule {
        var imports: [MTLModule] = []
        for name in module.imports {
            imports.append(
                try await resolve(
                    name, for: module, locationName: locationName, stack: stack, cache: &cache))
        }

        var parent: MTLModule?
        if let name = module.extends {
            parent = try await resolve(
                name, for: module, locationName: locationName, stack: stack, cache: &cache)
        }

        return module.linking(imports: imports, extending: parent)
    }

    /// The key that identifies a module that a module source supplied.
    private static func sourceKey(for location: String) -> String {
        "source:" + location
    }

    /// The key that identifies a module file independently of how it was reached.
    private static func key(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
