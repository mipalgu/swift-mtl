//
//  MTLIndentationTests.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Testing
@testable import MTL

@Suite("MTL Indentation Tests")
struct MTLIndentationTests {

    // MARK: - Basic Indentation

    @Test("Default indentation with spaces")
    func testDefaultIndentation() {
        let indent = MTLIndentation()
        #expect(indent.level == 0)
        #expect(indent.indentString == "    ")
        #expect(indent.asString == "")
    }

    @Test("Indentation increment")
    func testIncrement() {
        let indent = MTLIndentation()
        let incremented = indent.increment()
        #expect(incremented.level == 1)
        #expect(incremented.asString == "    ")

        let twice = incremented.increment()
        #expect(twice.level == 2)
        #expect(twice.asString == "        ")
    }

    @Test("Indentation decrement")
    func testDecrement() {
        let indent = MTLIndentation(level: 2, indentString: "    ")
        let decremented = indent.decrement()
        #expect(decremented.level == 1)
        #expect(decremented.asString == "    ")

        let twice = decremented.decrement()
        #expect(twice.level == 0)
        #expect(twice.asString == "")
    }

    @Test("Decrement doesn't go below zero")
    func testDecrementMin() {
        let indent = MTLIndentation(level: 0, indentString: "    ")
        let decremented = indent.decrement()
        #expect(decremented.level == 0)
        #expect(decremented.asString == "")
    }

    // MARK: - Custom Indentation Strings

    @Test("Tab indentation")
    func testTabIndentation() {
        let indent = MTLIndentation(level: 0, indentString: "\t")
        #expect(indent.indentString == "\t")

        let incremented = indent.increment()
        #expect(incremented.asString == "\t")

        let twice = incremented.increment()
        #expect(twice.asString == "\t\t")
    }

    @Test("Two-space indentation")
    func testTwoSpaceIndentation() {
        let indent = MTLIndentation(level: 0, indentString: "  ")
        let incremented = indent.increment()
        #expect(incremented.asString == "  ")

        let twice = incremented.increment()
        #expect(twice.asString == "    ")
    }

    // MARK: - Equality and Hashing

    @Test("Indentation equality")
    func testEquality() {
        let indent1 = MTLIndentation(level: 2, indentString: "    ")
        let indent2 = MTLIndentation(level: 2, indentString: "    ")
        let indent3 = MTLIndentation(level: 1, indentString: "    ")
        let indent4 = MTLIndentation(level: 2, indentString: "\t")

        #expect(indent1 == indent2)
        #expect(indent1 != indent3)
        #expect(indent1 != indent4)
    }

    @Test("Indentation hashable")
    func testHashable() {
        let indent1 = MTLIndentation(level: 2, indentString: "    ")
        let indent2 = MTLIndentation(level: 2, indentString: "    ")

        var set: Set<MTLIndentation> = []
        set.insert(indent1)
        set.insert(indent2)

        #expect(set.count == 1)
    }

    // MARK: - String Representation

    @Test("String representation at various levels")
    func testStringRepresentation() {
        let base = MTLIndentation(level: 0, indentString: ">>")

        #expect(base.asString == "")
        #expect(base.increment().asString == ">>")
        #expect(base.increment().increment().asString == ">>>>")
        #expect(base.increment().increment().increment().asString == ">>>>>>")
    }

    @Test("Custom indent string with special characters")
    func testCustomIndentString() {
        let indent = MTLIndentation(level: 0, indentString: "| ")
        #expect(indent.indentString == "| ")

        let incremented = indent.increment()
        #expect(incremented.asString == "| ")

        let twice = incremented.increment()
        #expect(twice.asString == "| | ")
    }
}
