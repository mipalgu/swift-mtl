//
//  MTLLetTypeMismatchTests.swift
//  MTL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import MTL

/// Tests for the handling of `let` values that do not conform to the declared type of their variable.
@Suite("MTL Let Type Mismatches")
@MainActor
struct MTLLetTypeMismatchTests {

    /// Wraps a template body in a module with a main template.
    private static func module(_ body: String) -> String {
        "[module m('u')/]\n[template main()]\(body)[/template]"
    }

    /// The outcome of a successful run.
    private struct Run {
        /// The main output.
        var output: String

        /// The warnings of the run.
        var warnings: [SourceDiagnostic]
    }

    /// Runs a template body with the given mismatch handling.
    ///
    /// - Parameters:
    ///   - body: The body of the main template.
    ///   - handling: How mismatches are handled.
    /// - Returns: The main output and the warnings of the run.
    private static func run(_ body: String, handling: MTLLetTypeMismatches) async throws -> Run {
        let module = try await MTLTestSupport.parse(module(body))
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(
            module: module, generationStrategy: strategy, options: MTLOptions(letTypeMismatches: handling))
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        let output = await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? ""
        return Run(output: output, warnings: generator.statistics.warnings)
    }

    // MARK: - Options

    @Test("The handling modes are spelt error and skip")
    func spellings() {
        #expect(MTLLetTypeMismatches.allCases.map(\.rawValue) == ["error", "skip"])
        #expect(MTLLetTypeMismatches(rawValue: "skip") == .skip)
        #expect(MTLLetTypeMismatches(rawValue: "warn") == nil)
    }

