//
//  MTLTemplate.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - MTL Visibility

/// Visibility levels for MTL templates and queries.
///
/// Visibility controls which templates and queries can be invoked from
/// outside their defining module or from submodules.
public enum MTLVisibility: String, Sendable, Codable, Equatable, Hashable {

    /// Public visibility - accessible from any module.
    case `public`

    /// Protected visibility - accessible only from submodules.
    case protected

    /// Private visibility - accessible only within the defining module.
    case `private`
}

// MARK: - MTL Template

/// Represents an MTL template for text generation.
///
/// Templates are the primary text generation units in MTL, defining parameterized
/// transformations from model elements to text. They can include guard conditions,
/// post-conditions, and visibility controls for modular template libraries.
///
/// ## Overview
///
/// MTL templates provide:
/// - **Parameterization**: Type-safe parameters for template invocation
/// - **Guards**: Conditional execution based on runtime conditions
/// - **Post-conditions**: Validation of template execution results
/// - **Visibility**: Access control for template reuse
/// - **Overriding**: Template specialization in module hierarchies
/// - **Main templates**: Entry points for generation
///
/// ## Example Usage
///
/// ```swift
/// // Simple template
/// let helloTemplate = MTLTemplate(
///     name: "sayHello",
///     parameters: [MTLVariable(name: "name", type: "String")],
///     body: MTLBlock(statements: [
///         MTLTextStatement(value: "Hello, "),
///         MTLExpressionStatement(expression: MTLExpression(AQLVariableExpression(name: "name"))),
///         MTLTextStatement(value: "!")
///     ])
/// )
///
/// // Template with guard
/// let guardedTemplate = MTLTemplate(
///     name: "generateClass",
///     parameters: [MTLVariable(name: "class", type: "Class")],
///     guard: MTLExpression(AQLNavigationExpression(
///         source: AQLVariableExpression(name: "class"),
///         property: "isPublic"
///     )),
///     body: classBody
/// )
///
/// // Main template (entry point)
/// let mainTemplate = MTLTemplate(
///     name: "main",
///     parameters: [MTLVariable(name: "model", type: "Model")],
///     body: mainBody,
///     isMain: true
/// )
/// ```
///
/// - Note: Templates are immutable value types designed for safe concurrent
///   access during parallel template execution.
public struct MTLTemplate: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the template.
    ///
    /// Template names must be valid identifiers and are used for template
    /// invocation and overriding in module hierarchies.
    public let name: String

    /// The visibility of this template.
    ///
    /// Visibility controls whether the template can be invoked from other
    /// modules or only within its defining module.
    public let visibility: MTLVisibility

    /// The parameters accepted by this template.
    ///
    /// Parameters define the template's interface and must be provided
    /// when invoking the template. Each parameter specifies a name and
    /// expected type.
    public let parameters: [MTLVariable]

    /// Optional guard condition for conditional execution.
    ///
    /// If present, the guard expression is evaluated before template execution.
    /// If it evaluates to `false`, the template body is not executed.
    public let `guard`: MTLExpression?

    /// Optional post-condition for result validation.
    ///
    /// If present, the post-condition is evaluated after template execution.
    /// If it evaluates to `false`, an error is thrown.
    public let post: MTLExpression?

    /// The template body containing generation statements.
    ///
    /// The body defines the text generation logic, including literal text,
    /// expressions, control flow, and file operations.
    public let body: MTLBlock

    /// Whether this template is a main entry point.
    ///
    /// Main templates can be specified as the entry point for generation.
    /// A module may have multiple main templates for different use cases.
    public let isMain: Bool

    /// Optional name of the template being overridden.
    ///
    /// In module hierarchies with inheritance, templates can override parent
    /// templates by specifying the parent template name.
    public let overrides: String?

    /// Optional documentation string.
    ///
    /// Documentation provides usage information and is preserved in the AST
    /// for tool support and code generation.
    public let documentation: String?

    // MARK: - Initialisation

    /// Creates a new MTL template.
    ///
    /// - Parameters:
    ///   - name: The template name for invocation
    ///   - visibility: The visibility level (default: .public)
    ///   - parameters: The parameter list (default: empty)
    ///   - guard: Optional guard condition (default: nil)
    ///   - post: Optional post-condition (default: nil)
    ///   - body: The template body
    ///   - isMain: Whether this is a main template (default: false)
    ///   - overrides: Optional parent template name (default: nil)
    ///   - documentation: Optional documentation (default: nil)
    ///
    /// - Precondition: The template name must be a non-empty string
    public init(
        name: String,
        visibility: MTLVisibility = .public,
        parameters: [MTLVariable] = [],
        `guard`: MTLExpression? = nil,
        post: MTLExpression? = nil,
        body: MTLBlock,
        isMain: Bool = false,
        overrides: String? = nil,
        documentation: String? = nil
    ) {
        precondition(!name.isEmpty, "Template name must not be empty")

        self.name = name
        self.visibility = visibility
        self.parameters = parameters
        self.`guard` = `guard`
        self.post = post
        self.body = body
        self.isMain = isMain
        self.overrides = overrides
        self.documentation = documentation
    }
}
