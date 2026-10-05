//
//  MTLProgressTests.swift
//  MTL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation
import Testing

@testable import MTL

@Suite("MTL progress and cancellation")
struct MTLProgressTests {

    private let header = "[module m('u')/]\n"

    /// A sequence of the given number of integers.
    private func numbers(_ count: Int) -> EcoreValueArray {
        EcoreValueArray((0..<count).map { $0 as any EcoreValue })
    }

    /// Collects progress reports on the main actor.
    @MainActor
    private final class Recorder {
        var reports: [MTLProgress] = []
    }

    @MainActor
    private func generate(
        _ source: String, arguments: [(any EcoreValue)?] = [],
        progress: (@MainActor @Sendable (MTLProgress) -> Void)?
    ) async throws -> MTLInMemoryStrategy {
        let module = try await MTLTestSupport.parse(source)
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.generate(
            mainTemplate: "main", arguments: arguments, models: [:], progress: progress)
        return strategy
    }

    // MARK: Progress

    @Test("Progress counts templates and files and names the current ones")
    @MainActor
    func reports() async throws {
        let recorder = Recorder()
        let source = header + """
            [template main()][file ('a.txt')][helper()/][/file][file ('b.txt')]b[/file][/template]
            [template helper()]h[/template]
            """
        _ = try await generate(source) { recorder.reports.append($0) }
        let last = try #require(recorder.reports.last)
        #expect(last.templatesExecuted == 2)
        #expect(last.filesWritten == 2)
        #expect(recorder.reports.contains { $0.currentFile == "a.txt" })
        #expect(recorder.reports.contains { $0.currentFile == "b.txt" })
        #expect(recorder.reports.contains { $0.currentTemplate == "main" })
        #expect(recorder.reports.contains { $0.currentTemplate == "helper" })
        let counts = recorder.reports.map(\.filesWritten)
        #expect(counts == counts.sorted())
        #expect(last.currentTemplate == nil && last.currentFile == nil)
    }

    @Test("Without a handler generation behaves as before")
    @MainActor
    func withoutHandler() async throws {
        let strategy = try await generate(header + "[template main()]x[/template]", progress: nil)
        #expect(await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] == "x")
    }

    @Test("The existing overload does not report")
    @MainActor
    func existingOverload() async throws {
        let module = try await MTLTestSupport.parse(header + "[template main()]x[/template]")
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        #expect(generator.statistics.successful)
    }

    @Test("Progress values compare by content")
    func equality() {
        #expect(MTLProgress() == MTLProgress())
        #expect(MTLProgress(templatesExecuted: 1) != MTLProgress())
        let progress = MTLProgress(templatesExecuted: 1, filesWritten: 2, currentTemplate: "t", currentFile: "f")
        #expect(progress.templatesExecuted == 1 && progress.filesWritten == 2)
        #expect(progress.currentTemplate == "t" && progress.currentFile == "f")
    }

    // MARK: Cancellation

    @Test("A cancelled run stops with a cancellation error")
    @MainActor
    func cancellation() async throws {
        let source = header + "[template main(xs : Sequence(Integer))][for (x | xs)]x[/for][/template]"
        let module = try await MTLTestSupport.parse(source)
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        let arguments: [(any EcoreValue)?] = [numbers(2_000_000)]
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { @MainActor in
            try await generator.generate(mainTemplate: "main", arguments: arguments, models: [:])
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            try await task.value
            Issue.record("Expected the run to be cancelled")
        } catch is CancellationError {
            #expect(clock.now - start < .seconds(20))
            #expect(!generator.statistics.successful)
        }
    }

    @Test("A run that is cancelled before it starts does not generate")
    @MainActor
    func cancelledBeforeStart() async throws {
        let module = try await MTLTestSupport.parse(header + "[template main()]x[/template]")
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: Responsiveness

    @Test("A long run on the main actor lets other main actor work proceed")
    @MainActor
    func responsiveness() async throws {
        let source = header + "[template main(xs : Sequence(Integer))][for (x | xs)]x[/for][/template]"
        let module = try await MTLTestSupport.parse(source)
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        let arguments: [(any EcoreValue)?] = [numbers(25_000)]
        var ticks = 0
        var finished = false
        let ticker = Task { @MainActor in
            while !finished {
                ticks += 1
                await Task.yield()
            }
        }
        try await generator.generate(mainTemplate: "main", arguments: arguments, models: [:])
        let ticksDuringRun = ticks
        finished = true
        await ticker.value
        #expect(ticksDuringRun > 1)
    }
}
