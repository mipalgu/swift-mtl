//
// GenerateCommand.swift
// swift-mtl
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import ArgumentParser
import ECore
import Foundation
import MTL

/// Command for generating text from models using MTL templates.
///
/// The generate command executes MTL templates to produce text output from
/// models, supporting code generation, documentation generation, and other
/// model-to-text transformations.
struct GenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate text from models using MTL templates",
        discussion: """
            Generates text files from models using MTL (Model-to-Text Language) templates.
            Supports generation from models in XMI and JSON formats with automatic
            format detection based on file extensions.

            Examples:
                # Basic generation
                swift-mtl generate template.mtl \\
                  --model input.xmi \\
                  --output generated/

                # Multiple models
                swift-mtl generate template.mtl \\
                  --model families.xmi \\
                  --model departments.xmi \\
                  --output generated/

                # Specify main template
                swift-mtl generate template.mtl \\
                  --model input.xmi \\
                  --template generateAll \\
                  --output generated/

                # Verbose output
                swift-mtl generate template.mtl \\
                  --model input.xmi \\
                  --output generated/ \\
                  --verbose
            """
    )

    @Argument(help: "MTL template file (.mtl)")
    var templateFile: String

    @Option(name: .long, help: "Input model file (XMI or JSON, can be specified multiple times)")
    var model: [String] = []

    @Option(name: .shortAndLong, help: "Output directory for generated files")
    var output: String = "."

    @Option(name: .shortAndLong, help: "Main template name to execute (auto-detect if not specified)")
    var template: String?

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    @MainActor
    func run() async throws {
        // Print configuration if verbose
        if verbose {
            print("MTL Template: \(templateFile)")
            print("Input Models: \(model.joined(separator: ", "))")
            print("Output Directory: \(output)")
            if let template = template {
                print("Main Template: \(template)")
            }
        }

        // Parse MTL template
        if verbose {
            print("\nParsing MTL template...")
        }

        let templateURL = URL(fileURLWithPath: templateFile)
        guard FileManager.default.fileExists(atPath: templateFile) else {
            throw ValidationError.fileNotFound(templateFile)
        }

        let parser = MTLParser(enableDebugging: verbose)
        let mtlModule: MTLModule
        do {
            mtlModule = try await parser.parse(templateURL)
        } catch {
            throw ValidationError.parseFailed(templateFile, error.localizedDescription)
        }

        if verbose {
            print("✓ Successfully parsed MTL module: \(mtlModule.name)")
            print("  Templates: \(mtlModule.templates.count)")
            print("  Queries: \(mtlModule.queries.count)")
            print("  Macros: \(mtlModule.macros.count)")
        }

        // TODO: Load models (Phase 7)
        if !model.isEmpty {
            if verbose {
                print("\nModel loading will be implemented in Phase 7")
                print("Models to load: \(model)")
            }
        }

        // TODO: Execute generation (Phase 7)
        if verbose {
            print("\nGeneration execution will be implemented in Phase 7")
        }

        print("\n✓ MTL template parsed successfully")
        print("  Note: Full generation support coming in Phase 7")
    }
}

/// Validation errors for the generate command.
enum ValidationError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case parseFailed(String, String)
    case generationFailed(String)

    var description: String {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .parseFailed(let path, let message):
            return "Failed to parse \(path): \(message)"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        }
    }
}
