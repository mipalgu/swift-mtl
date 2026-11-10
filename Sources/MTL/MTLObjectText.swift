//
//  MTLObjectText.swift
//  MTL
//
//  Created by Rene Hexel on 08/11/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase

/// The text that a template writes for a model object.
///
/// An expression such as `[person/]` whose value is a model object writes a text that stands
/// for the object. Acceleo writes what the Eclipse Modeling Framework gives the object as its
/// string: the name of its implementation class, a hash code and, for a class generated from a
/// metamodel, the values of its attributes. Neither the implementation class nor the hash code
/// exists outside the Java virtual machine, and a hash code changes from run to run, so
/// ``acceleo`` writes the name of the class of the object in their place. The text is then the
/// same for every run over the same model.
///
/// The raw value of each case is a lower-case word that can double as a command-line spelling,
/// so that a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through `allCases`.
public enum MTLObjectText: String, Sendable, CaseIterable, Hashable {
    /// An object is written as the name of its class and the values of its attributes.
    ///
    /// The values follow the class name in parentheses, as `name: value` pairs separated by
    /// commas, in the order the Eclipse Modeling Framework gives the attributes. Each class in
    /// the hierarchy of the object contributes its own group, from the most general class to
    /// the class of the object, as in `Employee (name: Ann, age: 42) (salary: 100)`. References
    /// and volatile attributes are left out, and a class without attributes is written as its
    /// name alone.
    ///
    /// An unset attribute is written as its default value, or as `<unset>` if it is a
    /// single-valued attribute that distinguishes being unset from holding its default. A
    /// value without text is written as `null`, and a many-valued attribute as a bracketed
    /// list such as `[a, b]`. An enumeration literal is written as its literal, or as its name
    /// if it has no literal. This is the default.
    case acceleo

    /// An object is written as its Swift description, as in version 0.6.
    ///
    /// The description is the one that Swift string interpolation gives the value of the
    /// object, which lists its stored properties.
    case swift
}

extension MTLObjectText {
    /// The text that this choice gives a model object.
    ///
    /// - Parameter object: The object to write.
    /// - Returns: The text that stands for the object.
    func text(of object: any EObject) -> String {
        switch self {
        case .swift:
            return "\(object)"
        case .acceleo:
            return Self.acceleoText(of: object)
        }
    }

    /// The text that ``acceleo`` gives a model object.
    ///
    /// - Parameter object: The object to write.
    /// - Returns: The class name of the object, followed by one group of attribute values for
    ///   each class in its hierarchy that declares attributes.
    private static func acceleoText(of object: any EObject) -> String {
        if let literal = object as? EEnumLiteral { return literal.literal ?? literal.name }
        guard let eClass = object.eClass as? EClass else { return object.eClass.name }
        var text = eClass.name
        var group: [String] = []
        var groupOwner: EUUID?
        for attribute in eClass.eAllAttributes where !attribute.volatile {
            if attribute.eContainerID != groupOwner, !group.isEmpty {
                text += MTLObjectTextSyntax.group(group)
                group = []
            }
            groupOwner = attribute.eContainerID
            group.append(attribute.name + MTLObjectTextSyntax.valueSeparator + valueText(of: attribute, in: object))
        }
        if !group.isEmpty { text += MTLObjectTextSyntax.group(group) }
        return text
    }

    /// The text of the value that an object holds for an attribute.
    ///
    /// - Parameters:
    ///   - attribute: The attribute to read.
    ///   - object: The object that holds the value.
    /// - Returns: The text of the stored value, of the default value of an unset attribute,
    ///   or ``MTLObjectTextSyntax/unset`` for an unset, unsettable, single-valued attribute.
    private static func valueText(of attribute: EAttribute, in object: any EObject) -> String {
        if let value = object.eGet(attribute) { return text(ofValue: value) }
        if attribute.unsettable, !attribute.isMany { return MTLObjectTextSyntax.unset }
        return text(ofValue: EcoreDefaultValue.value(for: attribute))
    }

    /// The text of an attribute value.
    ///
    /// - Parameter value: The value, or `nil` for a value without text.
    /// - Returns: The text of the value: a string as it is, an enumeration literal as its
    ///   literal, a collection as the bracketed list of the text of its elements, and any other
    ///   value as the expression language describes it.
    private static func text(ofValue value: (any EcoreValue)?) -> String {
        guard let value else { return AQLSyntax.nullText }
        if let string = value as? String { return string }
        if let literal = value as? EEnumLiteral { return literal.literal ?? literal.name }
        if let items = AQLValues.elements(of: value) {
            return MTLObjectTextSyntax.list(items.map { text(ofValue: $0) })
        }
        return AQLValues.description(of: value)
    }
}

/// The punctuation of the text that ``MTLObjectText/acceleo`` gives a model object.
///
/// The punctuation is that of the strings that the Eclipse Modeling Framework generates for
/// model objects.
enum MTLObjectTextSyntax {
    /// The text that separates an attribute name from its value.
    static let valueSeparator = ": "

    /// The text that separates the entries of a group or a list.
    static let entrySeparator = ", "

    /// The text that opens a group of attribute values, after the preceding text.
    static let groupOpening = " ("

    /// The text that closes a group of attribute values.
    static let groupClosing = ")"

    /// The text that opens a list of values.
    static let listOpening = "["

    /// The text that closes a list of values.
    static let listClosing = "]"

    /// The text of an unset attribute that distinguishes being unset from holding its default.
    static let unset = "<unset>"

    /// A group of attribute values.
    ///
    /// - Parameter entries: The `name: value` entries of the group.
    /// - Returns: The entries, separated and enclosed in parentheses.
    static func group(_ entries: [String]) -> String {
        groupOpening + entries.joined(separator: entrySeparator) + groupClosing
    }

    /// A list of values.
    ///
    /// - Parameter items: The text of the values.
    /// - Returns: The values, separated and enclosed in brackets.
    static func list(_ items: [String]) -> String {
        listOpening + items.joined(separator: entrySeparator) + listClosing
    }
}
