//
//  MTLCollectionParameterTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import MTL

/// A small model of actions whose many-valued features are passed to collection parameters.
///
/// Every action has many-valued `names` and `counts` attributes and a many-valued
/// `statements` containment reference. The actions differ in how the statements are stored.
@MainActor
private struct ActionModel {

    /// The name of the package of the model, and of the model alias.
    nonisolated static let packageName = "p"

    /// The namespace URI of the package.
    nonisolated static let namespace = "http://example.org/actions"

    /// The metaclass of statements.
    let statement: EClass

    /// The metaclass of actions.
    let action: EClass

    /// The package holding both metaclasses.
    let package: EPackage

    /// The resource holding every object of the model.
    let resource = Resource()

    /// Creates the metamodel.
    init() {
        let string = EDataType(name: EcoreDataType.eString.rawValue)
        let integer = EDataType(name: EcoreDataType.eInt.rawValue)
        var statement = EClass(name: "Statement")
        statement.eStructuralFeatures.append(EAttribute(name: "text", eType: string))
        var action = EClass(name: "Action")
        action.eStructuralFeatures.append(EAttribute(name: "names", eType: string, upperBound: -1))
        action.eStructuralFeatures.append(EAttribute(name: "counts", eType: integer, upperBound: -1))
        action.eStructuralFeatures.append(
            EReference(name: "statements", eType: statement, upperBound: -1, containment: true))
        self.statement = statement
        self.action = action
        self.package = EPackage(
            name: Self.packageName, nsURI: Self.namespace, nsPrefix: Self.packageName,
            eClassifiers: [statement, action])
    }

    /// Adds a statement with the given text to the resource.
    ///
    /// - Parameter text: The text of the statement.
    /// - Returns: The statement.
    func makeStatement(_ text: String) async -> DynamicEObject {
        var object = DynamicEObject(eClass: statement)
        object.eSet("text", value: text)
        await resource.add(object)
        return object
    }

    /// Adds an action whose statements are stored as the given value.
    ///
    /// - Parameter store: Produces the stored value of `statements` from the statement objects.
    /// - Returns: The action, with names `a`, `b`, `c`, counts 1 and 2 and statements `x` and `y`.
    func makeAction(
        storing store: ([DynamicEObject]) -> any EcoreValue = { statements in statements.map(\.id) }
    ) async -> DynamicEObject {
        let statements = [await makeStatement("x"), await makeStatement("y")]
        var object = DynamicEObject(eClass: action)
        object.eSet("names", value: ["a", "b", "c"])
        object.eSet("counts", value: [1, 2])
        object.eSet("statements", value: store(statements))
        await resource.add(object)
        return object
    }

    /// Runs the `main` template of a module on an object of the model.
    ///
    /// - Parameters:
    ///   - source: The module source.
    ///   - argument: The argument of the `main` template.
    /// - Returns: The standard output.
    func output(_ source: String, on argument: any EObject) async throws -> String {
        try await Self.output(source, on: argument, in: resource)
    }

    /// Runs the `main` template of a module on an object of a resource.
    ///
    /// - Parameters:
    ///   - source: The module source.
    ///   - argument: The argument of the `main` template.
    ///   - resource: The resource holding the model.
    /// - Returns: The standard output.
    static func output(_ source: String, on argument: any EObject, in resource: Resource) async throws -> String {
        let module = try await MTLTestSupport.parse(source)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.generate(mainTemplate: "main", arguments: [argument], models: [packageName: resource])
        return await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? ""
    }
}

/// Tests for passing collections, in particular the values of many-valued features, to
/// parameters of a collection type.
@Suite("MTL Collection Parameters")
struct MTLCollectionParameterTests {

    /// The module header shared by the test modules.
    private static let header = "[module m('\(ActionModel.namespace)')/]\n"

    /// The collection kinds that a many-valued feature conforms to.
    private static let collectionKinds = ["Sequence", "OrderedSet", "Bag", "Set", "Collection"]

