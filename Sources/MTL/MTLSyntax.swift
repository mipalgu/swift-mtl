//
//  MTLSyntax.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - MTL Syntax Constants

/// The single authoritative home for names and tokens that carry meaning in the MTL syntax.
///
/// Keywords, reserved variable names, annotation markers, file modes, and
/// module naming conventions are defined here so that the lexer, the parser,
/// the runtime, and the module resolver agree on them.
///
/// The constants describe the MOFM2T / Acceleo dialect only. They never refer
/// to the language of the generated text.
public enum MTLSyntax {

    // MARK: - Reserved Variables

    /// The variable bound to the first argument of a template, query, or macro.
    ///
    /// Inside an iterator body without an explicit iterator variable, and
    /// inside a `post` expression, it is bound to the current element or to the
    /// generated text respectively.
    public static let selfVariable = "self"

    /// The implicit, one-based iteration counter available inside a `for` block.
    public static let iterationCounterVariable = "i"

    /// The name under which the runtime registers itself with the expression
    /// evaluator so that invocations in expressions can find the module scope.
    ///
    /// The name is not a valid identifier, so templates can never clash with it.
    static let runtimeContextVariable = "$mtl.runtime"

    // MARK: - Annotations and Comments

    /// The annotation that marks a template as a main (entry point) template.
    public static let mainAnnotation = "@main"

    /// The prefix of a comment that declares the encoding of the module.
    public static let encodingDeclaration = "encoding"

    /// The default character encoding of modules and generated files.
    public static let defaultCharset = "UTF-8"

    // MARK: - Names and Modules

    /// The separator between the segments of a qualified name.
    public static let qualifiedNameSeparator = "::"

    /// The file extension of MTL module files (without the leading dot).
    public static let moduleFileExtension = "mtl"

    // MARK: - Protected Areas

    /// The clause that sets the text in front of the start marker of a protected area.
    public static let startTagPrefixClause = "startTagPrefix"

    /// The clause that sets the text in front of the end marker of a protected area.
    public static let endTagPrefixClause = "endTagPrefix"

    // MARK: - Types

    /// The declared type that accepts any value.
    public static let anyType = "OclAny"

    /// The declared type of a macro parameter that receives the body of the invocation.
    public static let macroBodyType = "Body"

    /// The names of the collection types that may carry an element type in parentheses.
    public static let collectionTypeNames: Set<String> = [
        "Sequence", "OrderedSet", "Set", "Bag", "Collection"
    ]

    /// The names of the primitive types and the Swift types that implement them.
    public static let primitiveTypeNames: [String: Set<String>] = [
        "String": ["String"],
        "Integer": ["Int"],
        "Boolean": ["Bool"],
        "Real": ["Double", "Int"]
    ]

    // MARK: - Standalone Functions

    /// The names of AQL library functions that take no receiver.
    public static let standaloneFunctionNames: Set<String> = [
        "min", "max", "abs", "toString"
    ]

    /// The OCL type operations whose first argument is a type name and whose receiver defaults to `self`.
    public static let typeOperationNames: Set<String> = [
        "oclIsKindOf", "oclIsTypeOf", "oclAsType", "oclIsUndefined"
    ]

    /// The operations whose arguments name types, so that qualified names in them denote types.
    public static let typeArgumentOperationNames: Set<String> = typeOperationNames.union(["filter"])

    /// The operations without a dedicated expression node whose argument is an iterator body.
    ///
    /// The iterator variable may be omitted in the argument, in which case the body is evaluated
    /// with the element bound to `self`.
    public static let iteratorOperationNames: Set<String> = ["sortedBy", "closure", "one", "isUnique"]

    // MARK: - Block Keywords

    /// The keywords that open a block and therefore have a matching closing tag.
    static let blockKeywords: Set<String> = [
        "template", "macro", "for", "if", "let", "file", "protected", MTLGenerationKeywords.emit
    ]

    /// The names of statements that produce no output and so count as block tags for the line rule.
    static let silentStatementNames: Set<String> = [MTLGenerationKeywords.collect]

    /// The keywords that continue a block without opening a new one.
    static let continuationKeywords: Set<String> = ["elseif", "else"]

    /// The keywords that introduce module-level declarations.
    static let declarationKeywords: Set<String> = [
        "module", "import", "extends", "query", MTLGenerationKeywords.merge,
        MTLGenerationKeywords.layout
    ]
}

// MARK: - File Modes

extension MTLOpenMode {

    /// The file mode selected by a Boolean literal.
    ///
    /// - Parameter append: `true` selects appending, `false` selects overwriting.
    /// - Returns: `.append` for `true`, otherwise `.overwrite`.
    public static func mode(append: Bool) -> MTLOpenMode {
        append ? .append : .overwrite
    }

    /// Interprets a value written in the mode position of a `file` block.
    ///
    /// Booleans select overwriting (`false`) or appending (`true`). Strings
    /// must name one of the modes (`'overwrite'`, `'append'`, `'create'`).
    ///
    /// - Parameter value: The evaluated mode expression.
    /// - Returns: The selected mode, or `nil` if the value does not denote a mode.
    public init?(value: (any Sendable)?) {
        switch value {
        case let flag as Bool:
            self = MTLOpenMode.mode(append: flag)
        case let name as String:
            guard let mode = MTLOpenMode(rawValue: name) else { return nil }
            self = mode
        default:
            return nil
        }
    }
}
