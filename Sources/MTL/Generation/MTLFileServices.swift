//
//  MTLFileServices.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation

// MARK: - File Options

/// The per-file options of a `file` block.
///
/// Options follow the charset in the `file` header, each as a string literal
/// of the form `'key=value'`; see ``MTLFileOptionKeys``.
public struct MTLFileOptions: Sendable, Equatable, Hashable {

    /// Whether regeneration merging applies to the file.
    ///
    /// Merging still requires a module-level `[merge]` declaration whose file
    /// patterns match the file. Set to `false` with `'merge=false'`.
    public var merge: Bool

    /// Whether the layout conversion applies to the file.
    ///
    /// Conversion still requires a module-level `[layout]` declaration or a
    /// generator layout option whose file patterns match the file. Set to
    /// `false` with `'layout=false'`.
    public var layout: Bool

    /// Creates file options.
    ///
    /// - Parameters:
    ///   - merge: Whether regeneration merging applies to the file (default: `true`).
    ///   - layout: Whether layout conversion applies to the file (default: `true`).
    public init(merge: Bool = true, layout: Bool = true) {
        self.merge = merge
        self.layout = layout
    }
}

// MARK: - File Services

/// The built-in services that expose the file context to templates.
///
/// - `fileExists(path)` tells whether a file exists below the generation
///   base path (or at an absolute path), as seen by the active generation
///   strategy. Files written earlier in the same run count.
/// - `forceOverwrite()` returns the force overwrite generator option.
///
/// The services are registered by every execution context before any
/// client-supplied provider, so clients and modules can override them.
struct MTLFileServices: AQLServiceProvider {

    /// The services offered.
    var services: [AQLService] {
        [
            AQLService(MTLFileServiceNames.fileExists, receiver: .standalone, arity: 1) { call in
                let path = try call.string(0)
                return try await Self.runtime(of: call).fileExists(path)
            },
            AQLService(MTLFileServiceNames.forceOverwrite, receiver: .standalone, arity: 0) { call in
                try await Self.runtime(of: call).forceOverwrite
            },
        ]
    }

    /// Finds the execution context that is evaluating a service call.
    @MainActor
    private static func runtime(of call: AQLServiceCall) async throws -> MTLExecutionContext {
        let handle = (try? await call.context.getVariable(MTLSyntax.runtimeContextVariable)) as? MTLRuntimeHandle
        guard let runtime = handle?.reference.runtime else {
            throw MTLExecutionError.invalidOperation("\(call.name) is only available during generation")
        }
        return runtime
    }
}
