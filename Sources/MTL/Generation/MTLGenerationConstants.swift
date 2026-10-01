//
//  MTLGenerationConstants.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

// MARK: - Generation Keywords

/// The keywords introduced by the generation facilities.
///
/// These keywords are recognised by the MTL lexer and parser in addition to
/// the Acceleo-compatible core syntax. They are defined once here so that the
/// lexer, the parser and the documentation agree on their spelling.
public enum MTLGenerationKeywords {

    /// Adds values to a named, de-duplicated set: `[collect ('set', expr)/]`.
    public static let collect = "collect"

    /// Marks where a collected set is rendered: `[emit ('set')]...[/emit]`.
    public static let emit = "emit"

    /// Declares the tagged-block merge configuration of a module.
    public static let merge = "merge"

    /// Separator clause of an emit block: `separator('...')`.
    public static let separator = "separator"

    /// Clause of an emit block that renders it once for the whole collection.
    public static let once = "once"
}

// MARK: - Deferred Block Names

/// The names used by deferred blocks (`[collect]` and `[emit]`).
///
/// Inside an `[emit]` block, the variable named by ``itemVariable`` is bound
/// to the current element of the set and the variable named by
/// ``itemsVariable`` is bound to the whole collection, in insertion order.
/// The expression `collected('set')` reads the current content of a set.
public enum MTLDeferredBlockNames {

    /// The variable bound to the current element inside an emit block.
    public static let itemVariable = "item"

    /// The variable bound to the whole collection inside an emit block.
    public static let itemsVariable = "items"

    /// The name of the expression that reads a collected set.
    public static let collectedFunction = "collected"

    /// The prefix of the hidden variables that mirror the collected sets.
    static let collectedVariablePrefix = "\u{1}mtl.collected."

    /// The character that opens an emit placeholder in a file buffer.
    static let placeholderOpen: Character = "\u{E000}"

    /// The character that closes an emit placeholder in a file buffer.
    static let placeholderClose: Character = "\u{E001}"
}

// MARK: - Merge Option Keys

/// The keys accepted as optional `key=value` arguments of the `[merge]`
/// declaration.
///
/// Each optional argument is a string of the form `key=value`. Unknown keys
/// are rejected by the parser.
public enum MTLMergeOptionKeys {

    /// Space-separated line comment markers, for example `//`.
    public static let lineComments = "lineComments"

    /// The block comment delimiters, separated by a space, for example `/* */`.
    public static let blockComment = "blockComment"

    /// The characters that delimit string and character literals.
    public static let quotes = "quotes"

    /// The characters that end a member (a newline is written `\n`).
    public static let terminators = "terminators"

    /// The character that opens a block body for the indentation strategy.
    public static let opener = "opener"

    /// The separator between key and value of an option.
    public static let assignment: Character = "="

    /// All recognised keys.
    public static let all: Set<String> = [
        lineComments, blockComment, quotes, terminators, opener,
    ]
}