    @Test("A mismatch is a type error by default")
    func defaultIsError() async throws {
        let module = try await MTLTestSupport.parse(Self.module("before[let x : Integer = 'a']inside[/let]"))
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy(), options: MTLOptions())
        #expect(generator.options.letTypeMismatches == .error)
        await #expect(throws: MTLExecutionError.self) {
            try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        }
        #expect(generator.statistics.warnings.isEmpty)
    }

    @Test("The error mode reports a type error naming the variable and both types")
    func errorMode() async {
        do {
            _ = try await Self.run("[let x : Integer = 'a']inside[/let]", handling: .error)
            Issue.record("Expected a type error")
        } catch let error as MTLExecutionError {
            guard case .typeError(let message) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(message.contains("'x'"))
            #expect(message.contains("Integer"))
            #expect(message.contains("String"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    // MARK: - Skipping

    @Test("The skip mode skips the let body and continues the generation")
    func skipsBody() async throws {
        let run = try await Self.run("before[let x : Integer = 'a']inside[/let]after", handling: .skip)
        #expect(run.output == "beforeafter")
    }

    @Test("A skipped let block produces exactly one warning naming the variable and both types")
    func skipWarns() async throws {
        let run = try await Self.run("[let x : Integer = 'a']inside[/let]", handling: .skip)
        let warning = try #require(run.warnings.first)
        #expect(run.warnings.count == 1)
        #expect(warning.severity == .warning)
        #expect(warning.code == MTLDiagnosticCode.letTypeMismatch.rawValue)
        #expect(warning.message.contains("'x'"))
        #expect(warning.message.contains("Integer"))
        #expect(warning.message.contains("String"))
    }

    @Test("A warning names the declared and actual types of the value", arguments: [
        ("Integer", "'text'", "String"),
        ("String", "42", "Integer"),
        ("Sequence(String)", "'text'", "String"),
        ("Boolean", "Sequence{true}", "Collection"),
        ("String", "true", "Boolean"),
        ("Integer", "1.5", "Real")
    ])
    func warningNamesTypes(declared: String, value: String, actual: String) async throws {
        let run = try await Self.run("[let v : \(declared) = \(value)]inside[/let]", handling: .skip)
        #expect(run.output.isEmpty)
        let warning = try #require(run.warnings.first)
        #expect(warning.message.contains("'v'"))
        #expect(warning.message.contains("type \(declared)"))
        #expect(warning.message.contains("type \(actual)"))
    }

    @Test("A warning names a model object by its metaclass")
    func warningNamesMetaclass() async throws {
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[template main(t : OclAny)][let s : String = t]inside[/let][/template]")
        let generator = MTLGenerator(
            module: module, generationStrategy: MTLInMemoryStrategy(), options: MTLOptions(letTypeMismatches: .skip))
        let thing = DynamicEObject(eClass: EClass(name: "Thing"))
        try await generator.generate(mainTemplate: "main", arguments: [thing], models: [:])
        let message = try #require(generator.statistics.warnings.first?.message)
        #expect(message.contains("type Thing"))
    }

    @Test("A warning points at the let block in the template")
    func warningLocation() async throws {
        let run = try await Self.run("\nline two\n[let x : Integer = 'a']inside[/let]", handling: .skip)
        let range = try #require(run.warnings.first?.range)
        #expect(range.start.line == 4)
    }

    @Test("Null conforms to every type in the skip mode")
    func nullConforms() async throws {
        let run = try await Self.run("[let s : String = null][if (s = null)]none[/if][/let]", handling: .skip)
        #expect(run.output == "none")
        #expect(run.warnings.isEmpty)
    }

    @Test("Conforming values bind as usual in the skip mode")
    func conformingValues() async throws {
        let run = try await Self.run(
            "[let names : Sequence(String) = Sequence{'a', 'b'}, n : Integer = 2]"
                + "[for (s : String | names) separator(', ')][s/][/for] [n/][/let]",
            handling: .skip)
        #expect(run.output == "a, b 2")
        #expect(run.warnings.isEmpty)
    }

    @Test("A mismatch of a later binding skips the whole let block")
    func laterBindingMismatch() async throws {
        let run = try await Self.run(
            "[let a : String = 'ok', b : Integer = a]inside [a/][/let]rest", handling: .skip)
        #expect(run.output == "rest")
        #expect(run.warnings.count == 1)
        let message = try #require(run.warnings.first?.message)
        #expect(message.contains("'b'"))
        #expect(!message.contains("'a'"))
    }

    @Test("A mismatch in a nested let skips only the inner block")
    func nestedInnerMismatch() async throws {
        let run = try await Self.run(
            "[let o : String = 'out']<[o/][let i : Integer = o]inner[/let]>[/let]", handling: .skip)
        #expect(run.output == "<out>")
        #expect(run.warnings.count == 1)
        #expect(run.warnings.first?.message.contains("'i'") == true)
    }

    @Test("A mismatch in an outer let skips the nested blocks")
    func nestedOuterMismatch() async throws {
        let run = try await Self.run(
            "[let o : Integer = 'x']outer[let i : String = 'y'][i/][/let][/let]done", handling: .skip)
        #expect(run.output == "done")
        #expect(run.warnings.count == 1)
        #expect(run.warnings.first?.message.contains("'o'") == true)
    }

    @Test("Generation continues after a mismatch inside a loop")
    func continuesInLoop() async throws {
        let run = try await Self.run(
            "[for (v | Sequence{1, 'two', 3})][let n : Integer = v][n/];[/let][/for]", handling: .skip)
        #expect(run.output == "1;3;")
        #expect(run.warnings.count == 1)
    }

    @Test("A mismatch that repeats in a loop is reported once")
    func repeatedMismatchReportedOnce() async throws {
        let run = try await Self.run(
            "[for (v | Sequence{'a', 'b', 'c'})][let n : Integer = v][n/][/let][/for]", handling: .skip)
        #expect(run.output.isEmpty)
        #expect(run.warnings.count == 1)
    }

    @Test("Distinct mismatches are each reported")
    func distinctMismatches() async throws {
        let run = try await Self.run(
            "[let a : Integer = 'x']a[/let][let b : String = 1]b[/let]", handling: .skip)
        #expect(run.output.isEmpty)
        #expect(run.warnings.count == 2)
        #expect(run.warnings.first?.message.contains("'a'") == true)
        #expect(run.warnings.last?.message.contains("'b'") == true)
    }

    // MARK: - Statistics

    @Test("Warnings of an earlier run are forgotten when the generator runs again")
    func warningsReset() async throws {
        let module = try await MTLTestSupport.parse(Self.module("[let x : Integer = 'a']inside[/let]"))
        let generator = MTLGenerator(
            module: module, generationStrategy: MTLInMemoryStrategy(), options: MTLOptions(letTypeMismatches: .skip))
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        #expect(generator.statistics.warnings.count == 1)
    }

    @Test("Warnings recorded before a failure remain available")
    func warningsBeforeFailure() async throws {
        let module = try await MTLTestSupport.parse(
            Self.module("[let x : Integer = 'a']inside[/let][missing()/]"))
        let generator = MTLGenerator(
            module: module, generationStrategy: MTLInMemoryStrategy(), options: MTLOptions(letTypeMismatches: .skip))
        await #expect(throws: (any Error).self) {
            try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        }
        #expect(generator.statistics.warnings.count == 1)
        #expect(!generator.statistics.successful)
    }

    @Test("The summary of the statistics counts the warnings")
    func summaryCountsWarnings() async throws {
        let module = try await MTLTestSupport.parse(Self.module("[let x : Integer = 'a']inside[/let]"))
        let generator = MTLGenerator(
            module: module, generationStrategy: MTLInMemoryStrategy(), options: MTLOptions(letTypeMismatches: .skip))
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        #expect(generator.statistics.summary().contains("Warnings: 1"))
        var statistics = generator.statistics
        statistics.reset()
        #expect(statistics.warnings.isEmpty)
    }

    // MARK: - Execution Context

    @Test("An execution context in the skip mode records the warning")
    func contextSkips() async throws {
        let module = try await MTLTestSupport.parse(Self.module("x"))
        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module, generationStrategy: strategy, options: MTLOptions(letTypeMismatches: .skip))
        #expect(context.options.letTypeMismatches == .skip)
        let parsed = try await MTLTestSupport.parse(Self.module("[let x : Integer = 'a']inside[/let]"))
        let statement = try #require(parsed.templates["main"]?.body.statements.first as? MTLLetStatement)
        try await statement.execute(in: context)
        #expect(context.warnings.count == 1)
        #expect(context.warnings.first?.code == MTLDiagnosticCode.letTypeMismatch.rawValue)
    }

    @Test("An execution context reports mismatches as type errors by default")
    func contextDefault() async throws {
        let module = try await MTLTestSupport.parse(Self.module("x"))
        let context = MTLExecutionContext(module: module, generationStrategy: MTLInMemoryStrategy(), options: MTLOptions())
        #expect(context.options.letTypeMismatches == .error)
        let parsed = try await MTLTestSupport.parse(Self.module("[let x : Integer = 'a']inside[/let]"))
        let statement = try #require(parsed.templates["main"]?.body.statements.first as? MTLLetStatement)
        await #expect(throws: MTLExecutionError.self) {
            try await statement.execute(in: context)
        }
        #expect(context.warnings.isEmpty)
    }
}
