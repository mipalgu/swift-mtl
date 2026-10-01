//
//  MTLInvocation.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation

// MARK: - Callable

/// A template, query, or macro that can be invoked, together with the module that declares it.
struct MTLCallable {

    /// The kind of module element.
    enum Element {
        case template(MTLTemplate)
        case query(MTLQuery)
        case macro(MTLMacro)
    }

    /// The module element.
    let element: Element

    /// The module that declares the element.
    let owner: MTLModule

    /// The precedence of the declaring module; lower values win ties.
    let rank: Int

    /// The declared types of the parameters, excluding a macro body parameter.
    var parameterTypes: [String] {
        switch element {
        case .template(let template): return template.parameters.map(\.type)
        case .query(let query): return query.parameters.map(\.type)
        case .macro(let macro): return macro.parameters.map(\.type)
        }
    }

    /// The name of the element.
    var name: String {
        switch element {
        case .template(let template): return template.name
        case .query(let query): return query.name
        case .macro(let macro): return macro.name
        }
    }

    /// Whether invoking the element produces text rather than a value.
    var producesText: Bool {
        if case .query = element { return false }
        return true
    }

    /// A key that identifies the element, used to avoid listing it twice.
    var identity: String {
        let location = owner.location?.path ?? ""
        let kind: String
        switch element {
        case .template: kind = "template"
        case .query: kind = "query"
        case .macro: kind = "macro"
        }
        return [owner.name, location, kind, name, parameterTypes.joined(separator: ",")].joined(separator: "|")
    }
}

// MARK: - Module Scope

extension MTLModule {

    /// The module followed by the chain of modules it extends, most derived first.
    var inheritanceChain: [MTLModule] {
        var chain: [MTLModule] = [self]
        var next = extendedModule
        while let module = next {
            chain.append(module)
            next = module.extendedModule
        }
        return chain
    }

    /// The elements named `name` that this module itself declares.
    ///
    /// - Parameters:
    ///   - name: The element name.
    ///   - visibilities: The visibilities to include.
    ///   - rank: The precedence to give the elements.
    /// - Returns: The matching templates, queries, and macros.
    func declaredCallables(named name: String, visibilities: Set<MTLVisibility>, rank: Int) -> [MTLCallable] {
        var found: [MTLCallable] = []
        for template in templates(named: name) where visibilities.contains(template.visibility) {
            found.append(MTLCallable(element: .template(template), owner: self, rank: rank))
        }
        for query in queries(named: name) where visibilities.contains(query.visibility) {
            found.append(MTLCallable(element: .query(query), owner: self, rank: rank))
        }
        if let macro = macros[name] {
            found.append(MTLCallable(element: .macro(macro), owner: self, rank: rank))
        }
        return found
    }
}

// MARK: - Resolution

@MainActor
extension MTLExecutionContext {

    /// The precedence of modules that are neither the root nor one of its ancestors.
    private static var importRank: Int { 1000 }

    /// The module in whose scope names are currently resolved.
    var scopeModule: MTLModule {
        moduleStack.last ?? module
    }

    /// Lists the callables that a name may refer to from the current position.
    ///
    /// The list contains the elements of the current module, the public and
    /// protected elements of the modules it extends, the public elements of
    /// its imports, and the elements of more derived modules of the running
    /// module that override them.
    ///
    /// - Parameters:
    ///   - name: The name being invoked.
    ///   - arity: The total number of arguments, including any receiver, or `nil` for any number.
    /// - Returns: The callables whose parameter count equals `arity` (all of them if `arity` is `nil`).
    func callables(named name: String, arity: Int?) -> [MTLCallable] {
        let scope = scopeModule
        let rootChain = module.inheritanceChain
        func rank(of owner: MTLModule) -> Int {
            rootChain.firstIndex(where: { $0.isSameModule(as: owner) }) ?? (Self.importRank / 2)
        }

        var found: [MTLCallable] = []
        let everything: Set<MTLVisibility> = [.public, .protected, .private]
        let inherited: Set<MTLVisibility> = [.public, .protected]
        let exported: Set<MTLVisibility> = [.public]

        let scopeChain = scope.inheritanceChain
        for (depth, module) in scopeChain.enumerated() {
            let visibilities = depth == 0 ? everything : inherited
            found += module.declaredCallables(named: name, visibilities: visibilities, rank: rank(of: module))
            for (order, imported) in module.importedModules.enumerated() {
                for exporter in imported.inheritanceChain {
                    found += exporter.declaredCallables(
                        named: name, visibilities: exported, rank: Self.importRank + order)
                }
            }
        }

        if let scopeIndex = rootChain.firstIndex(where: { $0.isSameModule(as: scope) }) {
            for derived in rootChain[..<scopeIndex] {
                found += derived.declaredCallables(named: name, visibilities: inherited, rank: rank(of: derived))
            }
        }

        var seen: Set<String> = []
        return found.filter { callable in
            (arity == nil || callable.parameterTypes.count == arity) && seen.insert(callable.identity).inserted
        }
    }

