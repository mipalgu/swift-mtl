//
//  MTLExpressions.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation

// MARK: - Runtime Handle

/// A weak reference to a runtime, held in a class so that it can be shared by value.
@MainActor
final class MTLRuntimeReference: Sendable {

    /// The runtime, or `nil` once it has been released.
    weak var runtime: MTLExecutionContext?

    /// Creates a reference to the given runtime.
    ///
    /// - Parameter runtime: The runtime to refer to.
    init(runtime: MTLExecutionContext) {
        self.runtime = runtime
    }
}

/// The value through which an expression finds the runtime that is evaluating it.
///
/// The handle is stored in the expression evaluator under a reserved variable
/// name when the runtime is created. It is an ordinary `EcoreValue`, so no
/// change to the evaluator is needed.
struct MTLRuntimeHandle: EcoreValue {

    /// The shared weak reference to the runtime.
    let reference: MTLRuntimeReference

    /// Creates a handle for a runtime.
    ///
    /// - Parameter runtime: The runtime the handle stands for.
    @MainActor
    init(runtime: MTLExecutionContext) {
        self.reference = MTLRuntimeReference(runtime: runtime)
    }

    static func == (lhs: MTLRuntimeHandle, rhs: MTLRuntimeHandle) -> Bool {
        lhs.reference === rhs.reference
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(reference))
    }
}

// MARK: - Invocation Expression

/// A call of the form `name(args)` or `receiver.name(args)` in an expression.
///
/// At run time the call is resolved in this order: templates, queries, and
/// macros of the current module (including its parent modules), then those of
/// imported modules, and finally the AQL library and services, which are
/// represented by the ``fallback`` call. Overloads are told apart by the
/// number and dynamic types of the arguments; the receiver, if any, counts as
/// the first argument.
public struct MTLInvocationExpression: AQLExpression {

    /// The name of the template, query, macro, or library operation.
    public let name: String

    /// The receiver written before the dot, or the implicit receiver.
    ///
    /// `nil` for a call without receiver.
    public let receiver: (any AQLExpression)?

    /// The arguments inside the parentheses.
    public let arguments: [any AQLExpression]

    /// The call that the AQL library evaluates when no template, query, or macro applies.
    public let fallback: AQLCallExpression

    /// Creates an invocation expression.
    ///
    /// - Parameters:
    ///   - name: The name being invoked.
    ///   - receiver: The receiver, if the call is written `receiver.name(...)`.
    ///   - arguments: The arguments.
    ///   - fallback: The AQL call to evaluate if no module element applies.
    public init(
        name: String,
        receiver: (any AQLExpression)?,
        arguments: [any AQLExpression],
        fallback: AQLCallExpression
    ) {
        self.name = name
        self.receiver = receiver
        self.arguments = arguments
        self.fallback = fallback
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        let handle = (try? await context.getVariable(MTLSyntax.runtimeContextVariable)) as? MTLRuntimeHandle
        guard let runtime = handle?.reference.runtime else {
            return try await fallback.evaluate(in: context)
        }
        return try await runtime.evaluate(self)
    }
}

// MARK: - Lambda Expression

/// An iterator-style argument of the form `(x : T | body)` for an operation without a dedicated node.
///
/// The released AQL library has dedicated expression nodes only for a fixed
/// set of iterating operations. For every other operation the parser keeps
/// the iterator and the body in this node so that an AQL integration can
/// evaluate them. Evaluating the node itself is an error.
public struct MTLLambdaExpression: AQLExpression {

    /// The name of the iterator variable.
    public let iterator: String

    /// The declared type of the iterator variable, if any.
    public let iteratorType: String?

    /// The body evaluated once per element.
    public let body: any AQLExpression

    /// Creates a lambda expression.
    ///
    /// - Parameters:
    ///   - iterator: The iterator variable name.
    ///   - iteratorType: The declared iterator type, if any.
    ///   - body: The body expression.
    public init(iterator: String, iteratorType: String? = nil, body: any AQLExpression) {
        self.iterator = iterator
        self.iteratorType = iteratorType
        self.body = body
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        throw AQLExecutionError.invalidOperation(
            "The iterator expression '\(iterator) | ...' can only be used as an operation argument")
    }
}

// MARK: - Collection Literal Expression

/// A collection literal such as `Sequence{1, 2, 3}` or `OrderedSet{}`.
///
/// Evaluates to an `EcoreValueArray` holding the values of its elements in
/// order. Sets and ordered sets drop duplicate elements.
public struct MTLCollectionLiteralExpression: AQLExpression {

    /// The collection kind written before the braces (`Sequence`, `OrderedSet`, `Set`, `Bag`).
    public let kind: String

    /// The element expressions in order.
    public let elements: [any AQLExpression]

    /// Creates a collection literal.
    ///
    /// - Parameters:
    ///   - kind: The collection kind.
    ///   - elements: The element expressions.
    public init(kind: String, elements: [any AQLExpression]) {
        self.kind = kind
        self.elements = elements
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        var values: [any EcoreValue] = []
        let unique = kind == "Set" || kind == "OrderedSet"
        for element in elements {
            guard let value = try await element.evaluate(in: context) else { continue }
            if unique, values.contains(where: { $0.hashValue == value.hashValue && AnyHashable($0) == AnyHashable(value) }) {
                continue
            }
            values.append(value)
        }
        return EcoreValueArray(values)
    }
}
