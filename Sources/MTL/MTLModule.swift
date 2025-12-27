//
//  MTLModule.swift
//  MTL
//
//  Created by Rene Hexel on 27/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation
import OrderedCollections

/// Represents an MTL (Model-to-Text Language) module.
///
/// An MTL module is the root container for a text generation specification, containing
/// source metamodels, templates, queries, macros, and module-level configuration.
/// MTL modules define transformations from models to text using declarative templates
/// and imperative control structures.
///
/// ## Overview
///
/// MTL modules follow a structured approach to model-to-text transformation:
/// - **Metamodels**: Reference metamodels that define the structure of input models
/// - **Templates**: Text generation units with parameters and control flow
/// - **Queries**: Side-effect-free operations for computed values
/// - **Macros**: Language extensions for pattern reuse
/// - **Module hierarchy**: Inheritance and imports for modular organization
///
/// ## Module Inheritance
///
/// MTL supports module inheritance through the `extends` mechanism, allowing
/// templates to be specialized and overridden in module hierarchies:
///
/// ```swift
/// // Base module
/// let baseModule = MTLModule(
///     name: "BaseGen",
///     metamodels: ["Model": modelPackage],
///     templates: ["generate": baseTemplate]
/// )
///
/// // Derived module (overrides base template)
/// let derivedModule = MTLModule(
///     name: "DerivedGen",
///     metamodels: ["Model": modelPackage],
///     extends: "BaseGen",
///     templates: ["generate": overridingTemplate]
/// )
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let module = MTLModule(
///     name: "ClassGenerator",
///     metamodels: ["UML": umlPackage],
///     templates: ["generateClass": classTemplate],
///     queries: ["isPublic": isPublicQuery],
///     macros: ["repeat": repeatMacro],
///     encoding: "UTF-8"
/// )
/// ```
///
/// - Note: MTL modules are designed as immutable value types to enable safe concurrent
///   processing and template execution across multiple actors.
public struct MTLModule: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the MTL module.
    ///
    /// Module names must be valid identifiers and are used for namespace resolution,
    /// inheritance, and debugging purposes during generation execution.
    public let name: String

    /// Source metamodels indexed by their namespace aliases.
    ///
    /// Source metamodels define the structure of input models that will be used
    /// during text generation. Each metamodel is associated with an alias used
    /// in MTL expressions for type references and navigation operations.
    public let metamodels: OrderedDictionary<String, EPackage>

    /// Optional parent module name for inheritance.
    ///
    /// If specified, this module extends the parent module, inheriting its
    /// templates, queries, and macros. Templates in this module can override
    /// parent templates by specifying the same name.
    public let extends: String?

    /// Imported module names for namespace composition.
    ///
    /// Imported modules make their public templates, queries, and macros
    /// available for invocation from this module without requiring full
    /// qualification.
    public let imports: [String]

    /// Templates indexed by their names.
    ///
    /// Templates define the text generation logic and can be invoked during
    /// generation execution. Templates support parameters, guards, and
    /// post-conditions for flexible and safe text generation.
    public let templates: OrderedDictionary<String, MTLTemplate>

    /// Queries indexed by their names.
    ///
    /// Queries extend AQL with custom side-effect-free operations that can be
    /// invoked from templates and other queries. They support both standalone
    /// and contextual query definitions.
    public let queries: OrderedDictionary<String, MTLQuery>

    /// Macros indexed by their names.
    ///
    /// Macros provide language extension capabilities, allowing custom control
    /// structures and pattern reuse. They can accept both regular parameters
    /// and body content parameters.
    public let macros: OrderedDictionary<String, MTLMacro>

    /// The default character encoding for generated files.
    ///
    /// Encoding specifies the character encoding used when writing generated
    /// text to files. Common values include "UTF-8", "ISO-8859-1", etc.
    public let encoding: String

    // MARK: - Initialisation

    /// Creates a new MTL module with the specified configuration.
    ///
    /// - Parameters:
    ///   - name: The module name, used for identification and inheritance
    ///   - metamodels: Source metamodels indexed by namespace aliases
    ///   - extends: Optional parent module name (default: nil)
    ///   - imports: Imported module names (default: empty)
    ///   - templates: Templates indexed by their names (default: empty)
    ///   - queries: Queries indexed by their names (default: empty)
    ///   - macros: Macros indexed by their names (default: empty)
    ///   - encoding: Default character encoding (default: "UTF-8")
    ///
    /// - Precondition: The module name must be a non-empty string
    public init(
        name: String,
        metamodels: OrderedDictionary<String, EPackage>,
        extends: String? = nil,
        imports: [String] = [],
        templates: OrderedDictionary<String, MTLTemplate> = [:],
        queries: OrderedDictionary<String, MTLQuery> = [:],
        macros: OrderedDictionary<String, MTLMacro> = [:],
        encoding: String = "UTF-8"
    ) {
        precondition(!name.isEmpty, "Module name must not be empty")

        self.name = name
        self.metamodels = metamodels
        self.extends = `extends`
        self.imports = imports
        self.templates = templates
        self.queries = queries
        self.macros = macros
        self.encoding = encoding
    }

    // MARK: - Equatable

    /// Compares two MTL modules for equality.
    ///
    /// Two modules are equal if they have the same name, metamodels, extends relationship,
    /// imports, templates, queries, macros, and encoding.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side module
    ///   - rhs: The right-hand side module
    /// - Returns: `true` if the modules are equal, `false` otherwise
    public static func == (lhs: MTLModule, rhs: MTLModule) -> Bool {
        return lhs.name == rhs.name
            && areMetamodelsEqual(lhs.metamodels, rhs.metamodels)
            && lhs.extends == rhs.extends
            && lhs.imports == rhs.imports
            && lhs.templates == rhs.templates
            && lhs.queries == rhs.queries
            && lhs.macros == rhs.macros
            && lhs.encoding == rhs.encoding
    }

    // MARK: - Hashable

    /// Hashes the essential components of the module into the given hasher.
    ///
    /// The hash value is computed from the module name, metamodel content,
    /// inheritance relationships, and all module elements using semantic
    /// hashing that ignores metamodel unique IDs.
    ///
    /// - Parameter hasher: The hasher to use when combining the components
    ///   of this instance
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(metamodels.keys.sorted())

        // Hash metamodel content semantically
        for (key, package) in metamodels.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hashEPackageSemantics(package, into: &hasher)
        }

        hasher.combine(extends)
        hasher.combine(imports.sorted())
        hasher.combine(templates.keys.sorted())
        hasher.combine(queries.keys.sorted())
        hasher.combine(macros.keys.sorted())
        hasher.combine(encoding)

        // Hash template values
        for (key, template) in templates.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hasher.combine(template)
        }

        // Hash query values
        for (key, query) in queries.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hasher.combine(query)
        }

        // Hash macro values
        for (key, macro) in macros.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hasher.combine(macro)
        }
    }
}