    /// Chooses the most specific callable that accepts the given arguments.
    ///
    /// - Parameters:
    ///   - candidates: The callables of the right name and arity.
    ///   - arguments: The evaluated arguments.
    /// - Returns: The callable with the smallest total type distance, preferring the most derived module on a tie; `nil` if none accepts the arguments.
    func bestCallable(
        among candidates: [MTLCallable],
        for arguments: [(any EcoreValue)?]
    ) -> MTLCallable? {
        var best: (callable: MTLCallable, distance: Int)?
        for candidate in candidates {
            var total = 0
            var applicable = true
            for (value, type) in zip(arguments, candidate.parameterTypes) {
                guard let distance = MTLTypeMatcher.distance(of: value, to: type) else {
                    applicable = false
                    break
                }
                total += distance
            }
            guard applicable else { continue }
            if let current = best,
               (current.distance, current.callable.rank) <= (total, candidate.rank) {
                continue
            }
            best = (candidate, total)
        }
        return best?.callable
    }

    /// Finds the macro to expand for an invocation statement.
    ///
    /// - Parameters:
    ///   - name: The macro name.
    ///   - arguments: The evaluated arguments.
    /// - Returns: The macro and its declaring module, or `nil` if there is none.
    func macro(named name: String, for arguments: [(any EcoreValue)?]) -> (macro: MTLMacro, owner: MTLModule)? {
        let macros = callables(named: name, arity: nil).filter {
            if case .macro = $0.element { return true }
            return false
        }
        let matching = macros.filter { $0.parameterTypes.count == arguments.count }
        if let chosen = bestCallable(among: matching, for: arguments), case .macro(let macro) = chosen.element {
            return (macro, chosen.owner)
        }
        guard let other = macros.first, case .macro(let macro) = other.element else { return nil }
        return (macro, other.owner)
    }

    // MARK: - Evaluation

    /// Evaluates an invocation expression.
    ///
    /// - Parameter invocation: The expression to evaluate.
    /// - Returns: The result of the selected template, query, or macro, or of the AQL library call if none applies.
    /// - Throws: `MTLExecutionError` if a candidate exists but none accepts the argument types.
    func evaluate(_ invocation: MTLInvocationExpression) async throws -> (any EcoreValue)? {
        let arity = invocation.arguments.count + (invocation.receiver == nil ? 0 : 1)
        let candidates = callables(named: invocation.name, arity: arity)
        guard !candidates.isEmpty else {
            return try await invocation.fallback.evaluate(in: aqlContext)
        }

        var values: [(any EcoreValue)?] = []
        if let receiver = invocation.receiver {
            values.append(try await receiver.evaluate(in: aqlContext))
        }
        for argument in invocation.arguments {
            values.append(try await argument.evaluate(in: aqlContext))
        }

        if let chosen = bestCallable(among: candidates, for: values) {
            return try await invoke(chosen, arguments: values)
        }

        if invocation.receiver != nil, let first = values.first,
           let elements = collectionElements(of: first) {
            return try await invokeForEach(candidates, elements: elements, rest: Array(values.dropFirst()), name: invocation.name)
        }

        return try await evaluateLibraryCall(invocation, values: values)
    }

    /// Falls back to the AQL library using already evaluated values.
    private func evaluateLibraryCall(
        _ invocation: MTLInvocationExpression,
        values: [(any EcoreValue)?]
    ) async throws -> (any EcoreValue)? {
        let source = invocation.receiver == nil ? nil : AQLLiteralExpression(value: values.first ?? nil)
        let rest = invocation.receiver == nil ? values : Array(values.dropFirst())
        let call = AQLCallExpression(
            source: source,
            methodName: invocation.name,
            arguments: rest.map { AQLLiteralExpression(value: $0) }
        )
        do {
            return try await call.evaluate(in: aqlContext)
        } catch {
            let types = values.map { value in value.map { String(describing: type(of: $0)) } ?? "null" }
            throw MTLExecutionError.invalidOperation(
                "No template, query, or macro '\(invocation.name)' accepts arguments (\(types.joined(separator: ", ")))")
        }
    }

    /// The elements of a collection value, or `nil` for any other value.
    private func collectionElements(of value: (any EcoreValue)?) -> [any EcoreValue]? {
        (value as? EcoreValueArray)?.values
    }

