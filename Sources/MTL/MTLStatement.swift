//
//  MTLStatement.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

// MARK: - MTL Statement Protocol

/// Protocol for all MTL statements that can be executed within templates.
///
/// MTL statements form the building blocks of template bodies, defining both
/// text generation operations and control flow constructs. Statements execute
/// within an MTL execution context, which provides access to variables, models,
/// indentation state, and text writers.
///
/// ## Overview
///
/// MTL supports several categories of statements:
/// - **Text generation**: Output literal text or expression results
/// - **Control flow**: Loops, conditionals, and variable bindings
/// - **File operations**: Create and manage output files
/// - **Advanced features**: Protected areas, macros, and traceability
///
/// ## Concurrency
///
/// Statement execution is coordinated through the `@MainActor` to ensure
/// thread-safe access to shared execution context and writer state.
public protocol MTLStatement: Sendable, Equatable, Hashable {

    /// Indicates whether this statement spans multiple lines.
    ///
    /// Multi-line statements typically include control flow constructs
    /// (for, if, let) that introduce indentation and newlines. Single-line
    /// statements (text, expression) generate inline content.
    var multiLines: Bool { get }

    /// Executes the statement within the specified execution context.
    ///
    /// Statement execution may involve:
    /// - Writing text to the current writer
    /// - Evaluating expressions
    /// - Managing indentation levels
    /// - Creating or closing files
    /// - Manipulating variable scopes
    ///
    /// - Parameter context: The execution context providing access to variables,
    ///   models, writers, and other execution state
    /// - Throws: `MTLExecutionError` if execution fails due to undefined variables,
    ///   type errors, file I/O issues, or other runtime problems
    @MainActor
    func execute(in context: MTLExecutionContext) async throws
}

// MARK: - Text and Expression Statements

/// A statement that outputs literal text to the current writer.
///
/// Text statements form the foundation of MTL template output, representing
/// the literal text portions of templates that are copied directly to the
/// generated output.
///
/// ## Example Usage
///
/// ```swift
/// let text = MTLTextStatement(value: "public class ")
/// ```
public struct MTLTextStatement: MTLStatement {

    /// The literal text to output.
    public let value: String

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    /// Whether a newline should be added after this text.
    public let newLineNeeded: Bool

    /// Creates a new text statement.
    ///
    /// - Parameters:
    ///   - value: The literal text to output
    ///   - multiLines: Whether this text spans multiple lines (default: false)
    ///   - newLineNeeded: Whether to add a newline after the text (default: false)
    public init(value: String, multiLines: Bool = false, newLineNeeded: Bool = false) {
        self.value = value
        self.multiLines = multiLines
        self.newLineNeeded = newLineNeeded
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        context.write(value)
        if newLineNeeded {
            context.writeLine()
        }
    }
}

/// A statement that evaluates an expression and outputs the result.
///
/// Expression statements allow dynamic content to be inserted into templates
/// by evaluating AQL expressions and converting their results to strings.
///
/// ## Example Usage
///
/// ```swift
/// let nameExpr = MTLExpression(AQLNavigationExpression(
///     source: AQLVariableExpression(name: "model"),
///     property: "name"
/// ))
/// let exprStmt = MTLExpressionStatement(expression: nameExpr)
/// ```
public struct MTLExpressionStatement: MTLStatement {

    /// The expression to evaluate and output.
    public let expression: MTLExpression

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    /// Whether a newline should be added after the expression result.
    public let newLineNeeded: Bool

    /// Creates a new expression statement.
    ///
    /// - Parameters:
    ///   - expression: The expression to evaluate
    ///   - multiLines: Whether this expression spans multiple lines (default: false)
    ///   - newLineNeeded: Whether to add a newline after the result (default: false)
    public init(expression: MTLExpression, multiLines: Bool = false, newLineNeeded: Bool = false) {
        self.expression = expression
        self.multiLines = multiLines
        self.newLineNeeded = newLineNeeded
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        let result = try await expression.evaluate(in: context)
        if let result = result {
            context.write("\(result)")
        }
        if newLineNeeded {
            context.writeLine()
        }
    }
}

/// A statement that outputs a newline with optional indentation.
///
/// Newline statements allow explicit control over line breaks and indentation
/// in generated text.
public struct MTLNewLineStatement: MTLStatement {

    /// Whether to apply indentation after the newline.
    public let indentationNeeded: Bool

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    /// Whether an additional newline is needed.
    public let newLineNeeded: Bool

