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

    /// The namespace URIs of the metamodels declared in the module header.
    ///
    /// The header `[module name('uri1', 'uri2')/]` lists the metamodels the
    /// module is written against. The URIs are bound to registered packages by
    /// their `nsURI` when the module is executed against models.
    public let metamodelURIs: [String]

    /// Further templates that share a name with an entry of ``templates``.
    ///
    /// Templates may be overloaded by parameter types. The first template of a
    /// given name is kept in ``templates``; all others are listed here in
    /// declaration order. Use ``templates(named:)`` to see all of them.
    public let templateOverloads: [MTLTemplate]

    /// Further queries that share a name with an entry of ``queries``.
    ///
    /// The first query of a given name is kept in ``queries``; all others are
    /// listed here in declaration order. Use ``queries(named:)`` to see all of
    /// them.
    public let queryOverloads: [MTLQuery]

    /// The location of the file the module was loaded from, if any.
    ///
    /// Imported modules are located relative to this file first.
    public let location: URL?

    /// The modules named by ``imports``, once they have been loaded.
    ///
    /// Empty until the module has been linked with ``linking(imports:extending:)``
    /// (which `MTLParser.parse(_:)` and `MTLModuleLoader` do).
    public let importedModules: [MTLModule]

    /// The module named by ``extends``, once it has been loaded.
    ///
    /// Held in an array of zero or one element so that the value type can
    /// contain itself. Use ``extendedModule`` to read it.
    private let linkedExtends: [MTLModule]

    /// The tagged-block merge configuration declared with `[merge (...)/]`.
    ///
    /// When present, generated files that already exist are merged with the
    /// new text instead of being overwritten.
    public let mergeConfiguration: MTLMergeConfiguration?

    /// The layout conversion declared with `[layout (...)/]`.
    ///
    /// When present, generated files are converted to the declared indentation
    /// and opener placement, unless the generator options supply their own layout.
    public let layoutConfiguration: MTLLayoutConfiguration?

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
    ///   - metamodelURIs: Namespace URIs of the declared metamodels (default: empty)
    ///   - templateOverloads: Templates that overload a name in `templates` (default: empty)
    ///   - queryOverloads: Queries that overload a name in `queries` (default: empty)
    ///   - location: The file the module was loaded from (default: nil)
    ///   - importedModules: The loaded imports (default: empty)
    ///   - extendedModule: The loaded parent module (default: nil)
    ///   - mergeConfiguration: Tagged-block merge configuration (default: nil)
    ///   - layoutConfiguration: Layout conversion (default: nil)
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
        encoding: String = "UTF-8",
        metamodelURIs: [String] = [],
        templateOverloads: [MTLTemplate] = [],
        queryOverloads: [MTLQuery] = [],
        location: URL? = nil,
        importedModules: [MTLModule] = [],
        extendedModule: MTLModule? = nil,
        mergeConfiguration: MTLMergeConfiguration? = nil,
        layoutConfiguration: MTLLayoutConfiguration? = nil
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
        self.mergeConfiguration = mergeConfiguration
        self.layoutConfiguration = layoutConfiguration
        self.metamodelURIs = metamodelURIs
        self.templateOverloads = templateOverloads
        self.queryOverloads = queryOverloads
        self.location = location
        self.importedModules = importedModules
        self.linkedExtends = extendedModule.map { [$0] } ?? []
    }

    // MARK: - Linking

    /// The loaded parent module, if the module extends one and it has been linked.
    public var extendedModule: MTLModule? {
        linkedExtends.first
    }

    /// Returns a copy of the module with its imports and parent module attached.
    ///
    /// - Parameters:
    ///   - imports: The loaded modules named by ``imports``.
    ///   - extendedModule: The loaded module named by ``extends``, if any.
    /// - Returns: A module that is identical except for the attached modules.
    public func linking(imports: [MTLModule], extending extendedModule: MTLModule?) -> MTLModule {
        rebuilt(location: location, imports: imports, extending: extendedModule)
    }

    /// The metamodel URIs of the module header that no bound package satisfies.
    ///
    /// Before ``binding(to:)`` is called this lists every URI of the header.
    public var unboundMetamodelURIs: [String] {
        metamodelURIs.filter { uri in !metamodels.values.contains { $0.nsURI == uri } }
    }

    /// Returns a copy of the module with its metamodel URIs bound to registered packages.
    ///
    /// Each URI of the module header is matched against the `nsURI` of the
    /// given packages and their subpackages. A matching package is added to
    /// ``metamodels`` under the package name. URIs without a matching package
    /// stay listed in ``unboundMetamodelURIs``.
    ///
    /// - Parameter packages: The registered packages, for example those of the loaded models.
    /// - Returns: A module whose ``metamodels`` hold the packages that match the header.
    public func binding(to packages: [EPackage]) -> MTLModule {
        func flattened(_ package: EPackage) -> [EPackage] {
            [package] + package.eSubpackages.flatMap(flattened)
        }
        let candidates = packages.flatMap(flattened)
        var bound = metamodels
        for uri in metamodelURIs {
            if let package = candidates.first(where: { $0.nsURI == uri }) {
                bound[package.name] = package
            }
        }
        return rebuilt(location: location, imports: importedModules, extending: extendedModule, metamodels: bound)
    }

    /// Returns a copy of the module that records where it was loaded from.
    ///
    /// - Parameter url: The file the module was loaded from.
    /// - Returns: A module that is identical except for its location.
    public func located(at url: URL?) -> MTLModule {
        rebuilt(location: url, imports: importedModules, extending: extendedModule)
    }

    /// Copies the module with a different location and linked modules.
    private func rebuilt(
        location: URL?,
        imports: [MTLModule],
        extending extendedModule: MTLModule?,
        metamodels: OrderedDictionary<String, EPackage>? = nil
    ) -> MTLModule {
        MTLModule(
            name: name,
            metamodels: metamodels ?? self.metamodels,
            extends: extends,
            imports: self.imports,
            templates: templates,
            queries: queries,
            macros: macros,
            encoding: encoding,
            metamodelURIs: metamodelURIs,
            templateOverloads: templateOverloads,
            queryOverloads: queryOverloads,
            location: location,
            importedModules: imports,
            extendedModule: extendedModule,
            mergeConfiguration: mergeConfiguration,
            layoutConfiguration: layoutConfiguration
        )
    }

    /// Returns every template of the given name declared in this module.
    ///
    /// - Parameter name: The template name.
    /// - Returns: The template in ``templates`` followed by its overloads, in declaration order.
    public func templates(named name: String) -> [MTLTemplate] {
        (templates[name].map { [$0] } ?? []) + templateOverloads.filter { $0.name == name }
    }

    /// Returns every query of the given name declared in this module.
    ///
    /// - Parameter name: The query name.
    /// - Returns: The query in ``queries`` followed by its overloads, in declaration order.
    public func queries(named name: String) -> [MTLQuery] {
        (queries[name].map { [$0] } ?? []) + queryOverloads.filter { $0.name == name }
    }

    /// Whether two modules denote the same module declaration.
    ///
    /// Modules are the same if they have the same name and were loaded from
    /// the same location (or both have no location).
    ///
    /// - Parameter other: The module to compare with.
    /// - Returns: `true` if both denote the same declaration.
    public func isSameModule(as other: MTLModule) -> Bool {
        name == other.name && location == other.location
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
            && lhs.metamodelURIs == rhs.metamodelURIs
            && lhs.templateOverloads == rhs.templateOverloads
            && lhs.queryOverloads == rhs.queryOverloads
            && lhs.importedModules == rhs.importedModules
            && lhs.extendedModule == rhs.extendedModule
            && lhs.mergeConfiguration == rhs.mergeConfiguration
            && lhs.layoutConfiguration == rhs.layoutConfiguration
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
        hasher.combine(metamodelURIs)
        hasher.combine(templateOverloads)
        hasher.combine(queryOverloads)
        hasher.combine(importedModules)
        hasher.combine(extendedModule)
        hasher.combine(mergeConfiguration)
        hasher.combine(layoutConfiguration)

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
