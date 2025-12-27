//
//  MTLGenerator.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation
import OrderedCollections

// MARK: - MTL Generator

/// Main execution engine for MTL model-to-text transformations.
///
/// The MTL generator orchestrates the execution of MTL templates, managing the
/// execution context, template invocation, query evaluation, and generation
/// statistics. It coordinates all aspects of text generation from model inputs.
///
/// ## Overview
///
/// The generator provides:
/// - **Template execution**: Invoke templates with parameter binding
/// - **Query evaluation**: Execute side-effect-free queries
/// - **Macro expansion**: Expand macro invocations (Advanced feature)
/// - **Statistics tracking**: Monitor execution performance and outcomes
/// - **Debugging support**: Optional detailed execution logging
/// - **Module support**: Handle module inheritance and imports (Advanced feature)
///
/// ## Basic Usage
///
/// ```swift
/// // Create module with templates
/// let module = MTLModule(
///     name: "MyGenerator",
///     metamodels: [:],
///     templates: [
///         "main": MTLTemplate(
///             name: "main",
///             parameters: [MTLVariable(name: "model", type: "Model")],
///             body: ...,
///             isMain: true
///         )
///     ]
/// )
///
/// // Create generator
/// let strategy = MTLInMemoryStrategy()
/// let generator = MTLGenerator(module: module, generationStrategy: strategy)
///
/// // Register models
/// var models: [String: Resource] = [:]
/// models["IN"] = inputModel
///
/// // Generate
/// try await generator.generate(
///     mainTemplate: "main",
///     arguments: [modelRoot],
///     models: models
/// )
///
/// // Check results
/// print(generator.statistics.summary())
/// ```
///
/// ## Template Execution
///
/// Templates are executed with parameter binding:
/// ```swift
/// // Template with parameters
/// let template = MTLTemplate(
///     name: "generateClass",
///     parameters: [
///         MTLVariable(name: "class", type: "Class"),
///         MTLVariable(name: "package", type: "String")
///     ],
///     body: ...
/// )
///
/// // Execute with arguments
/// try await generator.executeTemplate(
///     template,
///     arguments: [classElement, "com.example"]
/// )
/// ```
///
/// ## Statistics
///
/// The generator tracks detailed statistics:
/// - Execution time
/// - Success/failure status
/// - Templates executed
/// - Files generated
/// - Lines generated
/// - Protected areas preserved
/// - Last error (if any)
///
/// ```swift
/// print("Execution time: \(generator.statistics.executionTime)s")
/// print("Templates executed: \(generator.statistics.templatesExecuted)")
/// print("Files generated: \(generator.statistics.filesGenerated)")
/// ```
///
/// - Note: This class is `@MainActor` isolated to ensure thread-safe access
///   to execution state and model resources.
@MainActor
public final class MTLGenerator {

    // MARK: - Properties

    /// The MTL module being executed.
    public let module: MTLModule

    /// The execution context managing generation state.
    private var executionContext: MTLExecutionContext

    /// Statistics about the current/last generation run.
    public private(set) var statistics: MTLGenerationStatistics

    /// Whether debug mode is enabled.
    ///
    /// In debug mode, the generator logs detailed information about
    /// template execution, variable bindings, and decisions.
    private var debug: Bool = false

    // MARK: - Initialisation

    /// Creates a new MTL generator for the specified module.
    ///
    /// - Parameters:
    ///   - module: The MTL module to execute
    ///   - generationStrategy: The output strategy for generated text
    public init(module: MTLModule, generationStrategy: any MTLGenerationStrategy) {
        self.module = module
        self.executionContext = MTLExecutionContext(
            module: module,
            generationStrategy: generationStrategy
        )
        self.statistics = MTLGenerationStatistics()
    }

    // MARK: - Debug Control

    /// Enables or disables debug mode.
    ///
    /// When enabled, the generator and execution context will log detailed
    /// information about execution progress.
    ///
    /// - Parameter enabled: Whether to enable debug mode (default: true)
    public func enableDebugging(_ enabled: Bool = true) {
        debug = enabled
        executionContext.debug = enabled
    }

    // MARK: - Generation

