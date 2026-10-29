//
//  MTLDiagnostics.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase

/// The codes of the diagnostics that the MTL parser and generator report.
///
/// The raw value of each case is the stable code in ``SourceDiagnostic/code``. Problems in
/// expressions are reported with the same codes, as unexpected tokens or an unexpected end.
/// The generator reports its warnings in ``MTLGenerationStatistics/warnings``.
public enum MTLDiagnosticCode: String, Sendable, CaseIterable {
    /// A token appeared where the syntax does not allow it.
    case unexpectedToken = "mtl.unexpectedToken"

    /// The text ended where more was required.
    case unexpectedEnd = "mtl.unexpectedEnd"

    /// A string literal has no closing quote.
    case unterminatedString = "mtl.unterminatedString"

    /// A `\u` escape in a string literal lacks four hexadecimal digits.
    case malformedEscape = "mtl.malformedEscape"

    /// A number literal cannot be represented.
    case invalidNumber = "mtl.invalidNumber"

    /// A character that the syntax does not use appeared inside a directive.
    case invalidCharacter = "mtl.invalidCharacter"

    /// A comment or documentation comment is not terminated.
    case unterminatedComment = "mtl.unterminatedComment"

    /// A directive has no closing `]`.
    ///
    /// The problem is reported where the directive opens, for instance at the header of a
    /// template whose `]` is missing, rather than at the text or directive that follows.
    case unterminatedDirective = "mtl.unterminatedDirective"

    /// A declaration repeats one that already exists.
    case duplicateDeclaration = "mtl.duplicateDeclaration"

    /// A `let` block was skipped because a value does not conform to the declared type of its variable.
    ///
    /// The generator reports this warning only with ``MTLLetTypeMismatches/skip``.
    case letTypeMismatch = "mtl.letTypeMismatch"
}

/// The kinds of node in the outline of a module.
///
/// The raw value of each case is the ``OutlineNode/kind`` of the node.
public enum MTLOutlineKind: String, Sendable, CaseIterable {
    /// The module itself.
    case module

    /// A template.
    case template

    /// A query.
    case query

    /// A macro.
    case macro

    /// An `import` declaration.
    case importDeclaration = "import"

    /// An `extends` declaration.
    case extendsDeclaration = "extends"
}

/// The outcome of parsing MTL source text with recovery from syntax errors.
public struct MTLParseResult: Sendable {
    /// The parsed module, or `nil` if its header is malformed.
    ///
    /// Constructs that could not be parsed are left out of the module.
    public var module: MTLModule?

    /// The problems found, ordered by position.
    public var diagnostics: [SourceDiagnostic]

    /// The outline of the module: the module with its imports, templates, queries, and macros.
    ///
    /// The outline holds the declarations that were found even when the module header is
    /// malformed, in which case it lists them directly.
    public var outline: [OutlineNode]

    /// Creates a parse result.
    ///
    /// - Parameters:
    ///   - module: The parsed module, if any.
    ///   - diagnostics: The problems found.
    ///   - outline: The outline of the module.
    public init(module: MTLModule?, diagnostics: [SourceDiagnostic], outline: [OutlineNode]) {
        self.module = module
        self.diagnostics = diagnostics
        self.outline = outline
    }
}

/// The words and separators that the outline of a module uses in its descriptions.
enum MTLOutlineSyntax {
    /// The marker that the description of a main template carries.
    static let mainMarker = "main"

    /// The separator between the parameters in a description.
    static let parameterSeparator = ", "

    /// The text between the name and the type of a parameter in a description.
    static let typeSeparator = " : "

    /// Describes a parameter list as `name : Type, other : Type`.
    ///
    /// - Parameter parameters: The parameters.
    /// - Returns: The description.
    static func parameters(_ parameters: [MTLVariable]) -> String {
        parameters.map { "\($0.name)\(typeSeparator)\($0.type)" }.joined(separator: parameterSeparator)
    }
}
