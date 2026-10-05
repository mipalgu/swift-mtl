//
//  MTLDeferredBlocks.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation
import OrderedCollections

// MARK: - Deferred State

/// A deferred emit block, waiting for the file body to complete.
struct MTLDeferredEmit {

    /// The emit statement to render.
    let statement: MTLEmitStatement

    /// The name of the collected set to render.
    let setName: String

    /// The variables visible where the emit block appears.
    let variables: [String: (any EcoreValue)?]
}

/// The collected sets and pending emit blocks of one output file.
struct MTLDeferredState {

    /// The collected values per set, in insertion order without duplicates.
    var sets: OrderedDictionary<String, OrderedSet<String>> = [:]

    /// The emit blocks whose placeholders are in the file buffer, by identifier.
    var emits: [Int: MTLDeferredEmit] = [:]

    /// The identifier of the next emit block.
    var nextEmitIdentifier = 0

    /// The protected areas known before the file was scanned, restored when it closes.
    var protectedAreasBeforeScan: [String: MTLProtectedAreaManager.ProtectedAreaContent]?

    /// The URL of the file as written in the `file` block.
    var fileURL = ""

    /// The per-file options of the `file` block.
    var fileOptions = MTLFileOptions()

    /// Builds the placeholder text for an emit block.
    static func placeholder(for identifier: Int) -> String {
        "\(MTLDeferredBlockNames.placeholderOpen)\(identifier)\(MTLDeferredBlockNames.placeholderClose)"
    }
}

// MARK: - Collect Statement

/// A statement that adds values to a named set for the current file.
///
/// Written `[collect ('setName', expression)/]`. The expression evaluates to
/// a string or to a collection of strings. Values are added to the set in
/// insertion order and duplicates are ignored. The set belongs to the
/// enclosing `[file]` block, or to the main output outside of any file.
///
/// ## Example
///
/// ```swift
/// let collect = MTLCollectStatement(
///     setName: MTLExpression(AQLLiteralExpression(value: "imports")),
///     value: MTLExpression(AQLLiteralExpression(value: "java.util.List")))
/// ```
public struct MTLCollectStatement: MTLStatement {
    /// Where the construct was written, if it was parsed from source text.
    public let origin: SourceOrigin

    /// The expression that names the set.
    public let setName: MTLExpression

    /// The expression that yields the value or values to add.
    public let value: MTLExpression

    /// Collect statements produce no text and are single-line.
    public let multiLines: Bool

    /// Creates a collect statement.
    ///
    /// - Parameters:
    ///   - setName: The expression that names the set.
    ///   - value: The expression that yields the value or values to add.
    ///   - multiLines: Whether this statement spans multiple lines (default: false).
    ///   - origin: Where the construct was written, if known (default: none).
    public init(
        setName: MTLExpression, value: MTLExpression, multiLines: Bool = false,
        origin: SourceOrigin = .init()
    ) {
        self.origin = origin
        self.setName = setName
        self.value = value
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        let name = try await MTLDeferredSupport.name(of: setName, in: context)
        let result = try await value.evaluate(in: context)
        context.collect(MTLDeferredSupport.strings(from: result), into: name)
    }
}

// MARK: - Emit Statement

/// A statement that marks where a collected set is rendered.
///
/// Written `[emit ('setName') in(order) separator(text) once]...[/emit]`; all
/// clauses after the name are optional and may appear in any order. When the
/// enclosing file body is complete, the block is rendered, so collects that
/// occur after the emit position are included.
///
/// By default the block is rendered once per element of the set. Inside the
/// block the variable `item` (see ``MTLDeferredBlockNames/itemVariable``) is
/// bound to the current element and the variable `items` (see
/// ``MTLDeferredBlockNames/itemsVariable``) to the whole collection. The
/// `separator` text is written between elements. An empty set renders
/// nothing. Emit blocks cannot be nested.
///
/// The `in` clause supplies an expression, evaluated with `items` bound to
/// the collected values in insertion order, that yields the elements to
/// render and their order. A template uses it to sort, group or filter, for
/// example `in(items->sortedBy(s | s))`.
///
/// The `once` clause renders the block a single time with `items` bound to
/// the (possibly reordered) collection and `item` left unbound, so that the
/// body can iterate with its own `[for]` statement.
///
/// ## Example
///
/// ```swift
/// let emit = MTLEmitStatement(
///     setName: MTLExpression(AQLLiteralExpression(value: "imports")),
///     separator: MTLExpression(AQLLiteralExpression(value: "\n")),
///     body: MTLBlock(statements: [MTLTextStatement(value: "import ")], inlined: true))
/// ```
public struct MTLEmitStatement: MTLStatement {
    /// Where the construct was written, if it was parsed from source text.
    public let origin: SourceOrigin

