//
// MTLQueryHelpers.swift
// MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation

// MARK: - Query Helper

/// A `[query]` definition of an MTL module, callable as a native function.
///
/// Hosts that evaluate their own expressions can call a helper without generating any text.
/// The first argument of ``call`` is the receiver of the query, which is its first declared
/// parameter, so that a host can map `e.render('c')` onto the query
/// `render(e : Expression, lang : String)`.
public struct MTLQueryHelper: Sendable {
    /// The name of the query.
    public let name: String

    /// The declared types of the query parameters, receiver first.
    public let parameterTypes: [String]

    /// The declared return type of the query.
    public let returnType: String

    /// The number of arguments the query takes, including the receiver.
    public var arity: Int { parameterTypes.count }

    /// Runs the query.
    ///
    /// The closure takes the receiver followed by the remaining arguments, and throws
    /// ``MTLExecutionError`` if the number of arguments differs from ``arity`` or the query fails.
    public let call: @MainActor @Sendable ([(any EcoreValue)?]) async throws -> (any EcoreValue)?

    /// Creates a helper.
    ///
    /// - Parameters:
    ///   - name: The name of the query.
    ///   - parameterTypes: The declared parameter types, receiver first.
    ///   - returnType: The declared return type.
    ///   - call: The function that runs the query.
    public init(
        name: String,
        parameterTypes: [String],
        returnType: String,
        call: @escaping @MainActor @Sendable ([(any EcoreValue)?]) async throws -> (any EcoreValue)?
    ) {
        self.name = name
        self.parameterTypes = parameterTypes
        self.returnType = returnType
        self.call = call
    }
}

// MARK: - Query Helpers

/// Exposes the queries of MTL modules to other hosts.
///
/// ## Example
///
/// ```swift
/// let module = try await MTLParser(searchPaths: libraries).parse(url)
/// let helpers = MTLQueryHelpers.helpers(for: module)
/// let text = try await MTLQueryHelpers.call("render", arguments: [element, "c"], among: helpers)
/// ```
public enum MTLQueryHelpers {

    /// Lists the queries of a module and of its imported modules as helpers.
    ///
    /// All queries of the module itself are listed, overloads included, followed by the public
    /// queries of each imported module. Queries run on one generator, so queries of the module
    /// can call each other and the queries that it imports.
    ///
    /// - Parameters:
    ///   - module: The module whose queries are exposed.
    ///   - generator: The generator that runs the queries, or `nil` to use a new generator for
    ///     the module that discards any generated text. Pass a generator to share its global
    ///     variables and services, such as ``MTLParameterServices``, with the queries.
    /// - Returns: One helper per query, in declaration order.
    @MainActor
    public static func helpers(for module: MTLModule, generator: MTLGenerator? = nil) -> [MTLQueryHelper] {
        let runner = generator ?? MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        var queries = allQueries(of: module)
        for imported in module.importedModules {
            queries += allQueries(of: imported).filter { $0.visibility == .public }
        }
        return queries.map { query in
            MTLQueryHelper(
                name: query.name,
                parameterTypes: query.parameters.map(\.type),
                returnType: query.returnType
            ) { arguments in
                try await runner.executeQuery(query, arguments: arguments)
            }
        }
    }

    /// Calls the helper that best fits a name and arguments.
    ///
    /// Among helpers of the same name and arity, the one whose parameter types match the
    /// arguments most specifically is called.
    ///
    /// - Parameters:
    ///   - name: The query name.
    ///   - arguments: The receiver followed by the remaining arguments.
    ///   - helpers: The helpers to choose from.
    /// - Returns: The result of the query, or `nil` for null.
    /// - Throws: ``MTLExecutionError/queryNotFound(_:)`` if no helper has the name, and
    ///   ``MTLExecutionError/invalidOperation(_:)`` if none takes this number of arguments or
    ///   has parameter types that fit the arguments.
    @MainActor
    public static func call(
        _ name: String, arguments: [(any EcoreValue)?], among helpers: [MTLQueryHelper]
    ) async throws -> (any EcoreValue)? {
        let named = helpers.filter { $0.name == name }
        guard !named.isEmpty else { throw MTLExecutionError.queryNotFound(name) }
        let sameArity = named.filter { $0.arity == arguments.count }
        guard !sameArity.isEmpty else {
            let arities = Set(named.map(\.arity)).sorted().map(String.init).joined(separator: ", ")
            throw MTLExecutionError.invalidOperation(
                "Query '\(name)' expects \(arities) arguments, got \(arguments.count)")
        }
        var best: (helper: MTLQueryHelper, distance: Int)?
        for helper in sameArity {
            var total = 0
            var fits = true
            for (argument, type) in zip(arguments, helper.parameterTypes) {
                guard let distance = MTLTypeMatcher.distance(of: argument, to: type) else {
                    fits = false
                    break
                }
                total += distance
            }
            if fits, best == nil || total < best!.distance { best = (helper, total) }
        }
        guard let chosen = best?.helper else {
            throw MTLExecutionError.invalidOperation(
                "No query '\(name)' accepts arguments of the given types")
        }
        return try await chosen.call(arguments)
    }

    /// Lists the queries declared in a module, overloads included.
    private static func allQueries(of module: MTLModule) -> [MTLQuery] {
        Array(module.queries.values) + module.queryOverloads
    }
}

// MARK: - Query Services

/// Offers the queries of an MTL module as AQL services.
///
/// AQL-based hosts can register the services to call the queries by name. A query with
/// parameters `(e : T, a : U)` can be called as `e.name(a)`, `e->name(a)` and `name(e, a)`.
/// A query without parameters can be called as `name()`.
///
/// ## Example
///
/// ```swift
/// let services = MTLQueryServices(module: module)
/// ```
public struct MTLQueryServices: AQLServiceProvider {
    /// The helpers that the services call.
    public let helpers: [MTLQueryHelper]

    /// Creates the services for a module and its imports.
    ///
    /// - Parameters:
    ///   - module: The module whose queries are offered.
    ///   - generator: The generator that runs the queries, or `nil` for a new generator that
    ///     discards generated text; see ``MTLQueryHelpers/helpers(for:generator:)``.
    @MainActor
    public init(module: MTLModule, generator: MTLGenerator? = nil) {
        self.helpers = MTLQueryHelpers.helpers(for: module, generator: generator)
    }

    /// The services offered: one standalone and one receiver form per query name and arity.
    public var services: [AQLService] {
        let helpers = self.helpers
        var forms = Set<String>()
        var result: [AQLService] = []
        for helper in helpers {
            let name = helper.name
            let arity = helper.arity
            if forms.insert("\(name)/\(arity)").inserted {
                result.append(
                    AQLService(name, receiver: .standalone, arity: arity) { call in
                        try await MTLQueryHelpers.call(name, arguments: call.arguments, among: helpers)
                    })
            }
            if arity > 0, forms.insert("\(name).\(arity - 1)").inserted {
                result.append(
                    AQLService(name, receiver: .any, arity: arity - 1) { call in
                        try await MTLQueryHelpers.call(
                            name, arguments: [call.receiver] + call.arguments, among: helpers)
                    })
            }
        }
        return result
    }
}