    /// Invokes a callable once per element of a collection receiver.
    ///
    /// Text producing callables have their results concatenated; queries
    /// collect their results into a sequence.
    private func invokeForEach(
        _ candidates: [MTLCallable],
        elements: [any EcoreValue],
        rest: [(any EcoreValue)?],
        name: String
    ) async throws -> (any EcoreValue)? {
        var text = ""
        var values: [any EcoreValue] = []
        var producesText = true
        for element in elements {
            let arguments = [element] + rest
            guard let chosen = bestCallable(among: candidates, for: arguments) else {
                throw MTLExecutionError.invalidOperation(
                    "No template, query, or macro '\(name)' accepts an element of the receiver collection")
            }
            producesText = chosen.producesText
            let result = try await invoke(chosen, arguments: arguments)
            if let result = result {
                text += "\(result)"
                values.append(result)
            }
        }
        return producesText ? text : EcoreValueArray(values)
    }

    // MARK: - Invocation

    /// Invokes a callable and returns its result.
    ///
    /// - Parameters:
    ///   - callable: The template, query, or macro.
    ///   - arguments: The evaluated arguments.
    /// - Returns: The text generated by a template or macro, or the value of a query.
    func invoke(_ callable: MTLCallable, arguments: [(any EcoreValue)?]) async throws -> (any EcoreValue)? {
        switch callable.element {
        case .query(let query):
            return try await runQuery(query, owner: callable.owner, arguments: arguments)
        case .template(let template):
            return try await runTemplate(template, owner: callable.owner, arguments: arguments, capture: true)
        case .macro(let macro):
            return try await expandMacro(macro, owner: callable.owner, arguments: arguments, bodyText: nil, capture: true)
        }
    }

    /// Binds the parameters of an element and the implicit `self` variable.
    ///
    /// - Parameters:
    ///   - parameters: The declared parameters.
    ///   - arguments: The evaluated arguments, one per parameter.
    func bindParameters(_ parameters: [MTLVariable], to arguments: [(any EcoreValue)?]) {
        for (parameter, argument) in zip(parameters, arguments) {
            setVariable(parameter.name, value: argument)
        }
        if let first = arguments.first, !parameters.contains(where: { $0.name == MTLSyntax.selfVariable }) {
            setVariable(MTLSyntax.selfVariable, value: first)
        }
    }

    /// Runs a template, optionally capturing the text it generates.
    ///
    /// The guard is evaluated first; if it is false or null the body is skipped.
    /// After the body, the `post` expression is applied: a Boolean result acts
    /// as a post-condition, any other result replaces the generated text, with
    /// `self` bound to that text.
    ///
    /// - Parameters:
    ///   - template: The template to run.
    ///   - owner: The module that declares the template.
    ///   - arguments: The evaluated arguments, one per parameter.
    ///   - capture: Whether to return the generated text instead of writing it to the current output.
    /// - Returns: The generated text if `capture` is `true`, otherwise `nil`.
    /// - Throws: `MTLExecutionError` if the argument count is wrong, the post-condition fails, or evaluation fails.
    @discardableResult
    func runTemplate(
        _ template: MTLTemplate,
        owner: MTLModule,
        arguments: [(any EcoreValue)?],
        capture: Bool
    ) async throws -> String? {
        guard arguments.count == template.parameters.count else {
            throw MTLExecutionError.invalidOperation(
                "Template '\(template.name)' expects \(template.parameters.count) arguments, got \(arguments.count)"
            )
        }

        moduleStack.append(owner)
        pushScope()
        defer {
            popScope()
            moduleStack.removeLast()
        }
        bindParameters(template.parameters, to: arguments)

        if let guardExpression = template.guard {
            let guardResult = try await evaluateExpression(guardExpression)
            if guardResult == nil || (guardResult as? Bool) == false {
                return capture ? "" : nil
            }
        }

        var text: String?
        if capture || template.post != nil {
            text = try await captureOutput { try await template.body.execute(in: self) }
        } else {
            try await template.body.execute(in: self)
        }

        if let post = template.post, let generated = text {
            text = try await applyPost(post, to: generated, templateName: template.name)
        }

        if !capture, let generated = text {
            await write(generated)
            return nil
        }
        return text
    }

    /// Evaluates a `post` expression against the generated text.
    private func applyPost(_ post: MTLExpression, to generated: String, templateName: String) async throws -> String {
        pushScope()
        defer { popScope() }
        setVariable(MTLSyntax.selfVariable, value: generated)
        let result = try await evaluateExpression(post)

        switch result {
        case nil:
            throw MTLExecutionError.postConditionFailed(
                "Post-condition evaluated to null for template '\(templateName)'")
        case let condition as Bool:
            if !condition {
                throw MTLExecutionError.postConditionFailed("Post-condition failed for template '\(templateName)'")
            }
            return generated
        case let replacement as String:
            return replacement
        case let other?:
            return "\(other)"
        }
    }