    /// The expression that names the set.
    public let setName: MTLExpression

    /// The optional expression that yields the text between elements.
    public let separator: MTLExpression?

    /// The optional expression that yields the elements to render, in order.
    public let order: MTLExpression?

    /// Whether the block is rendered once for the whole collection.
    public let rendersOnce: Bool

    /// The block rendered for each element.
    public let body: MTLBlock

    /// Whether this statement spans multiple lines.
    public let multiLines: Bool

    /// Creates an emit statement.
    ///
    /// - Parameters:
    ///   - setName: The expression that names the set.
    ///   - separator: The expression that yields the text between elements (default: `nil`).
    ///   - order: The expression that yields the elements to render (default: `nil`).
    ///   - rendersOnce: Whether to render once for the whole collection (default: `false`).
    ///   - body: The block rendered for each element.
    ///   - multiLines: Whether this statement spans multiple lines (default: true).
    ///   - origin: Where the construct was written, if known (default: none).
    public init(
        setName: MTLExpression, separator: MTLExpression? = nil, order: MTLExpression? = nil,
        rendersOnce: Bool = false, body: MTLBlock, multiLines: Bool = true,
        origin: SourceOrigin = .init()
    ) {
        self.origin = origin
        self.setName = setName
        self.separator = separator
        self.order = order
        self.rendersOnce = rendersOnce
        self.body = body
        self.multiLines = multiLines
    }

    @MainActor
    public func execute(in context: MTLExecutionContext) async throws {
        let name = try await MTLDeferredSupport.name(of: setName, in: context)
        try await context.registerEmit(self, setName: name)
    }
}

// MARK: - Collected Expression

/// An expression that reads the current content of a collected set.
///
/// Written `collected('setName')`. It evaluates to the collection of the
/// values collected so far for the current file, in insertion order, or to
/// an empty collection if nothing has been collected. Templates use it for
/// checks such as short-name clashes before emitting.
public struct MTLCollectedExpression: AQLExpression {
    /// Where the construct was written, if it was parsed from source text.
    public let origin: SourceOrigin

    /// The expression that names the set.
    public let setName: any AQLExpression

    /// Creates a collected expression.
    ///
    /// - Parameter setName: The expression that names the set.
    public init(setName: any AQLExpression, origin: SourceOrigin = .init()) {
        self.origin = origin
        self.setName = setName
    }

    @MainActor
    public func evaluate(in context: AQLExecutionContext) async throws -> (any EcoreValue)? {
        let nameValue = try await setName.evaluate(in: context)
        guard let name = nameValue as? String else {
            throw AQLExecutionError.typeError("The name of a collected set must be a string")
        }
        let variable = MTLDeferredBlockNames.collectedVariablePrefix + name
        if let values = try? await context.getVariable(variable) {
            return values
        }
        return EcoreValueArray([])
    }
}

// MARK: - Support

/// Helpers shared by the deferred block statements.
enum MTLDeferredSupport {

    /// Evaluates an expression that must yield a set name.
    @MainActor
    static func name(of expression: MTLExpression, in context: MTLExecutionContext) async throws
        -> String
    {
        guard let name = try await expression.evaluate(in: context) as? String else {
            throw MTLExecutionError.typeError("The name of a collected set must be a string")
        }
        return name
    }

    /// Converts a value into a list of values; `nil` yields nothing and a scalar yields itself.
    static func values(from value: (any EcoreValue)?) -> [any EcoreValue] {
        guard let value else { return [] }
        if let array = value as? EcoreValueArray { return array.values }
        if let array = value as? [any EcoreValue] { return array }
        return [value]
    }

    /// Flattens a value into the strings to collect; `nil` yields nothing.
    static func strings(from value: (any EcoreValue)?) -> [String] {
        guard let value else { return [] }
        if let array = value as? EcoreValueArray {
            return array.values.flatMap { strings(from: $0) }
        }
        if let array = value as? [any EcoreValue] {
            return array.flatMap { strings(from: $0) }
        }
        if let string = value as? String { return [string] }
        return ["\(value)"]
    }
}
