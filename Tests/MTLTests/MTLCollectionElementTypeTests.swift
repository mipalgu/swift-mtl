//
//  MTLCollectionElementTypeTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import MTL

/// A small model of blocks of statements, some of which are assignments.
///
/// Every block has many-valued `names` and `counts` attributes and a many-valued
/// `statements` containment reference. An `Assignment` is a `Statement`, which is
/// an `Element`.
@MainActor
private struct BlockModel {

    /// The name of the package of the model, and of the model alias.
    nonisolated static let packageName = "p"

    /// The namespace URI of the package.
    nonisolated static let namespace = "http://example.org/blocks"

    /// The module header shared by the test modules.
    nonisolated static let header = "[module m('\(namespace)')/]\n"

    /// The root metaclass of statements.
    let element: EClass

    /// The metaclass of statements.
    let statement: EClass

    /// The metaclass of assignments, a subclass of statements.
    let assignment: EClass

    /// The metaclass of blocks.
    let block: EClass

    /// The resource holding every object of the model.
    let resource = Resource()

    /// Creates the metamodel.
    init() {
        let string = EDataType(name: EcoreDataType.eString.rawValue)
        let integer = EDataType(name: EcoreDataType.eInt.rawValue)
        var element = EClass(name: "Element")
        element.eStructuralFeatures.append(EAttribute(name: "text", eType: string))
        let statement = EClass(name: "Statement", eSuperTypes: [element])
        let assignment = EClass(name: "Assignment", eSuperTypes: [statement])
        var block = EClass(name: "Block")
        block.eStructuralFeatures.append(EAttribute(name: "names", eType: string, upperBound: -1))
        block.eStructuralFeatures.append(EAttribute(name: "counts", eType: integer, upperBound: -1))
        block.eStructuralFeatures.append(
            EReference(name: "statements", eType: statement, upperBound: -1, containment: true))
        self.element = element
        self.statement = statement
        self.assignment = assignment
        self.block = block
    }

    /// Adds an object of the given metaclass with the given text to the resource.
    ///
    /// - Parameters:
    ///   - eClass: The metaclass of the object.
    ///   - text: The text of the object.
    /// - Returns: The object.
    func make(_ eClass: EClass, _ text: String) async -> DynamicEObject {
        var object = DynamicEObject(eClass: eClass)
        object.eSet("text", value: text)
        await resource.add(object)
        return object
    }

    /// Adds a block whose statements have the given metaclasses.
    ///
    /// - Parameter kinds: The metaclass of each statement; the statements are named `s0`, `s1`, ...
    /// - Returns: The block, with names `a`, `b` and counts 1, 2.
    func makeBlock(_ kinds: [EClass]) async -> DynamicEObject {
        var statements: [DynamicEObject] = []
        for (index, kind) in kinds.enumerated() {
            statements.append(await make(kind, "s\(index)"))
        }
        var object = DynamicEObject(eClass: block)
        object.eSet("names", value: ["a", "b"])
        object.eSet("counts", value: [1, 2])
        object.eSet("statements", value: statements.map(\.id))
        await resource.add(object)
        return object
    }

    /// Runs the `main` template of a module on a block.
    ///
    /// - Parameters:
    ///   - body: The module source after the header.
    ///   - argument: The argument of the `main` template.
    /// - Returns: The standard output.
    func output(_ body: String, on argument: any EObject) async throws -> String {
        let module = try await MTLTestSupport.parse(Self.header + body)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.generate(
            mainTemplate: "main", arguments: [argument], models: [Self.packageName: resource])
        return await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? ""
    }
}

/// Tests for checking the element types of collection arguments against the element
/// types of collection parameters and typed `let` variables.
@Suite("MTL Collection Element Types")
struct MTLCollectionElementTypeTests {

    /// Two overloads of `show`, by element type, in either order of declaration.
    private static let stringAndIntegerOverloads = [
        """
        [template show(xs : Sequence(String))]strings[/template]
        [template show(xs : Sequence(Integer))]integers[/template]
        """,
        """
        [template show(xs : Sequence(Integer))]integers[/template]
        [template show(xs : Sequence(String))]strings[/template]
        """
    ]

    // MARK: Overloads by Element Type