    /// Runs a query and returns its value.
    ///
    /// - Parameters:
    ///   - query: The query to run.
    ///   - owner: The module that declares the query.
    ///   - arguments: The evaluated arguments, one per parameter.
    /// - Returns: The value of the query body.
    /// - Throws: `MTLExecutionError` if the argument count is wrong or evaluation fails.
    func runQuery(
        _ query: MTLQuery,
        owner: MTLModule,
        arguments: [(any EcoreValue)?]
    ) async throws -> (any EcoreValue)? {
        guard arguments.count == query.parameters.count else {
            throw MTLExecutionError.invalidOperation(
                "Query '\(query.name)' expects \(query.parameters.count) arguments, got \(arguments.count)"
            )
        }
        moduleStack.append(owner)
        pushScope()
        defer {
            popScope()
            moduleStack.removeLast()
        }
        bindParameters(query.parameters, to: arguments)
        return try await evaluateExpression(query.body)
    }

    /// Expands a macro, optionally capturing the text it generates.
    ///
    /// - Parameters:
    ///   - macro: The macro to expand.
    ///   - owner: The module that declares the macro.
    ///   - arguments: The evaluated arguments, one per regular parameter.
    ///   - bodyText: The text generated by the invocation body, bound to the body parameter.
    ///   - capture: Whether to return the generated text instead of writing it to the current output.
    /// - Returns: The generated text if `capture` is `true`, otherwise `nil`.
    /// - Throws: `MTLExecutionError` if the arguments do not fit the macro.
    @discardableResult
    func expandMacro(
        _ macro: MTLMacro,
        owner: MTLModule,
        arguments: [(any EcoreValue)?],
        bodyText: String?,
        capture: Bool
    ) async throws -> String? {
        guard arguments.count == macro.parameters.count else {
            throw MTLExecutionError.invalidOperation(
                "Macro '\(macro.name)' expects \(macro.parameters.count) arguments, got \(arguments.count)"
            )
        }
        if macro.bodyParameter != nil && bodyText == nil {
            throw MTLExecutionError.invalidOperation(
                "Macro '\(macro.name)' expects body content but none provided"
            )
        }

        moduleStack.append(owner)
        pushScope()
        defer {
            popScope()
            moduleStack.removeLast()
        }
        bindParameters(macro.parameters, to: arguments)
        if let bodyParameter = macro.bodyParameter, let bodyText = bodyText {
            setVariable(bodyParameter, value: bodyText)
        }

        if capture {
            return try await captureOutput { try await macro.body.execute(in: self) }
        }
        try await macro.body.execute(in: self)
        return nil
    }

    /// Runs a block of work with its output redirected into a string.
    ///
    /// - Parameter work: The work that generates text.
    /// - Returns: The text generated by the work.
    /// - Throws: Any error thrown by the work; the redirection is undone first.
    func captureOutput(_ work: () async throws -> Void) async throws -> String {
        let writer = MTLWriter(indentation: MTLIndentation())
        await pushWriter(writer)
        do {
            try await work()
        } catch {
            await popWriter()
            throw error
        }
        await popWriter()
        return await writer.getContent()
    }
}

// MARK: - Expression Output

@MainActor
extension MTLExecutionContext {

    /// The text an expression result contributes to the output.
    ///
    /// Collections contribute the concatenated text of their elements.
    ///
    /// - Parameter value: The evaluated expression.
    /// - Returns: The text to write.
    func renderedText(of value: any EcoreValue) -> String {
        if let array = value as? EcoreValueArray {
            return array.values.map { renderedText(of: $0) }.joined()
        }
        return "\(value)"
    }

    /// Writes the result of an expression statement to the current output.
    ///
    /// If the text spans several lines, every line after the first inherits the
    /// leading white space of the line that the expression starts on, so
    /// that multi-line results line up with their surroundings.
    ///
    /// - Parameter value: The evaluated expression.
    func writeExpressionResult(_ value: any EcoreValue) async {
        let text = renderedText(of: value)
        guard text.contains("\n") else {
            await write(text)
            return
        }

        let generated = await getGeneratedText()
        let currentLine = generated.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        let indentation = String(currentLine.prefix(while: { $0 == " " || $0 == "\t" }))
        guard !indentation.isEmpty else {
            await write(text)
            return
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let indented = lines.enumerated().map { index, line in
            index == 0 || line.isEmpty ? String(line) : indentation + line
        }
        await write(indented.joined(separator: "\n"))
    }
}