    /// Creates a new newline statement.
    ///
    /// - Parameters:
    ///   - indentationNeeded: Whether to indent after the newline (default: true)
    ///   - multiLines: Whether this statement is multi-line (default: false)
    ///   - newLineNeeded: Whether an additional newline is needed (default: false)
    public init(
        indentationNeeded: Bool = true, multiLines: Bool = false, newLineNeeded: Bool = false
    ) {
        self.indentationNeeded = indentationNeeded
        self.multiLines = multiLines
        self.newLineNeeded = newLineNeeded
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        context.writeLine(indent: indentationNeeded)
        if newLineNeeded {
            context.writeLine()
        }
    }
}

/// A statement representing a comment that produces no output.
///
/// Comments in MTL templates are preserved in the AST for documentation
/// and debugging purposes but do not generate any text in the output.
public struct MTLComment: MTLStatement {

    /// The comment text.
    public let value: String

    /// Whether this comment spans multiple lines.
    public let multiLines: Bool

    /// Creates a new comment statement.
    ///
    /// - Parameters:
    ///   - value: The comment text
    ///   - multiLines: Whether this comment spans multiple lines (default: true)
    public init(value: String, multiLines: Bool = true) {
        self.value = value
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        // Comments produce no output
    }
}

// MARK: - For Statement

/// File operations mode enumeration.
public enum MTLOpenMode: String, Sendable, Codable, Equatable, Hashable {
    /// Overwrite the file if it exists, create if it doesn't.
    case overwrite
    /// Append to the file if it exists, create if it doesn't.
    case append
    /// Create the file only if it doesn't exist, fail otherwise.
    case create
}

/// A for loop statement for iterating over collections.
///
/// For statements provide iteration capabilities in MTL templates, allowing
/// generation of repeated content with optional separators.
///
/// ## Example Usage
///
/// ```swift
/// let itemVar = MTLVariable(name: "item", type: "Element")
/// let collectionExpr = MTLExpression(AQLVariableExpression(name: "items"))
/// let binding = MTLBinding(variable: itemVar, initExpression: collectionExpr)
/// let separator = MTLExpression(AQLLiteralExpression(value: ", "))
///
/// let forStmt = MTLForStatement(
///     binding: binding,
///     separator: separator,
///     body: MTLBlock(statements: [
///         MTLExpressionStatement(expression: MTLExpression(AQLVariableExpression(name: "item")))
///     ])
/// )
/// ```
public struct MTLForStatement: MTLStatement {

    /// The variable binding for the loop.
    public let binding: MTLBinding

    /// Optional expression to evaluate and output between iterations.
    public let separator: MTLExpression?

    /// The block of statements to execute for each iteration.
    public let body: MTLBlock

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    /// Creates a new for statement.
    ///
    /// - Parameters:
    ///   - binding: The loop variable binding
    ///   - separator: Optional separator expression (default: nil)
    ///   - body: The loop body
    ///   - multiLines: Whether this is multi-line (default: true)
    public init(
        binding: MTLBinding, separator: MTLExpression? = nil, body: MTLBlock,
        multiLines: Bool = true
    ) {
        self.binding = binding
        self.separator = separator
        self.body = body
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        // Evaluate collection expression
        let collection = try await binding.initExpression.evaluate(in: context)

        // Handle different collection types
        let items: [any EcoreValue]
        if let array = collection as? [any EcoreValue] {
            items = array
        } else if let singleItem = collection {
            items = [singleItem]
        } else {
            items = []
        }

        // Execute body for each item
        for (index, item) in items.enumerated() {
            // Push scope and bind loop variable
            context.pushScope()
            context.setVariable(binding.variable.name, value: item)

            // Execute body
            try await body.execute(in: context)

            // Pop scope
            context.popScope()

            // Write separator (if not last item)
            if index < items.count - 1, let sep = separator {
                let sepValue = try await sep.evaluate(in: context)
                if let sepValue = sepValue {
                    context.write("\(sepValue)")
                }
            }
        }
    }
}

// MARK: - If Statement

/// A conditional statement for branching logic.
///
/// If statements provide conditional execution in MTL templates, supporting
/// if/elseif/else chains for complex branching logic.
public struct MTLIfStatement: MTLStatement {

    /// The condition expression.
    public let condition: MTLExpression

    /// The block to execute if the condition is true.
    public let thenBlock: MTLBlock

    /// Optional elseif conditions and blocks.
    public let elseIfBlocks: [(MTLExpression, MTLBlock)]

