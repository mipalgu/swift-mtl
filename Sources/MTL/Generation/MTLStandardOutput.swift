//
//  MTLStandardOutput.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// The names that identify the main output of a generation run.
public enum MTLStandardOutput {

    /// The file name under which in-memory strategies store the text written outside any file block.
    public static let fileName = "stdout"
}

/// Where a file system strategy sends the text written outside any file block.
///
/// Templates may produce text before, between or after their `[file]` blocks. That text belongs
/// to no file, so a file system strategy never writes it to disk; this value decides what happens
/// to it instead.
///
/// - Note: The default is ``discard``.
public enum MTLStandardOutputSink: Sendable {

    /// Drops the text.
    case discard

    /// Keeps the text of the latest run so that the caller can read it with
    /// ``MTLFileSystemStrategy/standardOutput``.
    case capture

    /// Passes the text to a handler once the run has finished.
    ///
    /// The handler receives the complete text, including when it is empty.
    case handler(@Sendable (String) async -> Void)
}
