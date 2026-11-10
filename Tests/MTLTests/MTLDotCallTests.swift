//
//  MTLDotCallTests.swift
//  MTL
//
//  Created by Rene Hexel on 7/11/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import AQL
@testable import MTL

/// Tests for calls written with a dot on a collection in the expressions of templates.
///
/// The expression options choose whether such a call applies to each element of the
/// collection, as in Eclipse AQL and Acceleo 4, or to the collection, as in version 0.6.
@Suite("MTL Dot Calls")
@MainActor
struct MTLDotCallTests {

    /// Wraps the lines of a main template in a module.
    ///
    /// The lines start on the third line of the module.
    ///
    /// - Parameters:
    ///   - lines: The body of the main template.
    ///   - declarations: Module elements written after the main template.
    /// - Returns: The text of the module.
    private static func module(_ lines: String, declarations: String = "") -> String {
        "[module m('u')/]\n[template main()]\n\(lines)\n[/template]\n" + declarations
    }

    /// The options of the expression language of version 0.6, except that dot calls apply to
    /// each element.
    private static let legacyEachElement: MTLOptions = {
        var options = MTLOptions.legacy
        options.aql.dotCalls = .eachElement
        return options
    }()

    /// The result of a run.
    private struct Run {
        /// The main output.
        var output: String

        /// The warnings of the run.
        var warnings: [SourceDiagnostic]
    }

    /// Runs the main template of a module.
    ///
    /// - Parameters:
    ///   - source: The text of the module.
    ///   - options: The options of the generator.
    ///   - times: How many runs the same generator makes (default: 1).
    /// - Returns: The main output and the warnings of the last run.
    private static func run(_ source: String, options: MTLOptions, times: Int = 1) async throws -> Run {
        let module = try await MTLTestSupport.parse(source)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy, options: options)
        for _ in 0..<times {
            try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        }
        let output = await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? ""
        return Run(output: output, warnings: generator.statistics.warnings)
    }

    // MARK: - Options

    @Test("The standard options apply dot calls to each element and the legacy options to the collection")
    func presets() {
        #expect(MTLOptions().aql.dotCalls == .eachElement)
        #expect(MTLOptions.standard.aql.dotCalls == .eachElement)
        #expect(MTLOptions.legacy.aql.dotCalls == .collection)
        #expect(MTLOptions(semantics: .standard).aql.dotCalls == .eachElement)
        #expect(MTLOptions(semantics: .legacy).aql.dotCalls == .collection)
    }

    @Test("The environment selects the dot calls of its preset")
    func environment() throws {
        let variable = ModellingSemantics.environmentVariable
        #expect(try MTLOptions.fromEnvironment([:]).aql.dotCalls == .eachElement)
        #expect(try MTLOptions.fromEnvironment([variable: "standard"]).aql.dotCalls == .eachElement)
        #expect(try MTLOptions.fromEnvironment([variable: "legacy"]).aql.dotCalls == .collection)
    }

    // MARK: - Evaluation

    @Test(
        "A dot call on a collection applies to each element unless dot calls apply to the collection",
        arguments: [
            ("[Sequence{'a', 'bc'}.size()->sep(',')/]", "1,2", "2"),
            ("[Sequence{'ab', 'c'}.toUpper()->sep(',')/]", "AB,C", nil),
            ("[Sequence{'a', 'bc'}->size()/]", "2", "2"),
            ("['abc'.size()/]", "3", "3"),
        ] as [(String, String, String?)])
    func evaluation(expression: String, eachElement: String, collection: String?) async throws {
        let source = Self.module(expression)
        #expect(try await MTLTestSupport.output(source, options: .standard) == eachElement + "\n")
        #expect(try await MTLTestSupport.output(source, options: Self.legacyEachElement) == eachElement + "\n")
        guard let collection else { return }
        let collectionCalls = MTLOptions(aql: AQLOptions(dotCalls: .collection))
        #expect(try await MTLTestSupport.output(source, options: collectionCalls) == collection + "\n")
        #expect(try await MTLTestSupport.output(source, options: .legacy) == collection + "\n")
        #expect(try await MTLTestSupport.output(source) == collection + "\n")
    }

    @Test("A query called with a dot on a collection applies to each element whatever the options")
    func queryOnEachElement() async throws {
        let source = Self.module(
            "[Sequence{'a', 'b'}.twice()->sep(',')/]",
            declarations: "[query twice(s : String) : String = s + s/]\n")
        #expect(try await MTLTestSupport.output(source, options: .standard) == "aa,bb\n")
        #expect(try await MTLTestSupport.output(source, options: .legacy) == "aa,bb\n")
    }

    // MARK: - Warnings

    @Test("A dot call whose elements lack the service of the collection is reported as a warning")
    func warnsAboutCollectionService() async throws {
        let run = try await Self.run(Self.module("\n[Sequence{1, 2}.size()/]"), options: .standard)
        #expect(run.output == "\n")
        let warning = try #require(run.warnings.first)
        #expect(run.warnings.count == 1)
        #expect(warning.severity == .warning)
        #expect(warning.code == AQLDiagnosticCode.dotCallOnElements)
        #expect(warning.message.contains("->size()"))
        #expect(warning.range?.start.line == 4)
    }

    @Test(
        "No warning is reported for an arrow call, a dot call on a single value or dot calls on the collection",
        arguments: [
            ("[Sequence{1, 2}->size()/]", MTLOptions.standard),
            ("[Sequence{'a', 'bc'}.size()->sep(',')/]", MTLOptions.standard),
            ("['abc'.size()/]", MTLOptions.standard),
            ("[Sequence{1, 2}.size()/]", MTLOptions(aql: AQLOptions(dotCalls: .collection))),
            ("[Sequence{1, 2}.size()/]", MTLOptions.legacy),
        ])
    func noWarning(expression: String, options: MTLOptions) async throws {
        let run = try await Self.run(Self.module(expression), options: options)
        #expect(run.warnings.isEmpty, "\(run.warnings)")
    }

    @Test("Each run of a generator reports the warnings of its expressions once")
    func warningsPerRun() async throws {
        let source = Self.module("[for (i | Sequence{1, 2, 3})][Sequence{1, 2}.size()/][/for]")
        let first = try await Self.run(source, options: .standard)
        #expect(first.warnings.count == 1)
        let again = try await Self.run(source, options: .standard, times: 2)
        #expect(again.warnings.count == 1)
    }

    @Test("Warnings of expressions and of templates are reported in the order they occur")
    func warningOrder() async throws {
        var options = MTLOptions.standard
        options.letTypeMismatches = .skip
        let source = Self.module("[Sequence{1, 2}.size()/]\n[let x : Integer = 'a']inside[/let]")
        let run = try await Self.run(source, options: options)
        #expect(run.warnings.map(\.code) == [AQLDiagnosticCode.dotCallOnElements, MTLDiagnosticCode.letTypeMismatch.rawValue])
    }
}
