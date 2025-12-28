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
            print("\n=== Parsing MTL Template ===")
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

        // Load models
        var loadedModels: [String: Resource] = [:]
        if !model.isEmpty {
            if verbose {
                print("\n=== Loading Models ===")
            }

            for (index, modelPath) in model.enumerated() {
                let modelURL = URL(fileURLWithPath: modelPath)
                guard FileManager.default.fileExists(atPath: modelPath) else {
                    throw ValidationError.fileNotFound(modelPath)
                }

                // Detect format based on extension
                let format = detectFormat(from: modelPath)

                if verbose {
                    print("Loading model \(index + 1): \(modelPath) (format: \(format))")
                }

                let resource = try await loadModel(from: modelPath, format: format, verbose: verbose)

                // Use filename without extension as model name
                let modelName = modelURL.deletingPathExtension().lastPathComponent
                loadedModels[modelName] = resource

                if verbose {
                    let count = await resource.count()
                    print("  ✓ Loaded \(count) objects")
                }
            }
        }

        // Determine main template
        let mainTemplateName: String
        if let specified = template {
            mainTemplateName = specified
            guard mtlModule.templates[mainTemplateName] != nil else {
                throw ValidationError.generationFailed("Template '\(mainTemplateName)' not found in module")
            }
        } else {
            // Find first template marked as main, or use first template
            if let main = mtlModule.templates.first(where: { $0.value.isMain }) {
                mainTemplateName = main.key
            } else if let first = mtlModule.templates.first {
                mainTemplateName = first.key
            } else {
                throw ValidationError.generationFailed("No templates found in module")
            }
        }

        if verbose {
            print("\n=== Executing Generation ===")
            print("Main template: \(mainTemplateName)")
            print("Output directory: \(output)")
        }

        // Create output directory if needed
        if !FileManager.default.fileExists(atPath: output) {
            let outputURL = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        }

        // Execute generation
        let strategy = MTLFileSystemStrategy(basePath: output)
        let generator = MTLGenerator(module: mtlModule, generationStrategy: strategy)

        do {
            try await generator.generate(
                mainTemplate: mainTemplateName,
                arguments: [],
                models: loadedModels
            )
        } catch {
            throw ValidationError.generationFailed(error.localizedDescription)
        }

        // Display results
        if verbose {
            print("\n=== Generation Complete ===")
            let stats = generator.statistics
            print("✓ Generation successful")
            print("  Templates executed: \(stats.templatesExecuted)")
            print("  Execution time: \(String(format: "%.3f", stats.executionTime * 1000))ms")
        } else {
            print("✓ Generation complete")
        }
    }
}

// MARK: - Helper Functions

/// Model format enumeration.
enum ModelFormat: String {
    case xmi
    case json

    var description: String {
        switch self {
        case .xmi: return "XMI"
        case .json: return "JSON"
        }
    }
}

/// Detects the model format based on file extension.
func detectFormat(from path: String) -> ModelFormat {
    let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
    switch pathExtension {
    case "xmi", "ecore":
        return .xmi
    case "json":
        return .json
    default:
        return .xmi  // Default to XMI
    }
}

/// Loads a model from a file using the appropriate parser.
func loadModel(
    from path: String,
    format: ModelFormat,
    verbose: Bool
) async throws -> Resource {
    let url = URL(fileURLWithPath: path)

    let resource: Resource
    switch format {
    case .xmi:
        let parser = XMIParser(enableDebugging: verbose)
        resource = try await parser.parse(url)
    case .json:
        let parser = JSONParser()
        resource = try await parser.parse(url)
    }

    return resource
}

// MARK: - Error Types

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
