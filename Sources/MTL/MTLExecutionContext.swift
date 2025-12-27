//
//  MTLExecutionContext.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation
import OCL

// MARK: - MTL Execution Context

/// Manages the execution state for MTL template generation.
///
/// The execution context maintains all runtime state during template execution,
/// including variable bindings, writer stack, indentation, protected areas,
/// and model access. It coordinates between MTL templates and the underlying
/// AQL expression evaluator.
///
/// ## Overview
///
/// The execution context provides:
/// - **Variable scoping**: Stack-based variable scopes with push/pop operations
/// - **Expression evaluation**: Integration with AQL for expression evaluation
/// - **Indentation management**: Stack-based indentation tracking
/// - **Writer management**: Stack of writers for nested file blocks
/// - **Protected areas**: Preservation of user code sections
/// - **Trace support**: Model-to-text traceability links
/// - **Model access**: Registration and access to input models
///
/// ## Variable Scoping
///
/// Variables are managed in a stack of scopes:
/// ```swift
/// context.setVariable("x", value: 10)     // Global scope
/// context.pushScope()
/// context.setVariable("x", value: 20)     // Local scope (shadows global)
/// await context.getVariable("x")          // Returns 20
/// context.popScope()
/// await context.getVariable("x")          // Returns 10
/// ```
///
/// ## Writer Stack
///
/// File blocks create new writers that are pushed onto a stack:
/// ```swift
/// // Main output (stdout)
/// context.write("Top level")
///
/// // Open file block - pushes new writer
/// try await context.openFile(url: "output.txt", mode: .create, charset: "UTF-8")
/// context.write("File content")  // Goes to output.txt
/// try await context.closeFile()  // Pops writer, finalizes file
///
/// context.write("Top level again")  // Back to stdout
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let module = MTLModule(...)
/// let strategy = MTLInMemoryStrategy()
/// let context = MTLExecutionContext(
///     module: module,
///     generationStrategy: strategy
/// )
///
/// // Register models
/// await context.registerModel("input", resource: inputModel)
///
/// // Execute template
/// context.setVariable("model", value: modelRoot)
/// let template = module.templates["generateClass"]!
/// // ... execute template body ...
///
/// // Finalize
/// try await context.finalize()
/// ```
///
/// - Note: This class is `@MainActor` isolated to ensure thread-safe access
///   to execution state and model resources.
@MainActor
public final class MTLExecutionContext: Sendable {

    // MARK: - Properties

    /// The MTL module being executed.
    public let module: MTLModule

    /// The AQL execution context for expression evaluation.
    private let aqlContext: AQLExecutionContext

    /// The generation strategy for output management.
    private let generationStrategy: any MTLGenerationStrategy

    // MARK: Variable Management

    /// Current variable bindings (innermost scope).
    ///
    /// Variables in the current scope shadow variables in outer scopes.
    private var variables: [String: (any EcoreValue)?] = [:]

    /// Stack of saved variable scopes.
    ///
    /// When a new scope is pushed, the current variables are saved here.
    /// When a scope is popped, variables are restored from this stack.
    private var scopeStack: [[String: (any EcoreValue)?]] = []

    // MARK: Indentation Management

    /// Stack of indentation levels.
    ///
    /// Blocks push/pop indentation levels. The top of the stack is the
    /// current indentation.
    private var indentationStack: [MTLIndentation] = [MTLIndentation()]

    // MARK: Writer Management

    /// Stack of writers for nested file blocks.
    ///
    /// The top writer receives all text output. File blocks push new writers,
    /// and closing files pops them.
    private var writerStack: [MTLWriter] = []

    // MARK: Protected Areas

    /// Manager for protected area content preservation.
    ///
    /// Protected areas preserve user code sections across regeneration.
    /// The manager handles scanning existing files and preserving content.
    private let protectedAreaManager: MTLProtectedAreaManager

    // MARK: Trace Support

