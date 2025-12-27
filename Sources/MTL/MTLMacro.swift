//
//  MTLMacro.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation

// MARK: - MTL Macro

/// Represents an MTL macro for language extension.
///
/// Macros provide a mechanism for extending MTL with custom language constructs,
/// allowing templates to capture and reuse complex patterns. They can accept
/// both regular parameters and body content parameters.
///
/// ## Overview
///
/// MTL macros enable:
/// - **Pattern reuse**: Common template patterns can be extracted and reused
/// - **Language extension**: New control structures can be defined
/// - **Higher-order templates**: Macros can accept template content as parameters
/// - **DSL creation**: Domain-specific notations can be built on MTL
///
/// ## Body Parameters
///
/// Macros can define a special body parameter that captures the content
/// between macro invocation tags, enabling higher-order template patterns:
///
/// ```mtl
/// [macro wrapDiv(content: Body)]
///   <div>
///     [content/]
///   </div>
/// [/macro]
///
/// [wrapDiv()]
///   Inner content here
/// [/wrapDiv]
/// ```
///
/// ## Example Usage
///
/// ```swift
/// // Simple macro
/// let repeatMacro = MTLMacro(
///     name: "repeat",
///     parameters: [
///         MTLVariable(name: "times", type: "Integer")
///     ],
///     bodyParameter: "content",
///     body: MTLBlock(statements: [
///         MTLForStatement(
///             binding: MTLBinding(
///                 variable: MTLVariable(name: "i", type: "Integer"),
///                 initExpression: MTLExpression(AQLCollectionExpression(
///                     operation: .range,
///                     arguments: [/* 1..times */]
///                 ))
///             ),
///             body: MTLBlock(statements: [
///                 MTLMacroInvocation(macroName: "content")
///             ])
///         )
///     ])
/// )
///
/// // Conditional wrapper macro
/// let ifPublicMacro = MTLMacro(
///     name: "ifPublic",
///     parameters: [MTLVariable(name: "element", type: "Element")],
///     bodyParameter: "content",
///     body: MTLBlock(statements: [
///         MTLIfStatement(
///             condition: MTLExpression(/* element.isPublic */),
///             thenBlock: MTLBlock(statements: [
///                 MTLMacroInvocation(macroName: "content")
///             ])
///         )
///     ])
/// )
/// ```
///
/// - Note: Macros are immutable value types designed for safe concurrent
///   access during template execution.
public struct MTLMacro: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the macro.
    ///
    /// Macro names must be valid identifiers and are used for macro
    /// invocation from templates.
    public let name: String

    /// The parameters accepted by this macro.
    ///
    /// Regular parameters are provided when invoking the macro and can
    /// be referenced within the macro body.
    public let parameters: [MTLVariable]

    /// Optional body parameter name.
    ///
    /// If present, the content between macro invocation tags is captured
    /// and made available through this parameter name within the macro body.
    public let bodyParameter: String?

    /// The macro body defining its expansion.
    ///
    /// The body contains the template statements that are executed when
    /// the macro is invoked, with parameter substitution applied.
    public let body: MTLBlock

    /// Optional documentation string.
    ///
    /// Documentation provides usage information and is preserved in the AST
    /// for tool support and code generation.
    public let documentation: String?

    // MARK: - Initialisation

    /// Creates a new MTL macro.
    ///
    /// - Parameters:
    ///   - name: The macro name for invocation
    ///   - parameters: The parameter list (default: empty)
    ///   - bodyParameter: Optional body parameter name (default: nil)
    ///   - body: The macro expansion body
    ///   - documentation: Optional documentation (default: nil)
    ///
    /// - Precondition: The macro name must be a non-empty string
    /// - Precondition: If bodyParameter is specified, it must not be empty
    public init(
        name: String,
        parameters: [MTLVariable] = [],
        bodyParameter: String? = nil,
        body: MTLBlock,
        documentation: String? = nil
    ) {
        precondition(!name.isEmpty, "Macro name must not be empty")
        if let bodyParam = bodyParameter {
            precondition(!bodyParam.isEmpty, "Body parameter name must not be empty")
        }

        self.name = name
        self.parameters = parameters
        self.bodyParameter = bodyParameter
        self.body = body
        self.documentation = documentation
    }
}

// MARK: - MTL Trace

/// Represents a trace link for model-to-text traceability.
///
/// Trace links record the correspondence between source model elements
/// and generated text locations, enabling bidirectional navigation for
/// debugging, incremental generation, and impact analysis.
public struct MTLTraceLink: Sendable, Equatable, Hashable {

    /// The source model element ID.
    public let sourceElement: EUUID

    /// The target file path.
    public let targetFile: String

    /// The range in the target file.
    public let targetRange: Range<Int>

    /// The timestamp when this link was created.
    public let timestamp: Date

    /// Creates a new trace link.
    ///
    /// - Parameters:
    ///   - sourceElement: The source model element ID
    ///   - targetFile: The target file path
    ///   - targetRange: The range in the target file
    ///   - timestamp: The creation timestamp (default: current time)
    public init(
        sourceElement: EUUID,
        targetFile: String,
        targetRange: Range<Int>,
        timestamp: Date = Date()
    ) {
        self.sourceElement = sourceElement
        self.targetFile = targetFile
        self.targetRange = targetRange
        self.timestamp = timestamp
    }
}
