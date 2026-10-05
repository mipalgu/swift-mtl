//
//  MTLModuleSource.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// Supplies the text of modules that other modules import or extend.
///
/// A module source lets the linker resolve `import` and `extends` declarations without
/// touching the file system, for example from the documents an editor has open. The linker asks
/// the source first and falls back to the file-based ``MTLModuleResolver`` when the source
/// does not know the module.
public protocol MTLModuleSource: Sendable {
    /// Returns the text of a module.
    ///
    /// - Parameters:
    ///   - module: The qualified name of the module, with `::` between segments.
    ///   - importedFrom: The location of the module that imports or extends it, as an earlier
    ///     call returned it, or `nil` for the module that is being linked.
    /// - Returns: The text of the module and a location that identifies it (a file path, a
    ///   document identifier, or any other string that is unique to the module), or `nil` if
    ///   the source does not know the module.
    /// - Throws: Any error that prevents the source from answering; it stops the linking.
    func source(forModule module: String, importedFrom: String?) async throws -> (text: String, location: String)?
}