    // MARK: Attributes

    @Test("A many-valued string attribute is a collection of strings", arguments: collectionKinds)
    @MainActor
    func manyValuedAttribute(kind: String) async throws {
        let model = ActionModel()
        let action = await model.makeAction()
        let output = try await model.output(Self.header + """
            [template main(a : p::Action)][show(a.names)/][/template]
            [template show(xs : \(kind)(String))][xs->size()/][if (xs->includes('b'))]+b[/if][/template]
            """, on: action)
        #expect(output == "3+b")
    }

    @Test("A many-valued attribute behaves as the declared sequence in the template")
    @MainActor
    func boundAttributeIsSequence() async throws {
        let model = ActionModel()
        let action = await model.makeAction()
        let output = try await model.output(Self.header + """
            [template main(a : p::Action)][show(a.names)/][/template]
            [template show(xs : Sequence(String))][xs->first()/][xs->last()/][xs->at(2)/][xs/][/template]
            """, on: action)
        #expect(output == "acbabc")
    }

    @Test("A single string does not conform to a sequence of strings")
    @MainActor
    func singleStringIsRejected() async throws {
        let model = ActionModel()
        let action = await model.makeAction()
        await #expect(throws: MTLExecutionError.self) {
            try await model.output(Self.header + """
                [template main(a : p::Action)][show(a.names->first())/][/template]
                [template show(xs : Sequence(String))]strings[/template]
                """, on: action)
        }
    }

    @Test("A typed query parameter accepts a many-valued attribute")
    @MainActor
    func queryParameter() async throws {
        let model = ActionModel()
        let action = await model.makeAction()
        let output = try await model.output(Self.header + """
            [query count(xs : Sequence(String)) : Integer = xs->size()/]
            [query total(xs : Sequence(Integer)) : Integer = xs->sum()/]
            [template main(a : p::Action)][count(a.names)/],[total(a.counts)/][/template]
            """, on: action)
        #expect(output == "3,3")
    }

    @Test("A typed for variable iterates over a many-valued attribute")
    @MainActor
    func forOverAttribute() async throws {
        let model = ActionModel()
        let action = await model.makeAction()
        let output = try await model.output(Self.header + """
            [template main(a : p::Action)][for (n : String | a.names) separator(',')][n/][/for][/template]
            """, on: action)
        #expect(output == "a,b,c")
    }

    // MARK: References

    /// How a many-valued containment may hold its statements.
    enum Storage: String, CaseIterable, CustomTestStringConvertible {
        case identifiers, wrappedIdentifiers, objects, wrappedObjects

        /// Converts the statement objects into the stored value.
        func store(_ statements: [DynamicEObject]) -> any EcoreValue {
            switch self {
            case .identifiers: return statements.map(\.id)
            case .wrappedIdentifiers: return EcoreValueArray(statements.map(\.id))
            case .objects: return statements
            case .wrappedObjects: return EcoreValueArray(statements)
            }
        }

        var testDescription: String { rawValue }
    }

    @Test("A many-valued containment is a sequence of its element type", arguments: Storage.allCases)
    @MainActor
    func manyValuedReference(storage: Storage) async throws {
        let model = ActionModel()
        let action = await model.makeAction(storing: storage.store)
        let output = try await model.output(Self.header + """
            [template main(a : p::Action)][body(a.statements)/][/template]
            [template body(ss : Sequence(Statement))][ss->size()/]:[ss->first().text/]:[for (s : Statement | ss)][s.text/][/for][/template]
            """, on: action)
        #expect(output == "2:x:xy")
    }

    @Test("A typed query parameter accepts a many-valued containment", arguments: Storage.allCases)
    @MainActor
    func queryReferenceParameter(storage: Storage) async throws {
        let model = ActionModel()
        let action = await model.makeAction(storing: storage.store)
        let output = try await model.output(Self.header + """
            [query texts(ss : Sequence(p::Statement)) : Sequence(String) = ss->collect(s | s.text)/]
            [template main(a : p::Action)][texts(a.statements)/][/template]
            """, on: action)
        #expect(output == "xy")
    }

    @Test("A single statement is the only element of a sequence of statements")
    @MainActor
    func singleObjectIsSingleton() async throws {
        let model = ActionModel()
        let action = await model.makeAction()
        let output = try await model.output(Self.header + """
            [template main(a : p::Action)][body(a.statements->first())/][/template]
            [template body(ss : Sequence(Statement))][ss->size()/]:[ss->first().text/][/template]
            """, on: action)
        #expect(output == "1:x")
    }

    @Test("A typed let variable holds a single statement as the only element of a sequence")
    @MainActor
    func typedLetHoldsSingletonSequence() async throws {
        let model = ActionModel()
        let action = await model.makeAction()
        let output = try await model.output(Self.header + """
            [template main(a : p::Action)][let ss : Sequence(Statement) = a.statements->first()][ss.size()/]:[ss.first().text/][/let],[let names : Sequence(String) = a.names][names.size()/][/let][/template]
            """, on: action)
        #expect(output == "1:x,3")
    }

    @Test("A single statement prefers any other overload to a sequence of statements")
    @MainActor
    func singleObjectPrefersDirectOverload() async throws {
        let model = ActionModel()
        let action = await model.makeAction()
        let output = try await model.output(Self.header + """
            [template main(a : p::Action)][body(a.statements->first())/],[other(a.statements->first())/][/template]
            [template body(ss : Sequence(Statement))]sequence[/template]
            [template body(s : Statement)]statement[/template]
            [template other(ss : Sequence(Statement))]sequence[/template]
            [template other(s : OclAny)]any[/template]
            """, on: action)
        #expect(output == "statement,any")
    }

    @Test("Single values that are no statements do not conform to a sequence of statements")
    @MainActor
    func singleValueOfOtherTypeIsRejected() async throws {
        let model = ActionModel()
        let action = await model.makeAction()
        for argument in ["a", "a.names->first()"] {
            await #expect(throws: MTLExecutionError.self) {
                try await model.output(Self.header + """
                    [template main(a : p::Action)][body(\(argument))/][/template]
                    [template body(ss : Sequence(Statement))]statements[/template]
                    """, on: action)
            }
        }
    }

    @Test("A many-valued containment loaded from XMI with one element is a sequence")
    @MainActor
    func loadedSingleElement() async throws {
        let model = ActionModel()
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(model.package, uri: ActionModel.namespace)
        let resource = try await XMIParser(resourceSet: resourceSet).parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <p:Action xmlns:xmi="http://www.omg.org/XMI" xmlns:p="\(ActionModel.namespace)" xmi:version="2.0">
              <names>a</names>
              <statements text="x"/>
            </p:Action>
            """, uri: "memory:/single.xmi")
        let action = try #require(await resource.getRootObjects().first)
        let output = try await ActionModel.output(Self.header + """
            [template main(a : p::Action)][body(a.statements)/],[show(a.names)/][/template]
            [template body(ss : Sequence(Statement))][ss->size()/]:[ss->first().text/][/template]
            [template show(xs : Sequence(String))][xs->size()/]:[xs->first()/][/template]
            """, on: action, in: resource)
        #expect(output == "1:x,1:a")
    }

    @Test("A many-valued containment loaded from XMI with several elements is a sequence")
    @MainActor
    func loadedSeveralElements() async throws {
        let model = ActionModel()
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(model.package, uri: ActionModel.namespace)
        let resource = try await XMIParser(resourceSet: resourceSet).parse("""
            <?xml version="1.0" encoding="UTF-8"?>
            <p:Action xmlns:xmi="http://www.omg.org/XMI" xmlns:p="\(ActionModel.namespace)" xmi:version="2.0">
              <names>a</names>
              <names>b</names>
              <statements text="x"/>
              <statements text="y"/>
            </p:Action>
            """, uri: "memory:/several.xmi")
        let action = try #require(await resource.getRootObjects().first)
        let output = try await ActionModel.output(Self.header + """
            [template main(a : p::Action)][body(a.statements)/],[show(a.names)/][/template]
            [template body(ss : Sequence(Statement))][ss->size()/]:[ss->first().text/][/template]
            [template show(xs : Sequence(String))][xs->size()/]:[xs->first()/][/template]
            """, on: action, in: resource)
        #expect(output == "2:x,2:a")
    }

    // MARK: Query Helpers

    @Test("A query helper accepts an array for a collection parameter")
    @MainActor
    func helperAcceptsArray() async throws {
        let module = try await MTLTestSupport.parse(Self.header + """
            [query count(xs : Sequence(String)) : Integer = xs->size()/]
            """)
        let helpers = MTLQueryHelpers.helpers(for: module)
        let result = try await MTLQueryHelpers.call("count", arguments: [["a", "b"]], among: helpers)
        #expect(result as? Int == 2)
        await #expect(throws: MTLExecutionError.self) {
            try await MTLQueryHelpers.call("count", arguments: ["a"], among: helpers)
        }
    }

    // MARK: Type Matching

    @Test("Arrays of values conform to collection types only if their elements do")
    func matcherAcceptsArrays() {
        let distance = MTLTypeMatcher.collectionDistance
        #expect(MTLTypeMatcher.distance(of: ["a"], to: "Sequence(String)") == distance)
        #expect(MTLTypeMatcher.distance(of: [1], to: "OrderedSet(Integer)") == distance)
        #expect(MTLTypeMatcher.distance(of: [true], to: "Collection(Boolean)") == distance)
        #expect(MTLTypeMatcher.distance(of: ["a"], to: "Sequence") == distance)
        #expect(MTLTypeMatcher.distance(of: [1], to: "Sequence(String)") == nil)
        #expect(MTLTypeMatcher.distance(of: [String](), to: "Bag(Integer)") == distance)
        #expect(MTLTypeMatcher.distance(of: "abc", to: "Sequence(String)") == nil)
    }

    @Test("A single model object conforms to a collection type of its own type, least specifically")
    @MainActor
    func matcherAcceptsSingleObject() throws {
        let model = ActionModel()
        let statement = DynamicEObject(eClass: model.statement)
        let singleton = MTLTypeMatcher.singletonDistance
        #expect(MTLTypeMatcher.distance(of: statement, to: "Sequence(Statement)") == singleton)
        #expect(MTLTypeMatcher.distance(of: statement, to: "OrderedSet(p::Statement)") == singleton)
        #expect(MTLTypeMatcher.distance(of: statement, to: "Sequence(Action)") == nil)
        let any = try #require(MTLTypeMatcher.distance(of: statement, to: MTLSyntax.anyType))
        let collection = try #require(MTLTypeMatcher.distance(of: statement, to: "Collection"))
        #expect(any < collection)
    }

    @Test("A parameter of a collection type holds a collection value")
    @MainActor
    func boundValues() throws {
        let model = ActionModel()
        let statement = DynamicEObject(eClass: model.statement)
        let array = try #require(MTLTypeMatcher.boundValue(of: ["a", "b"], to: "Sequence(String)") as? EcoreValueArray)
        #expect(array.values.count == 2)
        let single = try #require(MTLTypeMatcher.boundValue(of: statement, to: "Sequence(Statement)") as? EcoreValueArray)
        #expect((single.values.first as? DynamicEObject)?.id == statement.id)
        #expect(MTLTypeMatcher.boundValue(of: nil, to: "Sequence(String)") == nil)
        #expect(MTLTypeMatcher.boundValue(of: ["a"], to: "OclAny") is [String])
    }
}