    /// Optional else block.
    public let elseBlock: MTLBlock?

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    /// Creates a new if statement.
    ///
    /// - Parameters:
    ///   - condition: The condition expression
    ///   - thenBlock: The then block
    ///   - elseIfBlocks: Optional elseif conditions and blocks (default: empty)
    ///   - elseBlock: Optional else block (default: nil)
    ///   - multiLines: Whether this is multi-line (default: true)
    public init(
        condition: MTLExpression,
        thenBlock: MTLBlock,
        elseIfBlocks: [(MTLExpression, MTLBlock)] = [],
        elseBlock: MTLBlock? = nil,
        multiLines: Bool = true
    ) {
        self.condition = condition
        self.thenBlock = thenBlock
        self.elseIfBlocks = elseIfBlocks
        self.elseBlock = elseBlock
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        // Evaluate main condition
        let condResult = try await condition.evaluate(in: context)
        if let boolResult = condResult as? Bool, boolResult {
            try await thenBlock.execute(in: context)
            return
        }

        // Try elseif conditions
        for (elseIfCond, elseIfBlock) in elseIfBlocks {
            let elseIfResult = try await elseIfCond.evaluate(in: context)
            if let boolResult = elseIfResult as? Bool, boolResult {
                try await elseIfBlock.execute(in: context)
                return
            }
        }

        // Execute else block if present
        if let elseBlock = elseBlock {
            try await elseBlock.execute(in: context)
        }
    }

    // MARK: - Equatable

    public static func == (lhs: MTLIfStatement, rhs: MTLIfStatement) -> Bool {
        guard lhs.condition == rhs.condition else { return false }
        guard lhs.thenBlock == rhs.thenBlock else { return false }
        guard lhs.elseBlock == rhs.elseBlock else { return false }
        guard lhs.multiLines == rhs.multiLines else { return false }
        guard lhs.elseIfBlocks.count == rhs.elseIfBlocks.count else { return false }

        for (lhsElseIf, rhsElseIf) in zip(lhs.elseIfBlocks, rhs.elseIfBlocks) {
            if lhsElseIf.0 != rhsElseIf.0 || lhsElseIf.1 != rhsElseIf.1 {
                return false
            }
        }

        return true
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(condition)
        hasher.combine(thenBlock)
        hasher.combine(elseBlock)
        hasher.combine(multiLines)
        for elseIf in elseIfBlocks {
            hasher.combine(elseIf.0)
            hasher.combine(elseIf.1)
        }
    }
}

// MARK: - Let Statement

/// A let statement for variable binding in a nested scope.
///
/// Let statements create temporary variables within a nested scope, allowing
/// computed values to be reused within template sections.
public struct MTLLetStatement: MTLStatement {

    /// The variable bindings.
    public let variables: [MTLBinding]

    /// The block to execute with the bound variables.
    public let body: MTLBlock

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    /// Creates a new let statement.
    ///
    /// - Parameters:
    ///   - variables: The variable bindings
    ///   - body: The block to execute
    ///   - multiLines: Whether this is multi-line (default: true)
    public init(variables: [MTLBinding], body: MTLBlock, multiLines: Bool = true) {
        self.variables = variables
        self.body = body
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        // Push scope
        context.pushScope()
        defer { context.popScope() }

        // Evaluate and bind variables
        for binding in variables {
            let value = try await binding.initExpression.evaluate(in: context)
            context.setVariable(binding.variable.name, value: value)
        }

        // Execute body
        try await body.execute(in: context)
    }
}

// MARK: - File Statement

/// A file statement for directing output to a file.
///
/// File statements create and manage output files, allowing templates to
/// generate multiple files from a single execution.
public struct MTLFileStatement: MTLStatement {

    /// Expression that computes the file path.
    public let url: MTLExpression

    /// The file open mode.
    public let mode: MTLOpenMode

    /// Optional charset expression.
    public let charset: MTLExpression?

    /// The block to execute (output goes to the file).
    public let body: MTLBlock

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    /// Creates a new file statement.
    ///
    /// - Parameters:
    ///   - url: The file path expression
    ///   - mode: The file open mode (default: .overwrite)
    ///   - charset: Optional charset expression (default: nil)
    ///   - body: The file content block
    ///   - multiLines: Whether this is multi-line (default: true)
    public init(
        url: MTLExpression,
        mode: MTLOpenMode = .overwrite,
        charset: MTLExpression? = nil,
        body: MTLBlock,
        multiLines: Bool = true
    ) {
        self.url = url
        self.mode = mode
        self.charset = charset
        self.body = body
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        // Evaluate URL
        let urlResult = try await url.evaluate(in: context)
        guard let urlString = urlResult as? String else {
            throw MTLExecutionError.typeError("File URL must evaluate to a string")
        }

        // Evaluate charset if present
        let charsetString: String
        if let charset = charset {
            let charsetResult = try await charset.evaluate(in: context)
            charsetString = (charsetResult as? String) ?? "UTF-8"
        } else {
            charsetString = "UTF-8"
        }

        // Open file
        try await context.openFile(url: urlString, mode: mode, charset: charsetString)

        // Execute body
        try await body.execute(in: context)

        // Close file
        try await context.closeFile()
    }
}

// MARK: - Advanced Statements (Placeholders)

