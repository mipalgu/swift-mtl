//
//  MTLOptionsSemanticsTests.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import Foundation
import Testing

@testable import MTL

/// Tests for the options that a choice of semantics, or the environment, selects.
@Suite("MTL Options from Semantics")
struct MTLOptionsSemanticsTests {
    /// The name of the environment variable, as documented.
    private let variable = "SWIFT_MODELLING_SEMANTICS"

    @Test("Each semantics selects its preset")
    func presets() {
        #expect(MTLOptions(semantics: .standard) == .standard)
        #expect(MTLOptions(semantics: .legacy) == .legacy)
        #expect(MTLOptions(semantics: .standard).aql == AQLOptions(semantics: .standard))
        #expect(MTLOptions(semantics: .legacy).aql == AQLOptions(semantics: .legacy))
    }

    @Test("The environment selects the preset", arguments: ModellingSemantics.allCases)
    func environment(semantics: ModellingSemantics) throws {
        #expect(try MTLOptions.fromEnvironment([variable: semantics.rawValue]) == MTLOptions(semantics: semantics))
    }

    @Test("Without a choice in the environment, the options are standard")
    func unset() throws {
        #expect(try MTLOptions.fromEnvironment([:]) == .standard)
        #expect(try MTLOptions.fromEnvironment([variable: ""]) == .standard)
    }

    @Test("An invalid value in the environment is an error")
    func invalid() {
        #expect(throws: ModellingSemanticsError.invalidValue("eclipse", variable: variable)) {
            try MTLOptions.fromEnvironment([variable: "eclipse"])
        }
    }

    @Test("The process environment is read by default")
    func processEnvironment() throws {
        let expected = try MTLOptions.fromEnvironment(ProcessInfo.processInfo.environment)
        #expect(try MTLOptions.fromEnvironment() == expected)
    }
}
