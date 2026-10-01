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
    let aqlContext: AQLExecutionContext

    /// The modules whose elements are currently executing, innermost last.
    ///
    /// Invocations resolve names relative to the innermost module, so that a
    /// template of an imported module sees that module's own imports.
    var moduleStack: [MTLModule] = []

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

    /// The indentation level that was current when each writer of ``writerStack`` was pushed.
    private var writerBaseLevels: [Int] = [0]

    // MARK: Deferred Blocks

    /// The collected sets and pending emit blocks, one entry per open output.
    ///
    /// The first entry belongs to the main output; each open file adds an
    /// entry that is removed when the file closes.
    private var deferredStates: [MTLDeferredState] = [MTLDeferredState()]

    /// Whether the line break that starts the next text statement is to be dropped.
    private var absorbsNextLineBreak = false

    /// Whether emit blocks are currently being rendered.
    private var isRenderingDeferred = false

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
    ///   - protectedAreaManager: Optional protected area manager for preserving user code
    ///   - serviceProviders: AQL service providers to register (default: none). Later
    ///     providers take precedence over earlier ones. See ``register(_:)``.
    public init(
        module: MTLModule,
        generationStrategy: any MTLGenerationStrategy,
        aqlContext: AQLExecutionContext? = nil,
        protectedAreaManager: MTLProtectedAreaManager? = nil,
        serviceProviders: [any AQLServiceProvider] = []
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

        // Let expressions evaluated by AQL find this runtime for invocations
        self.aqlContext.setVariable(
            MTLSyntax.runtimeContextVariable,
            value: MTLRuntimeHandle(runtime: self)
        )

        self.aqlContext.register(MTLFileServices())
        for provider in serviceProviders {
            self.aqlContext.register(provider)
        }
    }

    // MARK: - Services

    /// Registers a provider of AQL services for use in expressions.
    ///
    /// The services of the provider can be called from templates as
    /// `receiver.name(args)`, `receiver->name(args)` and `name(args)`. Templates,
    /// queries and macros of the module (and of its parents and imports) always take
    /// precedence over services of the same name and arity; services take precedence over
    /// the AQL standard library, and later registrations over earlier ones.
    ///
    /// - Parameter provider: The provider whose services become available.
    public func register(_ provider: some AQLServiceProvider) {
        aqlContext.register(provider)
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

    /// Sets a variable that every template, query and macro can read.
    ///
    /// A global variable lives in the outermost scope, so it outlives every scope that is
    /// active when it is set. Template parameters and `let` variables of the same name
    /// shadow it inside their own scope; the global itself is never changed by them. Setting
    /// a global again replaces its value, including any inner binding of the same name.
    ///
    /// - Parameters:
    ///   - name: The variable name
    ///   - value: The variable value (nil for null)
    public func setGlobalVariable(_ name: String, value: (any EcoreValue)?) {
        if scopeStack.isEmpty {
            variables[name] = value
        } else {
            scopeStack[0][name] = value
            for index in scopeStack.indices.dropFirst() { scopeStack[index][name] = nil }
            variables[name] = nil
        }
        aqlContext.setGlobalVariable(name, value: value)
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
        aqlContext.pushScope()
    }

    /// Pops the current variable scope from the stack.
    ///
    /// All variables in the current scope are discarded, and the previous
    /// scope's bindings are restored. If there are no scopes to pop (only
    /// the global scope remains), this is a no-op.
    public func popScope() {
        guard !scopeStack.isEmpty else { return }
        variables = scopeStack.removeLast()
        aqlContext.popScope()
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
    /// indentation. This is typically called when entering a block. The new
    /// level applies to every line that is started in the current output
    /// from now on, deterministically and relative to where the output began.
    public func pushIndentation() {
        indentationStack.append(currentIndentation.increment())
    }

    /// Pops the current indentation level from the stack.
    ///
    /// The indentation returns to the previous level. This is typically
    /// called when exiting a block. If there is only one indentation level
    /// (the base level), this is a no-op.
    public func popIndentation() {
        guard indentationStack.count > 1 else { return }
        indentationStack.removeLast()
    }

    /// Returns the current indentation level.
    ///
    /// This is the indentation level of the innermost block that is being
    /// executed, counted from the start of the whole generation.
    public var currentIndentation: MTLIndentation {
        return indentationStack.last ?? MTLIndentation()
    }

    /// The indentation that new lines of the current output receive.
    ///
    /// Output that is captured or written to a file starts at no indentation
    /// when it is opened, so the levels that were already open at that point do not
    /// count towards it.
    private var effectiveIndentation: MTLIndentation {
        let current = currentIndentation
        let base = writerBaseLevels.last ?? 0
        return MTLIndentation(level: max(0, current.level - base), indentString: current.indentString)
    }

    /// Hands the current writer the indentation that applies right now.
    ///
    /// - Parameter writer: The writer that is about to receive text.
    private func synchroniseIndentation(of writer: MTLWriter) async {
        await writer.setIndentation(effectiveIndentation)
    }

    // MARK: - Writer Management (Internal)

    /// Pushes a writer onto the stack (internal use).
    ///
    /// This is used internally for capturing output in temporary writers.
    ///
    /// - Parameter writer: The writer to push
    func pushWriter(_ writer: MTLWriter) async {
        appendWriter(writer)
    }

    /// Pops the top writer from the stack (internal use).
    ///
    /// - Returns: The popped writer, or nil if only the main writer remains
    @discardableResult
    func popWriter() async -> MTLWriter? {
        guard writerStack.count > 1 else { return nil }
        return removeLastWriter()
    }

    /// Pushes a writer and remembers the indentation level at which it starts.
    private func appendWriter(_ writer: MTLWriter) {
        writerStack.append(writer)
        writerBaseLevels.append(currentIndentation.level)
    }

    /// Removes the innermost writer and returns it.
    @discardableResult
    private func removeLastWriter() -> MTLWriter {
        writerBaseLevels.removeLast()
        return writerStack.removeLast()
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
    public func write(_ text: String, indent: Bool = true) async {
        guard let currentWriter = writerStack.last else { return }
        await synchroniseIndentation(of: currentWriter)
        await currentWriter.write(text, indent: indent)
    }

    /// Writes a line of text followed by a newline to the current writer.
    ///
    /// - Parameters:
    ///   - text: The text to write (default: empty string for blank line)
    ///   - indent: Whether to apply indentation (default: true)
    public func writeLine(_ text: String = "", indent: Bool = true) async {
        guard let currentWriter = writerStack.last else { return }
        await synchroniseIndentation(of: currentWriter)
        await currentWriter.writeLine(text, indent: indent)
    }

    /// Records whether the next text statement drops the line break it starts with.
    ///
    /// - Parameter absorbs: `true` to drop that line break
    func absorbNextLineBreak(_ absorbs: Bool) {
        absorbsNextLineBreak = absorbs
    }

    /// Reports and clears a pending line break absorption.
    ///
    /// - Returns: `true` if the text statement being executed drops a leading line break
    func takeLineBreakAbsorption() -> Bool {
        defer { absorbsNextLineBreak = false }
        return absorbsNextLineBreak
    }

    /// Whether the current output has text on its last line.
    var isMidLine: Bool {
        get async {
            guard let text = await writerStack.last?.getContent() else { return false }
            return !(text.isEmpty || text.last?.isNewline == true)
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
    ///   - options: The per-file options (default: none)
    ///
    /// - Throws: `MTLExecutionError.fileError` if the file cannot be opened
    public func openFile(
        url: String, mode: MTLOpenMode, charset: String, options: MTLFileOptions = MTLFileOptions()
    ) async throws {
        let newWriter = try await generationStrategy.createWriter(
            url: url,
            mode: mode,
            charset: charset,
            indentation: MTLIndentation()
        )

        // Preserve the protected areas of a file that is about to be overwritten
        var state = MTLDeferredState()
        state.fileURL = url
        state.fileOptions = options
        if mode == .overwrite, let existing = await generationStrategy.existingContent(url: url) {
            state.protectedAreasBeforeScan = await protectedAreaManager.getAllContent()
            await protectedAreaManager.scanContent(existing)
        }

        switchCollectedVariables(from: deferredStates.last, to: state)
        appendWriter(newWriter)
        deferredStates.append(state)
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

        let fileWriter = removeLastWriter()
        let state = deferredStates.count > 1 ? deferredStates.removeLast() : MTLDeferredState()

        var regions: [MTLEmittedRegion] = []
        if !state.emits.isEmpty {
            let content = await fileWriter.getContent()
            let (resolved, emitted) = try await resolveDeferredBlocks(in: content, state: state)
            await fileWriter.replaceContent(resolved)
            regions = emitted
        }
        let mergeConfiguration = module.mergeConfiguration.flatMap { configuration in
            state.fileOptions.merge && configuration.applies(toFile: state.fileURL) ? configuration : nil
        }
        await fileWriter.setGenerationInfo(
            mergeConfiguration: mergeConfiguration, emittedRegions: regions)

        // Forget the protected areas scanned from this file's previous version
        if let before = state.protectedAreasBeforeScan {
            await protectedAreaManager.clear()
            for (id, area) in before {
                await protectedAreaManager.setContent(
                    id, content: area.content, markers: (area.startMarker, area.endMarker))
            }
        }
        switchCollectedVariables(from: state, to: deferredStates.last)

        try await generationStrategy.finalizeWriter(fileWriter)
    }

    /// Tells whether a file exists as seen by the generation strategy.
    ///
    /// - Parameter path: The file path, relative to the generation base path unless absolute.
    /// - Returns: `true` if a file exists at the path.
    public func fileExists(_ path: String) async -> Bool {
        await generationStrategy.fileExists(url: path)
    }

    /// The force overwrite option of the generation strategy.
    public var forceOverwrite: Bool {
        generationStrategy.generatorOptions.forceOverwrite
    }

    // MARK: - Deferred Blocks

    /// Adds values to a collected set of the current output.
    ///
    /// Values are appended in order; values already in the set are ignored.
    ///
    /// - Parameters:
    ///   - values: The values to add
    ///   - name: The name of the set
    public func collect(_ values: [String], into name: String) {
        guard !deferredStates.isEmpty else { return }
        let last = deferredStates.count - 1
        for value in values {
            deferredStates[last].sets[name, default: []].append(value)
        }
        mirrorCollectedSet(name)
    }

    /// Returns the values collected so far for the current output.
    ///
    /// - Parameter name: The name of the set
    /// - Returns: The values in insertion order, empty if nothing was collected
    public func collectedValues(_ name: String) -> [String] {
        guard let set = deferredStates.last?.sets[name] else { return [] }
        return Array(set)
    }

    /// Writes a placeholder for an emit block into the current output.
    ///
    /// The placeholder is replaced with the rendered block when the file closes.
    ///
    /// - Parameters:
    ///   - statement: The emit statement
    ///   - setName: The name of the set to render
    /// - Throws: `MTLExecutionError.invalidOperation` if called while an emit block is rendering
    func registerEmit(_ statement: MTLEmitStatement, setName: String) async throws {
        guard !isRenderingDeferred else {
            throw MTLExecutionError.invalidOperation("Emit blocks cannot be nested")
        }
        var visible: [String: (any EcoreValue)?] = [:]
        for scope in scopeStack {
            visible.merge(scope) { _, new in new }
        }
        visible.merge(variables) { _, new in new }

        let last = deferredStates.count - 1
        let identifier = deferredStates[last].nextEmitIdentifier
        deferredStates[last].nextEmitIdentifier += 1
        deferredStates[last].emits[identifier] = MTLDeferredEmit(
            statement: statement, setName: setName, variables: visible)
        await write(MTLDeferredState.placeholder(for: identifier))
    }

    /// Mirrors a collected set into a hidden variable that `collected(...)` reads.
    private func mirrorCollectedSet(_ name: String) {
        let values: [any EcoreValue] = deferredStates.last?.sets[name].map { Array($0) } ?? []
        aqlContext.setGlobalVariable(
            MTLDeferredBlockNames.collectedVariablePrefix + name, value: EcoreValueArray(values))
    }

    /// Re-targets the hidden collected-set variables when the current output changes.
    private func switchCollectedVariables(
        from old: MTLDeferredState?, to new: MTLDeferredState?
    ) {
        for name in old?.sets.keys ?? [] {
            aqlContext.setGlobalVariable(
                MTLDeferredBlockNames.collectedVariablePrefix + name,
                value: EcoreValueArray([]))
        }
        for (name, set) in new?.sets ?? [:] {
            let values: [any EcoreValue] = Array(set)
            aqlContext.setGlobalVariable(
                MTLDeferredBlockNames.collectedVariablePrefix + name,
                value: EcoreValueArray(values))
        }
    }

    /// Replaces the placeholders in a buffer with the rendered emit blocks.
    ///
    /// - Parameters:
    ///   - content: The buffer content
    ///   - state: The deferred state that owns the placeholders
    /// - Returns: The resolved content and the regions the emit blocks occupy
    /// - Throws: Any error raised while rendering a block
    private func resolveDeferredBlocks(in content: String, state: MTLDeferredState) async throws
        -> (String, [MTLEmittedRegion])
    {
        var output = ""
        var regions: [MTLEmittedRegion] = []
        var remainder = Substring(content)
        while let open = remainder.firstIndex(of: MTLDeferredBlockNames.placeholderOpen) {
            output += remainder[..<open]
            let afterOpen = remainder.index(after: open)
            guard
                let close = remainder[afterOpen...].firstIndex(
                    of: MTLDeferredBlockNames.placeholderClose),
                let identifier = Int(remainder[afterOpen..<close]),
                let emit = state.emits[identifier]
            else {
                output.append(remainder[open])
                remainder = remainder[afterOpen...]
                continue
            }
            let lineIndent = Self.leadingWhitespace(ofLineEndingAt: output)
            let rendered = try await render(emit, state: state, indentation: lineIndent)
            let firstLine = output.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
            var lineCount = rendered.isEmpty ? 0 : rendered.split(
                separator: "\n", omittingEmptySubsequences: false).count
            if rendered.hasSuffix("\n") { lineCount -= 1 }
            regions.append(
                MTLEmittedRegion(name: emit.setName, firstLine: firstLine, lineCount: lineCount))
            output += rendered
            remainder = remainder[remainder.index(after: close)...]
        }
        output += remainder
        return (output, regions)
    }

    /// Renders one emit block for every element of its set.
    private func render(
        _ emit: MTLDeferredEmit, state: MTLDeferredState, indentation: String
    ) async throws -> String {
        guard let set = state.sets[emit.setName], !set.isEmpty else { return "" }
        let values: [any EcoreValue] = Array(set)
        let collection = EcoreValueArray(values)

        let savedVariables = variables
        let savedScopes = scopeStack
        let savedIndentation = indentationStack
        var savedVisible: [String: (any EcoreValue)?] = [:]
        for scope in savedScopes { savedVisible.merge(scope) { _, new in new } }
        savedVisible.merge(savedVariables) { _, new in new }
        isRenderingDeferred = true
        defer {
            isRenderingDeferred = false
            variables = savedVariables
            scopeStack = savedScopes
            indentationStack = savedIndentation
            for (name, value) in savedVisible { aqlContext.setVariable(name, value: value) }
        }

        variables = [:]
        scopeStack = []
        indentationStack = [MTLIndentation()]
        for (name, value) in emit.variables { setVariable(name, value: value) }

        // Resolve the elements to render, in the order the template asks for
        var elements = values
        var visibleCollection = collection
        if let order = emit.statement.order {
            pushScope()
            defer { popScope() }
            setVariable(MTLDeferredBlockNames.itemsVariable, value: collection)
            elements = MTLDeferredSupport.values(from: try await order.evaluate(in: self))
            visibleCollection = EcoreValueArray(elements)
        }

        var output = ""
        let iterations: [(any EcoreValue)?] = emit.statement.rendersOnce ? [nil] : elements
        for (index, value) in iterations.enumerated() {
            pushScope()
            defer { popScope() }
            if let value { setVariable(MTLDeferredBlockNames.itemVariable, value: value) }
            setVariable(MTLDeferredBlockNames.itemsVariable, value: visibleCollection)

            let writer = MTLWriter()
            appendWriter(writer)
            do {
                try await emit.statement.body.execute(in: self)
            } catch {
                removeLastWriter()
                throw error
            }
            removeLastWriter()
            output += Self.indentContinuationLines(await writer.getContent(), by: indentation)

            if index < iterations.count - 1, let separator = emit.statement.separator,
                let text = try await separator.evaluate(in: self)
            {
                output += Self.indentContinuationLines("\(text)", by: indentation)
            }
        }
        return output
    }

    /// The leading whitespace of the line that the given text ends in.
    private static func leadingWhitespace(ofLineEndingAt text: String) -> String {
        let start = text.lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
        let line = text[start...]
        return String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    }

    /// Indents the lines that follow a newline within rendered text.
    private static func indentContinuationLines(_ text: String, by indentation: String) -> String {
        guard !indentation.isEmpty else { return text }
        var result = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            result.append(character)
            if character == "\n" {
                let isLast = index == characters.count - 1
                if isLast || characters[index + 1] != "\n" { result += indentation }
            }
        }
        return result
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
    /// The resource is also made known to the expression evaluator, so that whole-model
    /// services such as `eContainer()` and `allInstances()` can see its objects.
    ///
    /// - Parameters:
    ///   - alias: The model alias used in templates
    ///   - resource: The model resource
    public func registerModel(_ alias: String, resource: Resource) async {
        models[alias] = resource
        aqlContext.addResource(resource)

        // Register resource with AQL execution engine for UUID resolution
        await aqlContext.executionEngine.registerResource(resource, alias: alias)
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

        // Render the deferred blocks of the main output
        if let mainWriter = writerStack.first, let state = deferredStates.first, !state.emits.isEmpty
        {
            let content = await mainWriter.getContent()
            let (resolved, _) = try await resolveDeferredBlocks(in: content, state: state)
            await mainWriter.replaceContent(resolved)
            deferredStates[0].emits = [:]
        }

        // Hand the text written outside any file block to the strategy
        if let mainWriter = writerStack.first {
            try await generationStrategy.writeStandardOutput(await mainWriter.getContent())
        }
    }

    // MARK: - Testing Support

    /// Returns the currently generated text from the main writer.
    ///
    /// This method is primarily intended for testing purposes to verify
    /// generated output without finalizing the generation.
    ///
    /// - Returns: The accumulated text in the current writer
    public func getGeneratedText() async -> String {
        guard let currentWriter = writerStack.last else {
            return ""
        }
        let content = await currentWriter.getContent()
        if let state = deferredStates.last, !state.emits.isEmpty,
            let (resolved, _) = try? await resolveDeferredBlocks(in: content, state: state)
        {
            return resolved
        }
        return content
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
