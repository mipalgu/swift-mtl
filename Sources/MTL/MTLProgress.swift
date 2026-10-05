//
//  MTLProgress.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// A snapshot of how far a generation run has come.
///
/// The generator reports a snapshot each time a template starts or finishes and each time a
/// file is opened or finished, so a user interface can show what is being generated.
public struct MTLProgress: Sendable, Equatable {
    /// The number of templates that have finished running.
    public var templatesExecuted: Int

    /// The number of files that have been finished and handed to the generation strategy.
    public var filesWritten: Int

    /// The name of the template that is running, or `nil` between templates.
    public var currentTemplate: String?

    /// The name of the file that is being generated, or `nil` outside file blocks.
    public var currentFile: String?

    /// Creates a progress snapshot.
    ///
    /// - Parameters:
    ///   - templatesExecuted: The number of templates that have finished (default: 0).
    ///   - filesWritten: The number of files that have been finished (default: 0).
    ///   - currentTemplate: The name of the running template (default: none).
    ///   - currentFile: The name of the file being generated (default: none).
    public init(
        templatesExecuted: Int = 0, filesWritten: Int = 0, currentTemplate: String? = nil,
        currentFile: String? = nil
    ) {
        self.templatesExecuted = templatesExecuted
        self.filesWritten = filesWritten
        self.currentTemplate = currentTemplate
        self.currentFile = currentFile
    }
}

/// The time budget after which a long-running generation lets other work on its actor proceed.
enum MTLYielding {
    /// The longest stretch of work between two yields.
    static let budget: Duration = .milliseconds(10)
}
