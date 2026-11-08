//
//  MTLObjectTextTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import MTL

/// Tests for the text that a template writes for a model object.
@Suite("MTL Object Text")
@MainActor
struct MTLObjectTextTests {

    /// A module whose main template writes the given body for its argument `x`.
    private static func module(_ body: String) -> String {
        "[module m('u')/]\n[template main(x : OclAny)]\(body)[/template]\n"
    }

    /// The string data type.
    private static let string = EDataType(name: EcoreDataType.eString.rawValue)

    /// The integer data type.
    private static let integer = EDataType(name: EcoreDataType.eInt.rawValue)

    /// A class `Person` with a name and an age.
    private static let person = EClass(
        name: "Person",
        eStructuralFeatures: [
            EAttribute(name: "name", eType: string),
            EAttribute(name: "age", eType: integer),
        ])

    /// A class `Employee` that extends ``person`` with a salary.
    private static let employee = EClass(
        name: "Employee", eSuperTypes: [person],
        eStructuralFeatures: [EAttribute(name: "salary", eType: integer)])

    /// Creates a person with the given name and age.
    private static func makePerson(name: String = "Alice", age: Int = 42) -> DynamicEObject {
        var object = DynamicEObject(eClass: person)
        object.eSet("name", value: name)
        object.eSet("age", value: age)
        return object
    }

    /// Runs a template body for an argument and returns the main output.
    private func output(
        _ body: String, for argument: any EcoreValue, options: MTLOptions? = nil
    ) async throws -> String {
        try await MTLTestSupport.output(Self.module(body), arguments: [argument], options: options)
    }

    // MARK: - Options

    @Test("Objects are written as Acceleo writes them by default and in their Swift form in the legacy options")
    func optionValues() {
        #expect(MTLOptions().objectText == .acceleo)
        #expect(MTLOptions.standard.objectText == .acceleo)
        #expect(MTLOptions.legacy.objectText == .swift)
        #expect(MTLOptions(semantics: .legacy).objectText == .swift)
        #expect(MTLOptions(objectText: .swift) != .standard)
    }

    @Test("The object text values are spelt for the command line")
    func spellings() {
        #expect(MTLObjectText.allCases.map(\.rawValue) == ["acceleo", "swift"])
        #expect(MTLObjectText(rawValue: "swift") == .swift)
        #expect(MTLObjectText(rawValue: "debug") == nil)
    }

    // MARK: - Standard Semantics

    @Test("An object is written as its class name and the values of its attributes")
    func attributes() async throws {
        #expect(try await output("[x/]", for: Self.makePerson(), options: .standard) == "Person (name: Alice, age: 42)")
    }

