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

    /// The key of the option that restricts a merge declaration to matching files.
    ///
    /// The value is a space-separated list of glob patterns, for example
    /// `files=*.java`.
    public static let files = "files"

    /// The separator between the patterns of the ``files`` option.
    public static let filePatternSeparator: Character = " "

    /// The separator between key and value of an option.
    public static let assignment: Character = "="

    /// All recognised keys.
    public static let all: Set<String> = [
        lineComments, blockComment, quotes, terminators, opener, files,
    ]
}

// MARK: - File Option Keys

/// The keys and values of the optional trailing options of a `file` block.
///
/// A `file` block may carry options after its charset, each written as a
/// string literal of the form `'key=value'`, for example
/// `[file ('plugin.xml', 'overwrite', 'UTF-8', 'merge=false')]`.
public enum MTLFileOptionKeys {

    /// The key that enables or disables regeneration merging for the file.
    public static let merge = "merge"

    /// The value that enables an option.
    public static let enabled = "true"

    /// The value that disables an option.
    public static let disabled = "false"

    /// The character that separates the key from the value.
    public static let assignment: Character = "="

    /// All keys a `file` block understands.
    public static let all: Set<String> = [merge]
}

// MARK: - File Service Names

/// The names of the built-in services that expose the file context to templates.
public enum MTLFileServiceNames {

    /// `fileExists(path)`: whether a file exists below the generation base path.
    public static let fileExists = "fileExists"

    /// `forceOverwrite()`: the force overwrite generator option.
    public static let forceOverwrite = "forceOverwrite"
}

// MARK: - Charset Names

/// The character sets that generated files can be written in.
///
/// Names are matched ignoring case, hyphens, underscores and spaces, so
/// `ISO-8859-1`, `iso_8859_1` and `latin1` are the same character set.
public enum MTLCharsetNames {

    /// The supported character sets with their accepted spellings.
    ///
    /// Each spelling is already normalised (lower case, without separators).
    static let spellings: [(charset: MTLCharset, names: [String])] = [
        (.utf8, ["utf8"]),
        (.utf16, ["utf16"]),
        (.utf16BigEndian, ["utf16be"]),
        (.utf16LittleEndian, ["utf16le"]),
        (.latin1, ["iso88591", "latin1", "l1"]),
        (.ascii, ["usascii", "ascii"]),
    ]

    /// The characters ignored when matching a charset name.
    static let ignoredCharacters: Set<Character> = ["-", "_", " "]
}