// MARK: - Semantic Equality Helpers

/// Compare two metamodel dictionaries for semantic equality.
///
/// This function compares metamodel dictionaries by examining their structure
/// and content while ignoring unique identifiers that may vary across instances.
///
/// - Parameters:
///   - lhs: The left-hand side metamodel dictionary
///   - rhs: The right-hand side metamodel dictionary
/// - Returns: `true` if the dictionaries are semantically equal, `false` otherwise
private func areMetamodelsEqual(
    _ lhs: OrderedDictionary<String, EPackage>,
    _ rhs: OrderedDictionary<String, EPackage>
) -> Bool {
    guard lhs.count == rhs.count else { return false }

    for (key, lhsPackage) in lhs {
        guard let rhsPackage = rhs[key] else { return false }
        if !areEPackagesEqual(lhsPackage, rhsPackage) {
            return false
        }
    }
    return true
}

/// Compare two EPackages for semantic equality (ignoring unique IDs).
///
/// This function compares EPackages based on their structural content
/// (name, URI, prefix, classifier count) rather than unique identifiers,
/// enabling meaningful equality checks across different package instances.
///
/// - Parameters:
///   - lhs: The left-hand side package
///   - rhs: The right-hand side package
/// - Returns: `true` if the packages are semantically equal, `false` otherwise
private func areEPackagesEqual(_ lhs: EPackage, _ rhs: EPackage) -> Bool {
    return lhs.name == rhs.name
        && lhs.nsURI == rhs.nsURI
        && lhs.nsPrefix == rhs.nsPrefix
        && lhs.eClassifiers.count == rhs.eClassifiers.count
        && lhs.eSubpackages.count == rhs.eSubpackages.count
}

/// Hash an EPackage based on semantic content (ignoring unique IDs).
///
/// This function computes a hash value based on the package's structural
/// content rather than unique identifiers, ensuring consistent hashing
/// across equivalent package instances.
///
/// - Parameters:
///   - package: The package to hash
///   - hasher: The hasher to use
private func hashEPackageSemantics(_ package: EPackage, into hasher: inout Hasher) {
    hasher.combine(package.name)
    hasher.combine(package.nsURI)
    hasher.combine(package.nsPrefix)
    hasher.combine(package.eClassifiers.count)
    hasher.combine(package.eSubpackages.count)
}