    @Test("The attributes of each class in the hierarchy are grouped, most general first")
    func inheritedAttributes() async throws {
        var object = DynamicEObject(eClass: Self.employee)
        object.eSet("name", value: "Bob")
        object.eSet("salary", value: 100)
        #expect(
            try await output("[x/]", for: object, options: .standard)
                == "Employee (name: Bob, age: 0) (salary: 100)")
    }

    @Test("Unset attributes are written as their defaults, or as unset if they are unsettable")
    func unsetAttributes() async throws {
        let thing = EClass(
            name: "Thing",
            eStructuralFeatures: [
                EAttribute(name: "label", eType: Self.string),
                EAttribute(name: "limit", eType: Self.integer, defaultValueLiteral: "7"),
                EAttribute(name: "note", eType: Self.string, unsettable: true),
                EAttribute(name: "tags", eType: Self.string, upperBound: -1),
            ])
        #expect(
            try await output("[x/]", for: DynamicEObject(eClass: thing), options: .standard)
                == "Thing (label: null, limit: 7, note: <unset>, tags: [])")
    }

    @Test("Many-valued attributes are written as bracketed lists")
    func manyValuedAttribute() async throws {
        let tagged = EClass(
            name: "Tagged", eStructuralFeatures: [EAttribute(name: "tags", eType: Self.string, upperBound: -1)])
        var object = DynamicEObject(eClass: tagged)
        object.eSet("tags", value: EcoreValueArray(["a", "b"]))
        #expect(try await output("[x/]", for: object, options: .standard) == "Tagged (tags: [a, b])")
    }

    @Test("References and volatile attributes are left out")
    func referencesAndVolatileAttributes() async throws {
        let target = EClass(name: "Target")
        let source = EClass(
            name: "Source",
            eStructuralFeatures: [
                EAttribute(name: "id", eType: Self.string),
                EAttribute(name: "computed", eType: Self.string, volatile: true),
                EReference(name: "target", eType: target),
            ])
        var object = DynamicEObject(eClass: source)
        object.eSet("id", value: "s1")
        #expect(try await output("[x/]", for: object, options: .standard) == "Source (id: s1)")
    }

    @Test("An object without attributes is written as its class name")
    func noAttributes() async throws {
        let object = DynamicEObject(eClass: EClass(name: "Node"))
        #expect(try await output("[x/]", for: object, options: .standard) == "Node")
    }

    @Test("An enumeration literal is written as its literal")
    func enumerationLiteral() async throws {
        let literal = EEnumLiteral(name: "red", value: 0, literal: "RED")
        #expect(try await output("[x/]", for: literal, options: .standard) == "RED")
        let unnamed = EEnumLiteral(name: "green", value: 1)
        #expect(try await output("[x/]", for: unnamed, options: .standard) == "green")
    }

    @Test("A class of a metamodel is written with the attributes of its metaclass")
    func metamodelClass() async throws {
        let text = try await output("[x/]", for: Self.person, options: .standard)
        #expect(text.hasPrefix("EClass (name: Person)"))
        #expect(text.hasSuffix("(abstract: false, interface: false)"))
    }

    @Test("The objects of a collection are written one after the other")
    func collectionOfObjects() async throws {
        let text = "Person (name: Alice, age: 42)"
        #expect(try await output("[Sequence{x, x}/]", for: Self.makePerson(), options: .standard) == text + text)
    }

    @Test("A collected object is emitted as its text")
    func collectedObject() async throws {
        let body = "[collect ('people', x)/][emit ('people')][item/][/emit]"
        #expect(
            try await output(body, for: Self.makePerson(), options: .standard)
                == "Person (name: Alice, age: 42)")
    }

    @Test("Values other than objects are written as before")
    func otherValues() async throws {
        #expect(try await output("[x/]", for: "text", options: .standard) == "text")
        #expect(try await output("[x/]", for: 42, options: .standard) == "42")
        #expect(try await output("[x/]", for: 1.5, options: .standard) == "1.5")
        #expect(try await output("[x/]", for: true, options: .standard) == "true")
    }

    // MARK: - Legacy Semantics

    @Test("The legacy options write the Swift description of an object, as in version 0.6")
    func legacyDescription() async throws {
        let object = Self.makePerson()
        #expect(try await output("[x/]", for: object, options: .legacy) == "\(object)")
        #expect(try await output("[x/]", for: object) == "\(object)")
        #expect(try await output("[x/]", for: object, options: MTLOptions(objectText: .swift)) == "\(object)")
    }

    @Test("The legacy options write the Swift description of each object of a collection")
    func legacyCollection() async throws {
        let object = Self.makePerson()
        #expect(try await output("[Sequence{x, x}/]", for: object, options: .legacy) == "\(object)\(object)")
    }

    @Test("The legacy options collect the Swift description of an object")
    func legacyCollectedObject() async throws {
        let object = Self.makePerson()
        let body = "[collect ('people', x)/][emit ('people')][item/][/emit]"
        #expect(try await output(body, for: object, options: .legacy) == "\(object)")
    }

    @Test("The legacy options write an enumeration literal in its Swift form")
    func legacyEnumerationLiteral() async throws {
        let literal = EEnumLiteral(name: "red", value: 0, literal: "RED")
        #expect(try await output("[x/]", for: literal, options: .legacy) == "\(literal)")
    }
}
