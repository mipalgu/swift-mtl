//
//  MTLIndentation.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - MTL Indentation

/// Manages indentation levels and whitespace generation for MTL text output.
///
/// MTL indentation provides automatic indentation management for generated text,
/// supporting both space-based and tab-based indentation with configurable
/// indentation strings and nesting levels.
///
/// ## Overview
///
/// MTL templates can generate text with automatic indentation by:
/// - **Tracking nesting levels**: Each block increases the indentation level
/// - **Configurable indentation**: Spaces or tabs with customizable width
/// - **Inlined blocks**: Blocks can opt out of indentation with the `inlined` flag
/// - **Conditional indentation**: Lines can be written with or without indentation
///
/// ## Indentation Behavior
///
/// By default, MTL uses 4-space indentation:
/// ```
/// Level 0: "text"
/// Level 1: "    text"
/// Level 2: "        text"
/// ```
///
/// Indentation can be customized:
/// ```swift
/// // 2-space indentation
/// let indent = MTLIndentation(level: 0, indentString: "  ")
///
/// // Tab indentation
/// let tabIndent = MTLIndentation(level: 0, indentString: "\t")
/// ```
///
/// ## Example Usage
///
/// ```swift
/// var indent = MTLIndentation()
/// print(indent.asString)  // ""
///
/// indent = indent.increment()
/// print(indent.asString)  // "    " (4 spaces)
///
/// indent = indent.increment()
/// print(indent.asString)  // "        " (8 spaces)
///
/// indent = indent.decrement()
/// print(indent.asString)  // "    " (4 spaces)
/// ```
///
/// - Note: Indentation is immutable and thread-safe, designed for concurrent
///   template execution contexts.
public struct MTLIndentation: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The current indentation level (0-based).
    ///
    /// Level 0 means no indentation, level 1 means one indentation unit,
    /// and so on. The level cannot be negative.
    public let level: Int

    /// The string to use for each indentation level.
    ///
    /// Common values:
    /// - `"    "` (4 spaces) - default
    /// - `"  "` (2 spaces)
    /// - `"\t"` (tab character)
    ///
    /// This string is repeated `level` times to produce the final indentation.
    public let indentString: String

    // MARK: - Initialisation

    /// Creates a new indentation with the specified level and indent string.
    ///
    /// - Parameters:
    ///   - level: The indentation level (default: 0)
    ///   - indentString: The string to use for each level (default: 4 spaces)
    ///
    /// - Precondition: The level must not be negative
    /// - Precondition: The indent string must not be empty
    public init(level: Int = 0, indentString: String = "    ") {
        precondition(level >= 0, "Indentation level must not be negative")
        precondition(!indentString.isEmpty, "Indent string must not be empty")

        self.level = level
        self.indentString = indentString
    }

    // MARK: - Operations

    /// Returns a new indentation with the level increased by 1.
    ///
    /// This creates a deeper indentation level, typically used when entering
    /// a nested block in a template.
    ///
    /// - Returns: A new indentation with `level + 1`
    ///
    /// ## Example
    ///
    /// ```swift
    /// let indent0 = MTLIndentation()
    /// let indent1 = indent0.increment()
    /// let indent2 = indent1.increment()
    ///
    /// print(indent0.level)  // 0
    /// print(indent1.level)  // 1
    /// print(indent2.level)  // 2
    /// ```
    public func increment() -> MTLIndentation {
        return MTLIndentation(level: level + 1, indentString: indentString)
    }

    /// Returns a new indentation with the level decreased by 1.
    ///
    /// This creates a shallower indentation level, typically used when exiting
    /// a nested block in a template. If the current level is 0, returns the
    /// same indentation unchanged.
    ///
    /// - Returns: A new indentation with `max(0, level - 1)`
    ///
    /// ## Example
    ///
    /// ```swift
    /// let indent2 = MTLIndentation(level: 2)
    /// let indent1 = indent2.decrement()
    /// let indent0 = indent1.decrement()
    /// let stillIndent0 = indent0.decrement()
    ///
    /// print(indent2.level)       // 2
    /// print(indent1.level)       // 1
    /// print(indent0.level)       // 0
    /// print(stillIndent0.level)  // 0 (cannot go below 0)
    /// ```
    public func decrement() -> MTLIndentation {
        return MTLIndentation(level: max(0, level - 1), indentString: indentString)
    }

    /// Returns the indentation string for the current level.
    ///
    /// This is computed by repeating the `indentString` `level` times.
    /// For level 0, returns an empty string.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let spaces = MTLIndentation(level: 2, indentString: "  ")
    /// print(spaces.asString)  // "    " (4 spaces)
    ///
    /// let tabs = MTLIndentation(level: 3, indentString: "\t")
    /// print(tabs.asString)  // "\t\t\t" (3 tabs)
    /// ```
    public var asString: String {
        guard level > 0 else { return "" }
        return String(repeating: indentString, count: level)
    }
}
