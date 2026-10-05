//
//  MTLExpressionGoldenTests.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Testing

@testable import MTL

/// Compares the trees the parser builds for a broad corpus of expressions with recorded goldens.
@Suite("MTL Expression Goldens")
struct MTLExpressionGoldenTests {

    @Test("Every corpus expression has a golden and every golden a corpus expression")
    func corpusAndGoldensAgree() {
        let sources = MTLExpressionCorpus.valid.map(\.source)
        #expect(Set(sources).count == sources.count)
        #expect(Set(sources) == Set(MTLExpressionGoldens.trees.keys))
    }

    @Test("A corpus expression parses to its golden tree", arguments: MTLExpressionCorpus.valid.map(\.source))
    func parsesToGolden(source: String) async throws {
        let tree = try await MTLExpressionGoldenSupport.tree(source)
        #expect(tree == MTLExpressionGoldens.trees[source])
    }

    @Test("A malformed expression is rejected", arguments: MTLExpressionCorpus.invalid)
    func rejectsMalformed(source: String) async {
        await #expect(throws: MTLParseError.self) {
            _ = try await MTLExpressionGoldenSupport.parse(source)
        }
    }

    @Test("Collected expressions print their set name")
    func collectedExpression() async throws {
        let tree = try await MTLExpressionGoldenSupport.tree("collected('imports')")
        #expect(tree == "collected(lit(string(\"imports\")))")
    }

    @Test("Operators the grammar does not define are rejected rather than reinterpreted")
    func nullSafeNavigationIsNotMtlSyntax() async {
        await #expect(throws: MTLParseError.self) {
            _ = try await MTLExpressionGoldenSupport.parse("a?.b")
        }
    }
}
