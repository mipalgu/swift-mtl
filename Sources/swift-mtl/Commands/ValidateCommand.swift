//
// ValidateCommand.swift
// swift-mtl
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import ArgumentParser
import Foundation
import MTL

/// Command for validating MTL template syntax and semantics.
///
/// The validate command checks MTL templates for syntax errors and
/// structural problems, reporting issues found during validation.
struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate MTL template syntax and semantics",
        discussion: """
            Validates MTL templates for syntax errors and structural issues.
            Returns exit code 0 if all templates are valid, non-zero otherwise.

            Examples:
                # Validate single template
                swift-mtl validate template.mtl

                # Validate multiple templates
                swift-mtl validate template1.mtl template2.mtl

                # Validate all MTL files in directory
                swift-mtl validate Templates/*.mtl

                # Verbose validation
                swift-mtl validate template.mtl --verbose
            """
    )

    @Argument(help: "MTL template file(s) to validate")
    var templates: [String]

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    @MainActor
    func run() async throws {
        var allValid = true
        var validCount = 0
        var errorCount = 0

        let parser = MTLParser(enableDebugging: verbose)

        if verbose {
            print("Validating \(templates.count) template(s)...\n")
        }

        for templatePath in templates {
            let templateURL = URL(fileURLWithPath: templatePath)

            // Check file exists
            guard FileManager.default.fileExists(atPath: templatePath) else {
                print("✗ \(templatePath): File not found")
                allValid = false
                errorCount += 1
                continue
            }

            // Parse and validate
            do {
                let module = try await parser.parse(templateURL)

                print("✓ \(templatePath): Valid")
                validCount += 1

                if verbose {
                    print("  Module: \(module.name)")
                    print("  Templates: \(module.templates.count)")
                    print("  Queries: \(module.queries.count)")
                    print("  Macros: \(module.macros.count)")
                }
            } catch let error as MTLParseError {
                print("✗ \(templatePath): Parse error")
                if verbose || true {  // Always show parse errors
                    print("  \(error)")
                }
                allValid = false
                errorCount += 1
            } catch {
                print("✗ \(templatePath): \(error.localizedDescription)")
                allValid = false
                errorCount += 1
            }
        }

        // Print summary
        if templates.count > 1 || verbose {
            print()
            print("Summary:")
            print("  Valid: \(validCount)")
            print("  Errors: \(errorCount)")
            print("  Total: \(templates.count)")
        }

        // Exit with error code if any validation failed
        if !allValid {
            throw ExitCode.failure
        }
    }
}
