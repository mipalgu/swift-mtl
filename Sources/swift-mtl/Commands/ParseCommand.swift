//
// ParseCommand.swift
// swift-mtl
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import ArgumentParser
import Foundation
import MTL

/// Command for parsing and displaying MTL template structure.
///
/// The parse command parses MTL templates and displays their structure,
/// providing insights into templates, queries, macros, and other elements
/// defined in the module.
struct ParseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parse",
        abstract: "Parse and display MTL template structure",
        discussion: """
            Parses MTL templates and displays their internal structure including
            templates, queries, macros, and other module elements. Useful for
            understanding template organization and debugging template issues.

            Examples:
                # Basic parsing
                swift-mtl parse template.mtl

                # Detailed output
                swift-mtl parse template.mtl --detailed

                # JSON output
                swift-mtl parse template.mtl --json

                # Parse multiple files
                swift-mtl parse template1.mtl template2.mtl --detailed
            """
    )

    @Argument(help: "MTL template file(s) to parse")
    var templates: [String]

    @Flag(name: .shortAndLong, help: "Show detailed information about templates")
    var detailed: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    @MainActor
    func run() async throws {
        let parser = MTLParser(enableDebugging: verbose)

        for templatePath in templates {
            if verbose {
                print("Parsing: \(templatePath)")
            }

            let templateURL = URL(fileURLWithPath: templatePath)
            guard FileManager.default.fileExists(atPath: templatePath) else {
                print("Error: File not found: \(templatePath)")
                continue
            }

            do {
                let module = try await parser.parse(templateURL)

                if json {
                    printJSON(module, path: templatePath)
                } else {
                    printAST(module, path: templatePath, detailed: detailed)
                }
            } catch {
                print("Error parsing \(templatePath): \(error)")
            }

            if templates.count > 1 {
                print()  // Blank line between files
            }
        }
    }

    /// Prints the module structure as formatted text.
    private func printAST(_ module: MTLModule, path: String, detailed: Bool) {
        print("File: \(path)")
        print("Module: \(module.name)")

        if !module.metamodels.isEmpty {
            print("\nMetamodels:")
            for (alias, _) in module.metamodels {
                print("  - \(alias)")
            }
        }

        if let extends = module.extends {
            print("\nExtends: \(extends)")
        }

        if !module.imports.isEmpty {
            print("\nImports:")
            for importModule in module.imports {
                print("  - \(importModule)")
            }
        }

        if !module.templates.isEmpty {
            print("\nTemplates (\(module.templates.count)):")
            for (name, template) in module.templates {
                print("  - \(name)")
                if detailed {
                    print("    Visibility: \(template.visibility)")
                    print("    Parameters: \(template.parameters.count)")
                    print("    Main: \(template.isMain)")
                    if !template.parameters.isEmpty {
                        print("    Parameters:")
                        for param in template.parameters {
                            print("      - \(param.name): \(param.type)")
                        }
                    }
                }
            }
        }

        if !module.queries.isEmpty {
            print("\nQueries (\(module.queries.count)):")
            for (name, query) in module.queries {
                print("  - \(name)")
                if detailed {
                    print("    Visibility: \(query.visibility)")
                    print("    Parameters: \(query.parameters.count)")
                    print("    Return type: \(query.returnType)")
                }
            }
        }

        if !module.macros.isEmpty {
            print("\nMacros (\(module.macros.count)):")
            for (name, macro) in module.macros {
                print("  - \(name)")
                if detailed {
                    print("    Parameters: \(macro.parameters.count)")
                    if let bodyParam = macro.bodyParameter {
                        print("    Body parameter: \(bodyParam)")
                    }
                }
            }
        }

        print("\nEncoding: \(module.encoding)")
    }

    /// Prints the module structure as JSON.
    private func printJSON(_ module: MTLModule, path: String) {
        let output: [String: Any] = [
            "file": path,
            "module": module.name,
            "encoding": module.encoding,
            "extends": module.extends as Any,
            "imports": module.imports,
            "templates": module.templates.keys.map { $0 },
            "queries": module.queries.keys.map { $0 },
            "macros": module.macros.keys.map { $0 },
            "counts": [
                "templates": module.templates.count,
                "queries": module.queries.count,
                "macros": module.macros.count,
            ],
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print(jsonString)
        } else {
            print("Error: Failed to serialize to JSON")
        }
    }
}