    /// Traceability links from source model elements to generated text.
    ///
    /// Each link records a correspondence between a model element and a
    /// location in the generated text for debugging and incremental generation.
    private var traceLinks: [(source: any EObject, target: String)] = []

    // MARK: Model Access

    /// Registered input models, keyed by alias.
    ///
    /// Templates reference models by alias (e.g., "IN", "LIB") to access
    /// model elements during generation.
    private var models: [String: Resource] = [:]

    // MARK: Debugging

    /// Whether debug mode is enabled.
    ///
    /// In debug mode, the context may log additional information about
    /// execution state and decisions.
    public var debug: Bool = false

    // MARK: - Initialisation

    /// Creates a new MTL execution context.
    ///
    /// - Parameters:
    ///   - module: The MTL module to execute
    ///   - generationStrategy: The output strategy for generated text
    ///   - aqlContext: Optional AQL context (default: creates new one)
    public init(
        module: MTLModule,
        generationStrategy: any MTLGenerationStrategy,
        aqlContext: AQLExecutionContext? = nil,
        protectedAreaManager: MTLProtectedAreaManager? = nil
    ) {
        self.module = module
        self.generationStrategy = generationStrategy
        self.protectedAreaManager = protectedAreaManager ?? MTLProtectedAreaManager()

        // Create AQL context with empty execution engine (models registered later)
        if let providedContext = aqlContext {
            self.aqlContext = providedContext
        } else {
            let engine = ECoreExecutionEngine(models: [:])
            self.aqlContext = AQLExecutionContext(executionEngine: engine)
        }

        // Create initial stdout writer
        self.writerStack = [MTLWriter()]
    }

    // MARK: - Variable Management

    /// Sets a variable in the current scope.
    ///
    /// If a variable with the same name exists in an outer scope, it is
    /// shadowed by this assignment.
    ///
    /// - Parameters:
    ///   - name: The variable name
    ///   - value: The variable value (nil for null)
    public func setVariable(_ name: String, value: (any EcoreValue)?) {
        variables[name] = value

        // Also set in AQL context for expression evaluation
        aqlContext.setVariable(name, value: value)
    }

    /// Retrieves a variable from the current or enclosing scopes.
    ///
    /// Variables are looked up starting from the current scope and working
    /// outward through the scope stack. If the variable is not found in any
    /// scope, throws an error.
    ///
    /// - Parameter name: The variable name to look up
    /// - Returns: The variable value, or nil if the variable is null
    /// - Throws: `MTLExecutionError.variableNotFound` if the variable is undefined
    public func getVariable(_ name: String) async throws -> (any EcoreValue)? {
        // Check current scope
        if let value = variables[name] {
            return value
        }

        // Check scope stack (innermost to outermost)
        for scope in scopeStack.reversed() {
            if let value = scope[name] {
                return value
            }
        }

        throw MTLExecutionError.variableNotFound("Variable '\(name)' is not defined")
    }

    /// Pushes a new variable scope onto the stack.
    ///
    /// The current variable bindings are saved, and a new empty scope is
    /// created. Variables set after this call will be local to the new scope
    /// until `popScope()` is called.
    public func pushScope() {
        scopeStack.append(variables)
        variables = [:]
    }

    /// Pops the current variable scope from the stack.
    ///
    /// All variables in the current scope are discarded, and the previous
    /// scope's bindings are restored. If there are no scopes to pop (only
    /// the global scope remains), this is a no-op.
    public func popScope() {
        guard !scopeStack.isEmpty else { return }
        variables = scopeStack.removeLast()
    }

    // MARK: - Expression Evaluation

    /// Evaluates an MTL expression using the AQL evaluator.
    ///
    /// The expression is evaluated in the current context with access to
    /// all variables in the current and enclosing scopes.
    ///
    /// - Parameter expr: The expression to evaluate
    /// - Returns: The result of evaluating the expression, or nil if the result is null
    /// - Throws: `MTLExecutionError` if evaluation fails
    public func evaluateExpression(_ expr: MTLExpression) async throws -> (any EcoreValue)? {
        return try await expr.aqlExpression.evaluate(in: aqlContext)
    }