    /// Executes the specified main template with the given arguments.
    ///
    /// This is the primary entry point for MTL generation. It:
    /// 1. Resets statistics
    /// 2. Registers input models
    /// 3. Finds the specified main template
    /// 4. Executes the template with arguments
    /// 5. Finalizes the context
    /// 6. Records statistics
    ///
    /// - Parameters:
    ///   - mainTemplate: The name of the main template to execute
    ///   - arguments: The arguments to pass to the template
    ///   - models: The input models keyed by alias (e.g., "IN", "LIB")
    ///
    /// - Throws: `MTLExecutionError` if generation fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// var models: [String: Resource] = [:]
    /// models["IN"] = inputModel
    ///
    /// try await generator.generate(
    ///     mainTemplate: "main",
    ///     arguments: [modelRoot],
    ///     models: models
    /// )
    /// ```
    public func generate(
        mainTemplate: String,
        arguments: [(any EcoreValue)?],
        models: [String: Resource]
    ) async throws {
        let startTime = Date()
        statistics.reset()

        do {
            if debug {
                print("MTL Generation Started")
                print("  Module: \(module.name)")
                print("  Main template: \(mainTemplate)")
                print("  Arguments: \(arguments.count)")
                print("  Models: \(models.keys.joined(separator: ", "))")
            }

            // Register all models
            for (alias, resource) in models {
                executionContext.registerModel(alias, resource: resource)
            }

            // Find the main template
            guard let template = module.templates[mainTemplate] else {
                throw MTLExecutionError.templateNotFound(
                    "Main template '\(mainTemplate)' not found in module '\(module.name)'"
                )
            }

            // Verify it's marked as main (warning only)
            if !template.isMain && debug {
                print("Warning: Template '\(mainTemplate)' is not marked as main")
            }

            // Execute the template
            try await executeTemplate(template, arguments: arguments)

            // Finalize
            try await executionContext.finalize()

            // Record success
            statistics.successful = true
            statistics.executionTime = Date().timeIntervalSince(startTime)

            if debug {
                print("MTL Generation Completed Successfully")
                print(statistics.summary())
            }

        } catch {
            // Record failure
            statistics.successful = false
            statistics.executionTime = Date().timeIntervalSince(startTime)
            statistics.lastError = error

            if debug {
                print("MTL Generation Failed")
                print("  Error: \(error)")
                print(statistics.summary())
            }

            throw error
        }
    }

    // MARK: - Template Execution

