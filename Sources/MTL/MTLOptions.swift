//
//  MTLOptions.swift
//  MTL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore

/// The behaviours that a generator or an execution context follows.
///
/// Each property selects one behaviour. The default value of every property, also available as
/// ``standard``, gives the behaviour documented for this release. The ``legacy`` preset gives
/// the behaviour of version 0.6 for every template that version could run.
///
/// Pass the options to ``MTLGenerator/init(module:generationStrategy:options:serviceProviders:globals:)``
/// or ``MTLExecutionContext/init(module:generationStrategy:options:aqlContext:protectedAreaManager:serviceProviders:)``.
/// The initialisers without an `options` argument use ``legacy``.
///
/// ## Example
///
/// ```swift
/// var options = MTLOptions()
/// options.blockLineBreaks = .kept
/// let generator = MTLGenerator(module: module, generationStrategy: strategy, options: options)
/// ```
public struct MTLOptions: Sendable, Equatable, Hashable {
    /// What happens to the line break after the closing tag of a block written on one line.
    ///
    /// The default, ``MTLBlockLineBreaks/acceleo``, drops it when the line is empty once the
    /// block has run, as Acceleo 4 does.
    public var blockLineBreaks: MTLBlockLineBreaks

    /// Which arguments conform to a collection type and what a collection-typed variable holds.
    ///
    /// The default, ``MTLCollectionParameters/conforming``, accepts any collection whose
    /// elements conform to the element type of a template, query or macro parameter or of a
    /// typed `let` variable.
    public var collectionParameters: MTLCollectionParameters

    /// Whether a `let` block checks the values of its variables against their declared types.
    ///
    /// With `true`, the default, a value that does not conform to the declared type of its
    /// variable is treated as ``letTypeMismatches`` selects. With `false`, as in version 0.6,
    /// every value is bound as it is, whatever type its variable declares.
    public var checksLetTypes: Bool

    /// How a `let` block treats a value that does not conform to the declared type of its variable.
    ///
    /// The default, ``MTLLetTypeMismatches/error``, makes a mismatch a type error. The setting
    /// has no effect unless ``checksLetTypes`` is `true`.
    public var letTypeMismatches: MTLLetTypeMismatches

    /// Whether the container of each model object is looked up only once while a generator runs.
    ///
    /// With `true`, the default, the models must not change during a run except through services
    /// that declare `AQLService/modifiesModels`. With `false`, as in version 0.6, every
    /// container lookup sees the models as they are at that moment.
    public var cachesContainers: Bool

    /// How templates read structural features that have not been set.
    ///
    /// The default, `UnsetFeatureReads/defaults`, reads an unset attribute as its default value
    /// and an unset many-valued feature as an empty collection, as the Eclipse Modeling
    /// Framework does. The setting applies to the execution engine that an initialiser creates.
    public var unsetFeatureReads: UnsetFeatureReads

    /// Creates options, by default with the behaviour documented for this release.
    ///
    /// - Parameters:
    ///   - blockLineBreaks: What happens to the line break after the closing tag of a block
    ///     written on one line (default: ``MTLBlockLineBreaks/acceleo``).
    ///   - collectionParameters: Which arguments conform to a collection type and what a
    ///     collection-typed variable holds (default: ``MTLCollectionParameters/conforming``).
    ///   - checksLetTypes: Whether a `let` block checks the values of its variables against
    ///     their declared types (default: `true`).
    ///   - letTypeMismatches: How a `let` block treats a value that does not conform to the
    ///     declared type of its variable (default: ``MTLLetTypeMismatches/error``).
    ///   - cachesContainers: Whether the container of each model object is looked up only once
    ///     while a generator runs (default: `true`).
    ///   - unsetFeatureReads: How templates read structural features that have not been set
    ///     (default: `UnsetFeatureReads/defaults`).
    public init(
        blockLineBreaks: MTLBlockLineBreaks = .acceleo,
        collectionParameters: MTLCollectionParameters = .conforming,
        checksLetTypes: Bool = true,
        letTypeMismatches: MTLLetTypeMismatches = .error,
        cachesContainers: Bool = true,
        unsetFeatureReads: UnsetFeatureReads = .defaults
    ) {
        self.blockLineBreaks = blockLineBreaks
        self.collectionParameters = collectionParameters
        self.checksLetTypes = checksLetTypes
        self.letTypeMismatches = letTypeMismatches
        self.cachesContainers = cachesContainers
        self.unsetFeatureReads = unsetFeatureReads
    }

    /// The behaviour documented for this release.
    ///
    /// Every option has its default value, as for options created without arguments.
    public static let standard = MTLOptions()

    /// The behaviour of version 0.6.
    ///
    /// Line breaks after blocks written on one line are kept, collection types are matched as
    /// in version 0.6, declared `let` types are not checked, and containers are looked up
    /// afresh every time. Unset features read as their defaults.
    public static let legacy = MTLOptions(
        blockLineBreaks: .kept,
        collectionParameters: .exact,
        checksLetTypes: false,
        letTypeMismatches: .error,
        cachesContainers: false,
        unsetFeatureReads: .defaults
    )
}

/// What happens to the line break after the closing tag of a block written on one line.
///
/// A block such as `[if (c)][helper()/][/if]` may stand alone on its line. When the block has
/// run, the line it wrote may already be complete, because the output of the block ended in a
/// line break, or empty, because the block wrote nothing.
///
/// The raw value of each case is a lower-case word that can double as a command-line spelling,
/// so that a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through ``allCases``.
public enum MTLBlockLineBreaks: String, Sendable, CaseIterable, Hashable {
    /// The line break is dropped when the line is empty once the block has run, as in Acceleo 4.
    ///
    /// A one-line block around a call whose output ends a line adds no blank line, and a
    /// one-line block that writes nothing at the start of its line produces no line. Text
    /// before the block on its line, including white space, keeps the line break. This is the
    /// default.
    case acceleo

    /// The line break is always written, as in version 0.6.
    case kept
}

/// Which arguments conform to a collection type and what a collection-typed variable holds.
///
/// Template, query and macro parameters and typed `let` variables may declare a collection
/// type, such as `Sequence(String)`, `OrderedSet(ecore::EClass)` or `Collection(T)`.
///
/// The raw value of each case is a lower-case word that can double as a command-line spelling,
/// so that a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through ``allCases``.
public enum MTLCollectionParameters: String, Sendable, CaseIterable, Hashable {
    /// Any collection conforms if its elements conform to the element type.
    ///
    /// The value of a many-valued feature counts as a collection, references held as object
    /// identifiers are resolved to their objects before an overload is chosen, and a single
    /// model object conforms to a collection type of its element type, less specifically than
    /// to any other type. A collection-typed parameter or variable holds its value as a
    /// collection. Overloads are chosen by how closely the elements fit their element types.
    /// This is the default.
    case conforming

    /// Collection types are matched as in version 0.6.
    ///
    /// Only collection values of the expression language conform to a collection type, whatever
    /// their elements, arguments are passed as they were evaluated, and every parameter or
    /// variable holds its argument as it is.
    case exact
}