    // MARK: - Indentation Management

    /// Pushes a new indentation level onto the stack.
    ///
    /// The current indentation is incremented and becomes the new current
    /// indentation. This is typically called when entering a block.
    public func pushIndentation() {
        let newIndent = currentIndentation.increment()
        indentationStack.append(newIndent)

        // Update all writers with new indentation
        for writer in writerStack {
            Task {
                await writer.setIndentation(newIndent)
            }
        }
    }

    /// Pops the current indentation level from the stack.
    ///
    /// The indentation returns to the previous level. This is typically
    /// called when exiting a block. If there is only one indentation level
    /// (the base level), this is a no-op.
    public func popIndentation() {
        guard indentationStack.count > 1 else { return }
        indentationStack.removeLast()

        // Update all writers with restored indentation
        let currentIndent = currentIndentation
        for writer in writerStack {
            Task {
                await writer.setIndentation(currentIndent)
            }
        }
    }

    /// Returns the current indentation level.
    ///
    /// This is the indentation that will be applied to new lines of text.
    public var currentIndentation: MTLIndentation {
        return indentationStack.last ?? MTLIndentation()
    }

    // MARK: - Text Generation

    /// Writes text to the current writer.
    ///
    /// The text is written to whichever writer is currently on top of the
    /// writer stack (either the main output or a file writer).
    ///
    /// - Parameters:
    ///   - text: The text to write
    ///   - indent: Whether to apply indentation if at line start (default: true)
    public func write(_ text: String, indent: Bool = true) {
        guard let currentWriter = writerStack.last else { return }
        Task {
            await currentWriter.write(text, indent: indent)
        }
    }

    /// Writes a line of text followed by a newline to the current writer.
    ///
    /// - Parameters:
    ///   - text: The text to write (default: empty string for blank line)
    ///   - indent: Whether to apply indentation (default: true)
    public func writeLine(_ text: String = "", indent: Bool = true) {
        guard let currentWriter = writerStack.last else { return }
        Task {
            await currentWriter.writeLine(text, indent: indent)
        }
    }

    // MARK: - File Management

    /// Opens a new file for output, pushing a new writer onto the stack.
    ///
    /// All subsequent text output will go to this file until `closeFile()`
    /// is called. File blocks can be nested.
    ///
    /// - Parameters:
    ///   - url: The file path or URL
    ///   - mode: The file opening mode (overwrite, append, create)
    ///   - charset: The character encoding (typically "UTF-8")
    ///
    /// - Throws: `MTLExecutionError.fileError` if the file cannot be opened
    public func openFile(url: String, mode: MTLOpenMode, charset: String) async throws {
        let newWriter = try await generationStrategy.createWriter(
            url: url,
            mode: mode,
            charset: charset,
            indentation: currentIndentation
        )
        writerStack.append(newWriter)
    }

    /// Closes the current file, finalizing its content and popping its writer.
    ///
    /// The file's content is committed to the generation strategy, and output
    /// returns to the previous writer (either the parent file or main output).
    ///
    /// - Throws: `MTLExecutionError.fileError` if finalization fails
    public func closeFile() async throws {
        guard writerStack.count > 1 else {
            throw MTLExecutionError.fileError("No file is currently open")
        }

        let fileWriter = writerStack.removeLast()
        try await generationStrategy.finalizeWriter(fileWriter)
    }

    // MARK: - Protected Areas

    /// Retrieves the preserved content for a protected area.
    ///
    /// Protected areas allow user code to be preserved across regeneration.
    /// If the protected area has preserved content from a previous generation,
    /// this method returns it.
    ///
    /// - Parameter id: The protected area identifier
    /// - Returns: The preserved content, or nil if no content exists
    public func getProtectedAreaContent(_ id: String) async -> String? {
        return await protectedAreaManager.getContent(id)
    }