    /// Executes a template with the specified arguments.
    ///
    /// This method handles:
    /// 1. Parameter binding
    /// 2. Guard condition evaluation
    /// 3. Template body execution
    /// 4. Post-condition evaluation
    /// 5. Statistics updates
    ///
    /// - Parameters:
    ///   - template: The template to execute
    ///   - arguments: The arguments matching the template parameters
    ///
    /// - Throws: `MTLExecutionError` if execution fails
    ///
    /// ## Guard Conditions
    ///
    /// If the template has a guard condition and it evaluates to `false`,
    /// the template body is not executed:
    /// ```swift
    /// let template = MTLTemplate(
    ///     name: "generatePublicClass",
    ///     parameters: [MTLVariable(name: "class", type: "Class")],
    ///     guard: MTLExpression(/* class.isPublic */),
    ///     body: ...
    /// )
    ///
    /// // If guard fails, body is skipped
    /// try await generator.executeTemplate(template, arguments: [privateClass])
    /// ```
    ///
    /// ## Post-conditions
    ///
    /// If the template has a post-condition and it evaluates to `false`
    /// after execution, an error is thrown:
    /// ```swift
    /// let template = MTLTemplate(
    ///     name: "generateFile",
    ///     parameters: [MTLVariable(name: "path", type: "String")],
    ///     post: MTLExpression(/* fileExists(path) */),
    ///     body: ...
    /// )
    ///
    /// // If post fails, throws error
    /// try await generator.executeTemplate(template, arguments: ["/output/file.txt"])
    /// ```
    public func executeTemplate(
        _ template: MTLTemplate,
        arguments: [(any EcoreValue)?]
    ) async throws {
        if debug {
            print("Executing template: \(template.name)")
            print("  Parameters: \(template.parameters.map { $0.name }.joined(separator: ", "))")
            print("  Arguments: \(arguments.count)")
        }

        // Check parameter count
        guard arguments.count == template.parameters.count else {
            throw MTLExecutionError.invalidOperation(
                "Template '\(template.name)' expects \(template.parameters.count) arguments, got \(arguments.count)"
            )
        }

        // Push new scope for template execution
        executionContext.pushScope()
        defer { executionContext.popScope() }

        // Bind parameters
        for (parameter, argument) in zip(template.parameters, arguments) {
            executionContext.setVariable(parameter.name, value: argument)

            if debug {
                let argDesc = argument.map { String(describing: $0) } ?? "nil"
                print("  Bound: \(parameter.name) = \(argDesc)")
            }
        }

        // Evaluate guard condition
        if let guardExpr = template.guard {
            let guardResult = try await executionContext.evaluateExpression(guardExpr)

            if let boolValue = guardResult as? Bool, !boolValue {
                if debug {
                    print("  Guard failed, skipping template body")
                }
                return
            } else if guardResult == nil {
                if debug {
                    print("  Guard evaluated to null, skipping template body")
                }
                return
            }
        }

        // Execute template body
        try await template.body.execute(in: executionContext)

        // Evaluate post-condition
        if let postExpr = template.post {
            let postResult = try await executionContext.evaluateExpression(postExpr)

            if let boolValue = postResult as? Bool, !boolValue {
                throw MTLExecutionError.postConditionFailed(
                    "Post-condition failed for template '\(template.name)'"
                )
            } else if postResult == nil {
                throw MTLExecutionError.postConditionFailed(
                    "Post-condition evaluated to null for template '\(template.name)'"
                )
            }
        }

        // Update statistics
        statistics.templatesExecuted += 1

        if debug {
            print("  Template completed successfully")
        }
    }

    // MARK: - Query Execution

    /// Executes a query and returns its result.
    ///
    /// Queries are side-effect-free operations that compute values from
    /// model elements without generating text output.
    ///
    /// - Parameters:
    ///   - query: The query to execute
    ///   - arguments: The arguments matching the query parameters
    ///
    /// - Returns: The query result, or nil if the result is null
    ///
    /// - Throws: `MTLExecutionError` if execution fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// let query = MTLQuery(
    ///     name: "isPublic",
    ///     parameters: [MTLVariable(name: "element", type: "Element")],
    ///     returnType: "Boolean",
    ///     body: MTLExpression(/* element.visibility = 'public' */)
    /// )
    ///
    /// let result = try await generator.executeQuery(query, arguments: [element])
    /// if let isPublic = result as? Bool, isPublic {
    ///     print("Element is public")
    /// }
    /// ```
    public func executeQuery(
        _ query: MTLQuery,
        arguments: [(any EcoreValue)?]
    ) async throws -> (any EcoreValue)? {
        if debug {
            print("Executing query: \(query.name)")
        }

        // Check parameter count
        guard arguments.count == query.parameters.count else {
            throw MTLExecutionError.invalidOperation(
                "Query '\(query.name)' expects \(query.parameters.count) arguments, got \(arguments.count)"
            )
        }

        // Push new scope for query execution
        executionContext.pushScope()
        defer { executionContext.popScope() }

        // Bind parameters
        for (parameter, argument) in zip(query.parameters, arguments) {
            executionContext.setVariable(parameter.name, value: argument)
        }

        // Evaluate query body
        let result = try await executionContext.evaluateExpression(query.body)

        if debug {
            let resultDesc = result.map { String(describing: $0) } ?? "nil"
            print("  Query result: \(resultDesc)")
        }

        return result
    }

    // MARK: - Macro Expansion (Advanced)

