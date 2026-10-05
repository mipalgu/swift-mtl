//
//  MTLTestSupport.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Foundation
import Testing

@testable import MTL

/// Helpers shared by the syntax and generation tests.
enum MTLTestSupport {

    /// The name under which the generator stores the main output.
    static let standardOutput = "stdout"

    /// Parses a module from source text.
    ///
    /// - Parameter source: The module source.
    /// - Returns: The parsed module.
    static func parse(_ source: String) async throws -> MTLModule {
        try await MTLParser().parse(source, filename: "test.mtl")
    }

    /// Parses a module, runs a template, and returns all generated files.
    ///
    /// - Parameters:
    ///   - source: The module source.
    ///   - main: The name of the template to run.
    ///   - arguments: The template arguments.
    /// - Returns: The generated files by name; the main output is under ``standardOutput``.
    @MainActor
    static func run(
        _ source: String,
        main: String = "main",
        arguments: [(any EcoreValue)?] = []
    ) async throws -> [String: String] {
        let module = try await parse(source)
        return try await run(module, main: main, arguments: arguments)
    }

    /// Runs a template of an already parsed module and returns all generated files.
    ///
    /// - Parameters:
    ///   - module: The module.
    ///   - main: The name of the template to run.
    ///   - arguments: The template arguments.
    /// - Returns: The generated files by name.
    @MainActor
    static func run(
        _ module: MTLModule,
        main: String = "main",
        arguments: [(any EcoreValue)?] = []
    ) async throws -> [String: String] {
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.generate(mainTemplate: main, arguments: arguments, models: [:])
        return await strategy.getGeneratedFiles()
    }

    /// Runs a template and returns only its standard output.
    @MainActor
    static func output(
        _ source: String,
        main: String = "main",
        arguments: [(any EcoreValue)?] = []
    ) async throws -> String {
        let files = try await run(source, main: main, arguments: arguments)
        return files[standardOutput] ?? ""
    }

    /// The URL of a fixture directory below the test resources.
    ///
    /// Depending on the toolchain, the copied `Resources` directory is either the
    /// bundle's resource directory itself or nested inside it, so both are tried.
    ///
    /// - Parameter path: The path below `Resources`.
    /// - Returns: The file URL of the resource.
    static func resource(_ path: String) -> URL {
        let base = Bundle.module.resourceURL!
        let nested = base.appendingPathComponent("Resources").appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: nested.path) { return nested }
        return base.appendingPathComponent(path)
    }
}