    /// Sets the preserved content for a protected area.
    ///
    /// This is typically called during initialization to restore previously
    /// generated protected area content before regeneration.
    ///
    /// - Parameters:
    ///   - id: The protected area identifier
    ///   - content: The content to preserve
    ///   - markers: Optional tuple of (startMarker, endMarker)
    public func setProtectedAreaContent(
        _ id: String,
        content: String,
        markers: (String, String)? = nil
    ) async {
        await protectedAreaManager.setContent(id, content: content, markers: markers)
    }

    /// Scans a file for protected areas before regeneration.
    ///
    /// This should be called before generating to a file that may already exist,
    /// to preserve any protected areas in the existing file.
    ///
    /// - Parameter path: The file path to scan
    /// - Throws: `MTLExecutionError.fileError` if scanning fails
    public func scanFileForProtectedAreas(_ path: String) async throws {
        try await protectedAreaManager.scanFile(path)
    }

    /// Returns the protected area manager for advanced operations.
    ///
    /// - Returns: The protected area manager
    public var protectedAreas: MTLProtectedAreaManager {
        return protectedAreaManager
    }

    // MARK: - Trace Support

    /// Adds a traceability link from a source model element to generated text.
    ///
    /// Trace links enable bidirectional navigation between models and generated
    /// text for debugging, impact analysis, and incremental generation.
    ///
    /// - Parameters:
    ///   - source: The source model element
    ///   - target: The target location identifier (e.g., file path)
    public func addTraceLink(source: any EObject, target: String) {
        traceLinks.append((source: source, target: target))
    }

    /// Returns all recorded trace links.
    ///
    /// - Returns: Array of (source element, target location) pairs
    public func getTraceLinks() -> [(source: any EObject, target: String)] {
        return traceLinks
    }

    // MARK: - Model Registration

    /// Registers an input model for template access.
    ///
    /// Templates reference models by alias to navigate and query model elements.
    /// Common aliases include "IN" for the primary input model and "LIB" for
    /// library models.
    ///
    /// - Parameters:
    ///   - alias: The model alias used in templates
    ///   - resource: The model resource
    public func registerModel(_ alias: String, resource: Resource) {
        models[alias] = resource

        // TODO: Register model elements in AQL context for navigation
    }

    /// Retrieves a registered model by alias.
    ///
    /// - Parameter alias: The model alias
    /// - Returns: The model resource, or nil if not registered
    public func getModel(_ alias: String) -> Resource? {
        return models[alias]
    }

    // MARK: - Finalization

    /// Finalizes the execution context after generation completes.
    ///
    /// This ensures all pending file operations are completed and resources
    /// are properly cleaned up. Should be called after template execution
    /// finishes.
    ///
    /// - Throws: `MTLExecutionError.fileError` if finalization fails
    public func finalize() async throws {
        // Finalize any remaining open files (shouldn't happen, but be safe)
        while writerStack.count > 1 {
            try await closeFile()
        }

        // Finalize the main writer if needed
        if let mainWriter = writerStack.first {
            // For file system strategy, we might want to write stdout
            // For in-memory strategy, content is already captured
            // This depends on the strategy implementation
            _ = await mainWriter.getContent()
        }
    }

    // MARK: - Debugging

    /// Returns a summary of the current execution state for debugging.
    ///
    /// - Returns: A string describing the current state
    public func debugSummary() async -> String {
        let protectedAreaCount = await protectedAreaManager.getAllContent().count

        var summary = "MTL Execution Context State:\n"
        summary += "  Variables: \(variables.count) in current scope\n"
        summary += "  Scope stack depth: \(scopeStack.count)\n"
        summary += "  Indentation level: \(currentIndentation.level)\n"
        summary += "  Writer stack depth: \(writerStack.count)\n"
        summary += "  Protected areas: \(protectedAreaCount)\n"
        summary += "  Trace links: \(traceLinks.count)\n"
        summary += "  Registered models: \(models.count)\n"
        return summary
    }
}
