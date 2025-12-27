//
//  MTLWriter.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - MTL Writer

/// Thread-safe actor for accumulating generated text with automatic indentation.
///
/// MTL writers manage the output buffer for text generation, providing thread-safe
/// text accumulation with automatic indentation handling. Writers track whether
/// they are at the start of a line to apply indentation only when needed.
///
/// ## Overview
///
/// MTL writers support:
/// - **Thread-safe accumulation**: Actor isolation ensures safe concurrent access
/// - **Automatic indentation**: Indentation is applied at the start of each line
/// - **Line tracking**: Knows when to apply indentation based on line position
/// - **Content retrieval**: Accumulated text can be retrieved and cleared
/// - **Conditional indentation**: Individual writes can opt out of indentation
///
/// ## Indentation Behavior
///
/// Indentation is automatically applied:
/// - At the start of the first write
/// - After each newline when writing new content
/// - Unless explicitly disabled with `indent: false`
///
/// ```swift
/// let writer = MTLWriter(indentation: MTLIndentation(level: 1))
///
/// await writer.write("Hello")         // "    Hello" (indented)
/// await writer.write(" World")        // "    Hello World" (same line)
/// await writer.newLine()              // "    Hello World\n"
/// await writer.write("Next line")     // "    Hello World\n    Next line"
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let writer = MTLWriter()
///
/// // Write text with automatic indentation
/// await writer.writeLine("class Example {")
/// writer.indentation = writer.indentation.increment()
/// await writer.writeLine("var x: Int")
/// writer.indentation = writer.indentation.decrement()
/// await writer.writeLine("}")
///
/// let output = await writer.getContent()
/// // class Example {
/// //     var x: Int
/// // }
/// ```
///
/// - Note: Writers are actors to ensure thread-safe access during parallel
///   template execution.
public actor MTLWriter {

    // MARK: - Properties

    /// The accumulated text buffer.
    ///
    /// This buffer contains all text written so far, including indentation
    /// and newlines.
    private var buffer: String = ""

    /// Whether the writer is currently at the start of a line.
    ///
    /// When `true`, the next write operation will apply indentation
    /// (unless disabled). When `false`, text is appended without indentation.
    private var atLineStart: Bool = true

    /// The current indentation level.
    ///
    /// This indentation is applied at the start of each line. It can be
    /// modified directly to change the indentation for subsequent writes.
    ///
    /// - Note: This property can be accessed and modified from outside the
    ///   actor since MTLIndentation is a Sendable value type.
    public var indentation: MTLIndentation

    // MARK: - Initialisation

    /// Creates a new writer with the specified initial indentation.
    ///
    /// - Parameter indentation: The initial indentation level (default: level 0)
    public init(indentation: MTLIndentation = MTLIndentation()) {
        self.indentation = indentation
    }

    // MARK: - Indentation Management

    /// Updates the current indentation level.
    ///
    /// - Parameter newIndentation: The new indentation to use
    public func setIndentation(_ newIndentation: MTLIndentation) {
        self.indentation = newIndentation
    }

    // MARK: - Writing Operations

    /// Writes text to the buffer with optional automatic indentation.
    ///
    /// If the writer is at the start of a line and `indent` is `true`,
    /// the current indentation is written before the text. The text is
    /// then appended to the buffer.
    ///
    /// - Parameters:
    ///   - text: The text to write
    ///   - indent: Whether to apply indentation if at line start (default: true)
    ///
    /// ## Example
    ///
    /// ```swift
    /// let writer = MTLWriter(indentation: MTLIndentation(level: 1))
    ///
    /// await writer.write("Hello")           // "    Hello"
    /// await writer.write(" World")          // "    Hello World"
    /// await writer.newLine()
    /// await writer.write("Next", indent: false)  // "    Hello World\nNext" (no indent)
    /// ```
    public func write(_ text: String, indent: Bool = true) {
        guard !text.isEmpty else { return }

        // Apply indentation if at line start and indentation is enabled
        if atLineStart && indent {
            buffer.append(indentation.asString)
        }

        buffer.append(text)
        atLineStart = false
    }

    /// Writes a line of text followed by a newline.
    ///
    /// This is equivalent to calling `write(text, indent: indent)` followed
    /// by `newLine(indent: false)`. The text is written with optional indentation,
    /// then a newline is appended.
    ///
    /// - Parameters:
    ///   - text: The text to write (default: empty string)
    ///   - indent: Whether to apply indentation (default: true)
    ///
    /// ## Example
    ///
    /// ```swift
    /// let writer = MTLWriter(indentation: MTLIndentation(level: 1))
    ///
    /// await writer.writeLine("Line 1")  // "    Line 1\n"
    /// await writer.writeLine("Line 2")  // "    Line 1\n    Line 2\n"
    /// await writer.writeLine()          // "    Line 1\n    Line 2\n\n" (blank line)
    /// ```
    public func writeLine(_ text: String = "", indent: Bool = true) {
        if !text.isEmpty {
            write(text, indent: indent)
        } else if atLineStart && indent {
            // For blank lines, write indentation only if at line start
            buffer.append(indentation.asString)
        }
        buffer.append("\n")
        atLineStart = true
    }

    /// Writes a newline character to the buffer.
    ///
    /// This marks the writer as being at the start of a new line, so the
    /// next write operation will apply indentation.
    ///
    /// - Parameter indent: Whether the next line should be indented (default: true)
    ///   - If `true`, the next write will apply indentation
    ///   - If `false`, the next write will not apply indentation
    ///
    /// ## Example
    ///
    /// ```swift
    /// await writer.write("Line 1")
    /// await writer.newLine()
    /// await writer.write("Line 2")  // Will be indented
    ///
    /// await writer.write("Line 3")
    /// await writer.newLine(indent: false)
    /// await writer.write("Line 4")  // Will NOT be indented
    /// ```
    public func newLine(indent: Bool = true) {
        buffer.append("\n")
        atLineStart = indent
    }

    // MARK: - Content Management

    /// Returns the accumulated buffer contents.
    ///
    /// This retrieves all text that has been written to the buffer without
    /// clearing it. The buffer contents remain available for future writes.
    ///
    /// - Returns: The complete accumulated text including all indentation and newlines
    ///
    /// ## Example
    ///
    /// ```swift
    /// await writer.writeLine("Line 1")
    /// await writer.writeLine("Line 2")
    ///
    /// let content = await writer.getContent()
    /// print(content)  // "Line 1\nLine 2\n"
    ///
    /// // Buffer is still available
    /// await writer.writeLine("Line 3")
    /// let updated = await writer.getContent()
    /// print(updated)  // "Line 1\nLine 2\nLine 3\n"
    /// ```
    public func getContent() -> String {
        return buffer
    }

    /// Clears the buffer and resets the writer state.
    ///
    /// This removes all accumulated text and resets the writer to its initial
    /// state (at line start). The indentation level is preserved.
    ///
    /// ## Example
    ///
    /// ```swift
    /// await writer.writeLine("Line 1")
    /// await writer.clear()
    ///
    /// let content = await writer.getContent()
    /// print(content)  // "" (empty)
    ///
    /// await writer.writeLine("New start")
    /// let newContent = await writer.getContent()
    /// print(newContent)  // "New start\n"
    /// ```
    public func clear() {
        buffer = ""
        atLineStart = true
    }
}