/// A protected area statement for preserving user code across generations.
public struct MTLProtectedArea: MTLStatement {

    /// Expression that computes the protected area ID.
    public let id: MTLExpression

    /// Optional start tag prefix expression.
    public let startTagPrefix: MTLExpression?

    /// Optional end tag prefix expression.
    public let endTagPrefix: MTLExpression?

    /// The block to execute (contains default content).
    public let body: MTLBlock

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    public init(
        id: MTLExpression,
        startTagPrefix: MTLExpression? = nil,
        endTagPrefix: MTLExpression? = nil,
        body: MTLBlock,
        multiLines: Bool = true
    ) {
        self.id = id
        self.startTagPrefix = startTagPrefix
        self.endTagPrefix = endTagPrefix
        self.body = body
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        // Evaluate protected area ID
        let idResult = try await id.evaluate(in: context)
        guard let idString = idResult as? String else {
            throw MTLExecutionError.typeError("Protected area ID must evaluate to a string")
        }

        // Evaluate tag prefixes if present
        let startPrefix: String
        if let startTagPrefixExpr = startTagPrefix {
            let startPrefixResult = try await startTagPrefixExpr.evaluate(in: context)
            startPrefix = (startPrefixResult as? String) ?? ""
        } else {
            startPrefix = ""
        }

        let endPrefix: String
        if let endTagPrefixExpr = endTagPrefix {
            let endPrefixResult = try await endTagPrefixExpr.evaluate(in: context)
            endPrefix = (endPrefixResult as? String) ?? ""
        } else {
            endPrefix = ""
        }

        // Generate protection markers
        let startMarker = "\(startPrefix)START PROTECTED REGION \(idString)"
        let endMarker = "\(endPrefix)END PROTECTED REGION \(idString)"

        // Write start marker
        context.writeLine(startMarker)

        // Check for preserved content
        if let preservedContent = context.getProtectedAreaContent(idString) {
            // Write preserved content
            context.write(preservedContent, indent: false)
        } else {
            // Execute body for default content
            try await body.execute(in: context)
        }

        // Write end marker
        context.writeLine(endMarker)
    }
}

/// A trace statement for recording traceability links.
public struct MTLTrace: MTLStatement {

    /// Expression that identifies the source element.
    public let sourceExpression: MTLExpression

    /// The block to execute.
    public let body: MTLBlock

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    public init(sourceExpression: MTLExpression, body: MTLBlock, multiLines: Bool = true) {
        self.sourceExpression = sourceExpression
        self.body = body
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        // Evaluate source expression to get model element
        let sourceResult = try await sourceExpression.evaluate(in: context)

        // Record trace link if source is an EObject
        if let sourceObject = sourceResult as? any EObject {
            // TODO: Track current file/position for accurate target location
            // For now, record with a placeholder target
            context.addTraceLink(source: sourceObject, target: "generated-output")
        }

        // Execute body
        try await body.execute(in: context)
    }
}

/// A macro invocation statement.
public struct MTLMacroInvocation: MTLStatement {

    /// The name of the macro to invoke.
    public let macroName: String

    /// The argument expressions.
    public let arguments: [MTLExpression]

    /// Optional body content to pass to the macro.
    public let bodyContent: MTLBlock?

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    public init(
        macroName: String,
        arguments: [MTLExpression] = [],
        bodyContent: MTLBlock? = nil,
        multiLines: Bool = true
    ) {
        self.macroName = macroName
        self.arguments = arguments
        self.bodyContent = bodyContent
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        // Look up macro in module
        guard let macro = context.module.macros[macroName] else {
            throw MTLExecutionError.macroNotFound(
                "Macro '\(macroName)' not found in module '\(context.module.name)'")
        }

        // Check parameter count
        guard arguments.count == macro.parameters.count else {
            throw MTLExecutionError.invalidOperation(
                "Macro '\(macroName)' expects \(macro.parameters.count) arguments, got \(arguments.count)"
            )
        }

        // Check body parameter requirement
        if macro.bodyParameter != nil && bodyContent == nil {
            throw MTLExecutionError.invalidOperation(
                "Macro '\(macroName)' expects body content but none provided"
            )
        }

        // Push new scope for macro expansion
        context.pushScope()
        defer { context.popScope() }

        // Evaluate and bind arguments
        for (parameter, argumentExpr) in zip(macro.parameters, arguments) {
            let argumentValue = try await argumentExpr.evaluate(in: context)
            context.setVariable(parameter.name, value: argumentValue)
        }

        // Bind body parameter if present
        // TODO: This requires a way to represent blocks as callable values
        // For now, macros with body parameters will have limited functionality

        // Execute macro body
        try await macro.body.execute(in: context)
    }
}