    /// Expands a macro invocation with the specified arguments.
    ///
    /// Macros are language extension mechanisms that accept both regular
    /// parameters and captured body content.
    ///
    /// - Parameters:
    ///   - macro: The macro to expand
    ///   - arguments: The arguments matching the macro parameters
    ///   - bodyContent: The captured body content (if macro has body parameter)
    ///
    /// - Throws: `MTLExecutionError` if expansion fails
    ///
    /// ## Example
    ///
    /// ```swift
    /// let macro = MTLMacro(
    ///     name: "repeat",
    ///     parameters: [MTLVariable(name: "count", type: "Integer")],
    ///     bodyParameter: "content",
    ///     body: MTLBlock(statements: [
    ///         MTLForStatement(
    ///             binding: MTLBinding(...),
    ///             body: MTLBlock(statements: [
    ///                 // Execute captured content here
    ///             ])
    ///         )
    ///     ])
    /// )
    ///
    /// try await generator.expandMacro(
    ///     macro,
    ///     arguments: [3],
    ///     bodyContent: MTLBlock(statements: [
    ///         MTLTextStatement(value: "Repeated line")
    ///     ])
    /// )
    /// ```
    public func expandMacro(
        _ macro: MTLMacro,
        arguments: [(any EcoreValue)?],
        bodyContent: MTLBlock? = nil
    ) async throws {
        if debug {
            print("Expanding macro: \(macro.name)")
        }

        // Check parameter count
        guard arguments.count == macro.parameters.count else {
            throw MTLExecutionError.invalidOperation(
                "Macro '\(macro.name)' expects \(macro.parameters.count) arguments, got \(arguments.count)"
            )
        }

        // Check body parameter
        if macro.bodyParameter != nil && bodyContent == nil {
            throw MTLExecutionError.invalidOperation(
                "Macro '\(macro.name)' expects body content but none provided"
            )
        }

        // Push new scope for macro expansion
        executionContext.pushScope()
        defer { executionContext.popScope() }

        // Bind regular parameters
        for (parameter, argument) in zip(macro.parameters, arguments) {
            executionContext.setVariable(parameter.name, value: argument)
        }

        // Bind body parameter (as a block that can be executed)
        // TODO: This requires a way to represent blocks as values
        // For now, macros with body parameters are not fully supported

        // Execute macro body
        try await macro.body.execute(in: executionContext)

        if debug {
            print("  Macro expanded successfully")
        }
    }

    // MARK: - Statistics Access

    /// Returns a detailed summary of the current statistics.
    ///
    /// - Returns: A formatted string describing generation statistics
    public func statisticsSummary() -> String {
        return statistics.summary()
    }
}

// MARK: - MTL Generation Statistics

/// Statistics about MTL template execution.
///
/// The statistics structure tracks performance metrics and outcomes
/// for MTL generation runs.
public struct MTLGenerationStatistics: Sendable {

    // MARK: - Properties

    /// Total execution time in seconds.
    public var executionTime: TimeInterval = 0

    /// Whether the generation was successful.
    public var successful: Bool = false

    /// Number of templates executed.
    public var templatesExecuted: Int = 0

    /// Number of files generated.
    public var filesGenerated: Int = 0

    /// Number of lines generated.
    public var linesGenerated: Int = 0

    /// Number of protected areas preserved.
    public var protectedAreasPreserved: Int = 0

    /// The last error that occurred (if any).
    public var lastError: Error?

    // MARK: - Operations

    /// Resets all statistics to their initial state.
    public mutating func reset() {
        executionTime = 0
        successful = false
        templatesExecuted = 0
        filesGenerated = 0
        linesGenerated = 0
        protectedAreasPreserved = 0
        lastError = nil
    }

    /// Returns a formatted summary of the statistics.
    ///
    /// - Returns: A multi-line string describing the statistics
    public func summary() -> String {
        var lines: [String] = []
        lines.append("MTL Generation Statistics:")
        lines.append("  Status: \(successful ? "Success" : "Failed")")
        lines.append("  Execution time: \(String(format: "%.3f", executionTime))s")
        lines.append("  Templates executed: \(templatesExecuted)")
        lines.append("  Files generated: \(filesGenerated)")
        lines.append("  Lines generated: \(linesGenerated)")
        lines.append("  Protected areas preserved: \(protectedAreasPreserved)")

        if let error = lastError {
            lines.append("  Last error: \(error)")
        }

        return lines.joined(separator: "\n")
    }
}