    @Test("Overloads by element type tell strings from integers", arguments: stringAndIntegerOverloads)
    @MainActor
    func overloadByPrimitiveElementType(overloads: String) async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        let output = try await model.output("""
            [template main(b : p::Block)][show(b.names)/],[show(b.counts)/],[show(Sequence{'x'})/],[show(Sequence{3})/][/template]
            \(overloads)
            """, on: block)
        #expect(output == "strings,integers,strings,integers")
    }

    @Test("Query overloads by element type tell strings from integers")
    @MainActor
    func queryOverloadByElementType() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        let output = try await model.output("""
            [query kind(xs : Sequence(Integer)) : String = 'integers'/]
            [query kind(xs : Sequence(String)) : String = 'strings'/]
            [template main(b : p::Block)][kind(b.names)/],[kind(b.counts)/][/template]
            """, on: block)
        #expect(output == "strings,integers")
    }

    @Test("Overloads by element type prefer the most specific metaclass")
    @MainActor
    func overloadByMetaclass() async throws {
        let model = BlockModel()
        let assignments = await model.makeBlock([model.assignment, model.assignment])
        let mixed = await model.makeBlock([model.assignment, model.statement])
        let overloads = """
            [template kind(ss : Sequence(Element))]elements[/template]
            [template kind(ss : Sequence(Assignment))]assignments[/template]
            [template kind(ss : Sequence(p::Statement))]statements[/template]
            """
        let main = "[template main(b : p::Block)][kind(b.statements)/][/template]\n"
        #expect(try await model.output(main + overloads, on: assignments) == "assignments")
        #expect(try await model.output(main + overloads, on: mixed) == "statements")
    }

    @Test("The least specific element, not the size, decides the distance of a collection")
    @MainActor
    func leastSpecificElementDecides() async throws {
        let model = BlockModel()
        let mixed = await model.makeBlock([model.assignment, model.assignment, model.assignment])
        let output = try await model.output("""
            [template main(b : p::Block)][kind(b.statements, b.statements->first())/][/template]
            [template kind(ss : Sequence(Element), s : Assignment)]elements and assignment[/template]
            [template kind(ss : Sequence(Statement), s : Element)]statements and element[/template]
            """, on: mixed)
        #expect(output == "elements and assignment")
    }

    // MARK: Rejection

    @Test("A template rejects a collection whose elements do not conform")
    @MainActor
    func templateRejectsMismatchedElements() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        for argument in ["b.names", "b.counts->including('x')", "b.statements", "Sequence{b}"] {
            await #expect(throws: MTLExecutionError.self, "\(argument)") {
                try await model.output("""
                    [template main(b : p::Block)][show(\(argument))/][/template]
                    [template show(xs : Sequence(Integer))]integers[/template]
                    """, on: block)
            }
        }
    }

    @Test("A collection of statements does not conform to a sequence of assignments")
    @MainActor
    func templateRejectsSupertypeElements() async throws {
        let model = BlockModel()
        let mixed = await model.makeBlock([model.assignment, model.statement])
        await #expect(throws: MTLExecutionError.self) {
            try await model.output("""
                [template main(b : p::Block)][show(b.statements)/][/template]
                [template show(ss : Sequence(Assignment))]assignments[/template]
                """, on: mixed)
        }
    }

    @Test("A query rejects a collection whose elements do not conform")
    @MainActor
    func queryRejectsMismatchedElements() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        await #expect(throws: MTLExecutionError.self) {
            try await model.output("""
                [query total(xs : Sequence(Integer)) : Integer = xs->sum()/]
                [template main(b : p::Block)][total(b.names)/][/template]
                """, on: block)
        }
    }

    @Test("A macro rejects a collection whose elements do not conform")
    @MainActor
    func macroRejectsMismatchedElements() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        let macro = "[macro tally(xs : Sequence(Integer))][xs->size()/][/macro]\n"
        #expect(try await model.output(macro + """
            [template main(b : p::Block)][tally(b.counts)/][/template]
            """, on: block) == "2")
        await #expect(throws: MTLExecutionError.self) {
            try await model.output(macro + """
                [template main(b : p::Block)][tally(b.names)/][/template]
                """, on: block)
        }
    }

    @Test("A macro and a template of the same name are told apart by element type")
    @MainActor
    func macroAndTemplateByElementType() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        let output = try await model.output("""
            [macro show(xs : Sequence(Integer))]integers[/macro]
            [template show(xs : Sequence(String))]strings[/template]
            [template main(b : p::Block)][show(b.names)/],[show(b.counts)/][/template]
            """, on: block)
        #expect(output == "strings,integers")
    }

    @Test("A collection whose elements do not conform falls back to a less specific overload")
    @MainActor
    func mismatchFallsBackToOclAny() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        let output = try await model.output("""
            [template main(b : p::Block)][show(b.names)/],[show(b.counts)/][/template]
            [template show(xs : Sequence(Integer))]integers[/template]
            [template show(x : OclAny)]any[/template]
            """, on: block)
        #expect(output == "any,integers")
    }

    @Test("A collection prefers a collection of any elements to any value")
    @MainActor
    func collectionOfAnyBeatsAny() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        let output = try await model.output("""
            [template main(b : p::Block)][show(b.names)/],[show(b.counts)/],[show('x')/][/template]
            [template show(x : OclAny)]any[/template]
            [template show(xs : Sequence(OclAny))]collection[/template]
            [template show(xs : Sequence(String))]strings[/template]
            """, on: block)
        #expect(output == "strings,collection,any")
    }

    // MARK: Query Helpers

    @Test("A query helper checks the element types of collection arguments")
    @MainActor
    func helperChecksElementTypes() async throws {
        let module = try await MTLTestSupport.parse(BlockModel.header + """
            [query kind(xs : Sequence(String)) : String = 'strings'/]
            [query kind(xs : Sequence(Integer)) : String = 'integers'/]
            [query count(xs : Sequence(String)) : Integer = xs->size()/]
            """)
        let helpers = MTLQueryHelpers.helpers(for: module)
        #expect(try await MTLQueryHelpers.call("kind", arguments: [["a"]], among: helpers) as? String == "strings")
        #expect(try await MTLQueryHelpers.call("kind", arguments: [[1, 2]], among: helpers) as? String == "integers")
        #expect(
            try await MTLQueryHelpers.call("kind", arguments: [EcoreValueArray([1])], among: helpers) as? String
                == "integers")
        await #expect(throws: MTLExecutionError.self) {
            try await MTLQueryHelpers.call("count", arguments: [[1, 2]], among: helpers)
        }
        await #expect(throws: MTLExecutionError.self) {
            try await MTLQueryHelpers.call("count", arguments: [EcoreValueArray(["a", 1])], among: helpers)
        }
    }

    // MARK: Empty Collections

    @Test("An empty collection conforms to every collection type")
    @MainActor
    func emptyCollectionConforms() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([])
        let output = try await model.output("""
            [template main(b : p::Block)][tally(b.statements)/],[tally(Sequence{})/],[total(OrderedSet{})/],[nested(Sequence{})/][/template]
            [template tally(ss : Sequence(Assignment))][ss->size()/][/template]
            [query total(xs : OrderedSet(Integer)) : Integer = xs->size()/]
            [template nested(xss : Sequence(Sequence(String)))][xss->size()/][/template]
            """, on: block)
        #expect(output == "0,0,0,0")
    }

    @Test(
        "An empty collection takes the first of equally specific overloads",
        arguments: zip(stringAndIntegerOverloads, ["strings", "integers"]))
    @MainActor
    func emptyCollectionTakesFirstOverload(overloads: String, expected: String) async throws {
        let model = BlockModel()
        let block = await model.makeBlock([])
        let output = try await model.output("""
            [template main(b : p::Block)][show(Sequence{})/][/template]
            \(overloads)
            [template show(x : OclAny)]any[/template]
            """, on: block)
        #expect(output == expected)
    }

    // MARK: Nested Collections

    @Test("Nested collections are checked element by element")
    @MainActor
    func nestedCollections() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        let overloads = """
            [template show(xss : Sequence(Sequence(String)))]strings[/template]
            [template show(xss : Sequence(Sequence(Integer)))]integers[/template]
            """
        let output = try await model.output("""
            [template main(b : p::Block)][show(Sequence{b.names, Sequence{'c'}})/],[show(Sequence{b.counts})/][/template]
            \(overloads)
            """, on: block)
        #expect(output == "strings,integers")
        for argument in ["Sequence{b.names, b.counts}", "b.names"] {
            await #expect(throws: MTLExecutionError.self, "\(argument)") {
                try await model.output("""
                    [template main(b : p::Block)][show(\(argument))/][/template]
                    \(overloads)
                    """, on: block)
            }
        }
    }

    // MARK: Null Elements

    @Test("Null elements conform to every element type")
    @MainActor
    func nullElements() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.statement])
        let output = try await model.output("""
            [template main(b : p::Block)][show(Sequence{'a', null, 'b'})/],[show(Sequence{null, 3})/],[show(Sequence{null})/][/template]
            [template show(xs : Sequence(String))]strings[xs->size()/][/template]
            [template show(xs : Sequence(Integer))]integers[xs->size()/][/template]
            """, on: block)
        #expect(output == "strings2,integers1,strings0")
    }

    // MARK: Single Objects

    @Test("A single object still conforms to a collection of its type, most specifically")
    @MainActor
    func singleObjectFallback() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.assignment, model.statement])
        let output = try await model.output("""
            [template main(b : p::Block)][kind(b.statements->first())/],[kind(b.statements->last())/][/template]
            [template kind(ss : Sequence(Statement))]statements[ss->size()/][/template]
            [template kind(ss : Sequence(Assignment))]assignments[ss->size()/][/template]
            """, on: block)
        #expect(output == "assignments1,statements1")
    }

    @Test("A single object is not an element of a nested collection")
    @MainActor
    func singleObjectNotNested() throws {
        let model = BlockModel()
        let statement = DynamicEObject(eClass: model.statement)
        #expect(MTLTypeMatcher.distance(of: [statement], to: "Sequence(Sequence(Statement))") == nil)
        #expect(MTLTypeMatcher.distance(of: statement, to: "Sequence(Sequence(Statement))") == nil)
    }

    // MARK: Typed Let

    @Test("A typed let checks the element types of a collection")
    @MainActor
    func typedLetChecksElements() async throws {
        let model = BlockModel()
        let block = await model.makeBlock([model.assignment, model.statement])
        let output = try await model.output("""
            [template main(b : p::Block)][let ns : OrderedSet(ecore::EString) = b.names, ss : Sequence(p::Element) = b.statements, xss : Sequence(Sequence(Integer)) = Sequence{b.counts}, es : Sequence(Assignment) = Sequence{}][ns->size()/][ss->size()/][xss->size()/][es->size()/][/let][/template]
            """, on: block)
        #expect(output == "2210")
        let mismatches = [
            "Sequence(Integer) = b.names",
            "Sequence(String) = Sequence{1}",
            "Sequence(Assignment) = b.statements",
            "Sequence(Sequence(String)) = Sequence{b.counts}",
            "Sequence(Sequence(String)) = b.names"
        ]
        for mismatch in mismatches {
            do {
                _ = try await model.output("""
                    [template main(b : p::Block)][let x : \(mismatch)][x/][/let][/template]
                    """, on: block)
                Issue.record("Expected a type error for \(mismatch)")
            } catch let error as MTLExecutionError {
                guard case .typeError(let message) = error else {
                    Issue.record("Unexpected error \(error) for \(mismatch)")
                    continue
                }
                #expect(message.contains("'x'"))
            }
        }
    }

    // MARK: Type Matching

    @Test("A collection matches with its collection distance plus its least specific element")
    func matcherScoresElements() {
        let collection = MTLTypeMatcher.collectionDistance
        #expect(MTLTypeMatcher.distance(of: ["a", "b"], to: "Sequence(String)") == collection)
        #expect(MTLTypeMatcher.distance(of: ["a"], to: "Sequence(ecore::EString)") == collection)
        #expect(MTLTypeMatcher.distance(of: [1], to: "OrderedSet(EInt)") == collection)
        #expect(MTLTypeMatcher.distance(of: EcoreValueArray([1, 2]), to: "Sequence(Real)") == collection + 1)
        #expect(MTLTypeMatcher.distance(of: EcoreValueArray([1.5, 2]), to: "Sequence(Real)") == collection + 1)
        #expect(MTLTypeMatcher.distance(of: EcoreValueArray([1.5]), to: "Sequence(Integer)") == nil)
        #expect(MTLTypeMatcher.distance(of: EcoreValueArray(["a", 1]), to: "Sequence(String)") == nil)
        #expect(MTLTypeMatcher.distance(of: ["a"], to: "Bag(Statement)") == nil)
    }

    @Test("Metaclass elements are scored by their distance up the hierarchy")
    @MainActor
    func matcherScoresMetaclassElements() {
        let model = BlockModel()
        let statement = DynamicEObject(eClass: model.statement)
        let assignment = DynamicEObject(eClass: model.assignment)
        let mixed = EcoreValueArray([assignment, statement])
        let collection = MTLTypeMatcher.collectionDistance
        #expect(MTLTypeMatcher.distance(of: [assignment], to: "Sequence(Assignment)") == collection)
        #expect(MTLTypeMatcher.distance(of: mixed, to: "Sequence(p::Statement)") == collection + 1)
        #expect(MTLTypeMatcher.distance(of: mixed, to: "Sequence(Element)") == collection + 2)
        #expect(MTLTypeMatcher.distance(of: mixed, to: "Sequence(Assignment)") == nil)
        #expect(
            MTLTypeMatcher.distance(of: mixed, to: "Sequence(EObject)")
                == collection + MTLTypeMatcher.unverifiableDistance)
    }

    @Test("Elements that cannot be checked at run time are unverifiable")
    func matcherUnverifiableElements() {
        let packages = [EPackage(name: "a"), EPackage(name: "b")]
        let collection = MTLTypeMatcher.collectionDistance
        #expect(MTLTypeMatcher.distance(of: packages, to: "Sequence(EPackage)") == collection)
        #expect(
            MTLTypeMatcher.distance(of: packages, to: "Sequence(ecore::ENamedElement)")
                == collection + MTLTypeMatcher.unverifiableDistance)
    }

    @Test("A bare collection type and a collection of OclAny accept any elements")
    func matcherAcceptsAnyElements() throws {
        let mixed = EcoreValueArray(["a", 1, true])
        let collection = MTLTypeMatcher.collectionDistance
        #expect(MTLTypeMatcher.distance(of: mixed, to: "Sequence") == collection)
        #expect(MTLTypeMatcher.distance(of: mixed, to: "Collection") == collection)
        let anyElements = try #require(MTLTypeMatcher.distance(of: mixed, to: "Sequence(OclAny)"))
        let strings = try #require(MTLTypeMatcher.distance(of: ["a"], to: "Sequence(String)"))
        let stringsAsAny = try #require(MTLTypeMatcher.distance(of: ["a"], to: "Sequence(OclAny)"))
        #expect(strings < stringsAsAny)
        #expect(anyElements < MTLTypeMatcher.unspecificDistance)
        let nestedAny = try #require(MTLTypeMatcher.distance(of: [mixed], to: "Sequence(Sequence(OclAny))"))
        #expect(nestedAny < MTLTypeMatcher.unspecificDistance)
    }

    @Test("An empty collection matches every collection type with the collection distance")
    func matcherAcceptsEmptyCollections() {
        let collection = MTLTypeMatcher.collectionDistance
        for type in ["Sequence(String)", "OrderedSet(Statement)", "Sequence(Sequence(Integer))", "Sequence(OclAny)"] {
            #expect(MTLTypeMatcher.distance(of: EcoreValueArray([]), to: type) == collection, "\(type)")
        }
    }

    @Test("Nested collections are scored by their nesting")
    func matcherScoresNestedCollections() {
        let collection = MTLTypeMatcher.collectionDistance
        let nested = EcoreValueArray([EcoreValueArray(["a"]), ["b", "c"]])
        #expect(MTLTypeMatcher.distance(of: nested, to: "Sequence(Sequence(String))") == 2 * collection)
        #expect(MTLTypeMatcher.distance(of: nested, to: "Sequence(OrderedSet(ecore::EString))") == 2 * collection)
        #expect(MTLTypeMatcher.distance(of: nested, to: "Sequence(Sequence)") == 2 * collection)
        #expect(MTLTypeMatcher.distance(of: nested, to: "Sequence(Sequence(Integer))") == nil)
        #expect(MTLTypeMatcher.distance(of: nested, to: "Sequence(String)") == nil)
        #expect(MTLTypeMatcher.distance(of: ["a"], to: "Sequence(Sequence(String))") == nil)
    }
}
