//
//  CLIIntegrationTests.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@Suite("CLI Integration Tests")
struct CLIIntegrationTests {

    // MARK: - Generate Command Tests

    @Test("Generate command - simple template")
    @MainActor
    func testGenerateSimpleTemplate() async throws {
        // Given
        let templateURL = try loadTestResource(named: "simple-hello.mtl", subdirectory: "templates")
        let outputDir = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(outputDir) }

        // When
        let result = try await executeSwiftMTL(
            command: "generate",
            arguments: [
                templateURL.path,
                "--output", outputDir.path
            ]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("Generation complete"))

        // Verify stdout was created
        let stdoutFile = outputDir.appendingPathComponent("stdout")
        #expect(FileManager.default.fileExists(atPath: stdoutFile.path))

        let content = try String(contentsOf: stdoutFile)
        #expect(content.contains("Hello, World!"))
        #expect(content.contains("This is a simple MTL template."))
    }

    @Test("Generate command - template with expressions")
    @MainActor
    func testGenerateTemplateWithExpressions() async throws {
        // Given
        let templateURL = try loadTestResource(named: "with-expressions.mtl", subdirectory: "templates")
        let outputDir = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(outputDir) }

        // When
        let result = try await executeSwiftMTL(
            command: "generate",
            arguments: [
                templateURL.path,
                "--output", outputDir.path
            ]
        )

        // Then
        #expect(result.succeeded)

        let stdoutFile = outputDir.appendingPathComponent("stdout")
        let content = try String(contentsOf: stdoutFile)
        #expect(content.contains("Version: 1.0.0"))
        #expect(content.contains("Numbers: 6"))
    }

    @Test("Generate command - template with control flow")
    @MainActor
    func testGenerateTemplateWithControlFlow() async throws {
        // Given
        let templateURL = try loadTestResource(named: "with-control-flow.mtl", subdirectory: "templates")
        let outputDir = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(outputDir) }

        // When
        let result = try await executeSwiftMTL(
            command: "generate",
            arguments: [
                templateURL.path,
                "--output", outputDir.path
            ]
        )

        // Then
        #expect(result.succeeded)

        let stdoutFile = outputDir.appendingPathComponent("stdout")
        let content = try String(contentsOf: stdoutFile)
        #expect(content.contains("Condition is true"))
        #expect(!content.contains("Condition is false"))
        #expect(content.contains("Items: 1, 2, 3"))
        #expect(content.contains("Message: Hello"))
    }

    @Test("Generate command - template with file blocks")
    @MainActor
    func testGenerateTemplateWithFileBlocks() async throws {
        // Given
        let templateURL = try loadTestResource(named: "with-file-blocks.mtl", subdirectory: "templates")
        let outputDir = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(outputDir) }

        // When
        let result = try await executeSwiftMTL(
            command: "generate",
            arguments: [
                templateURL.path,
                "--output", outputDir.path
            ]
        )

        // Then
        #expect(result.succeeded)

        // Verify files were created
        let output1 = outputDir.appendingPathComponent("output1.txt")
        let output2 = outputDir.appendingPathComponent("output2.txt")

        #expect(FileManager.default.fileExists(atPath: output1.path))
        #expect(FileManager.default.fileExists(atPath: output2.path))

        let content1 = try String(contentsOf: output1)
        let content2 = try String(contentsOf: output2)

        #expect(content1.contains("File 1 content"))
        #expect(content2.contains("File 2 content"))
    }

    @Test("Generate command - verbose output")
    @MainActor
    func testGenerateVerboseOutput() async throws {
        // Given
        let templateURL = try loadTestResource(named: "simple-hello.mtl", subdirectory: "templates")
        let outputDir = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(outputDir) }

        // When
        let result = try await executeSwiftMTL(
            command: "generate",
            arguments: [
                templateURL.path,
                "--output", outputDir.path,
                "--verbose"
            ]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("Parsing MTL Template"))
        #expect(result.stdout.contains("Executing Generation"))
        #expect(result.stdout.contains("Generation Complete"))
        #expect(result.stdout.contains("Templates executed:"))
        #expect(result.stdout.contains("Execution time:"))
    }

    @Test("Generate command - file not found error")
    @MainActor
    func testGenerateFileNotFound() async throws {
        // When
        let result = try await executeSwiftMTL(
            command: "generate",
            arguments: ["/nonexistent/template.mtl"]
        )

        // Then
        #expect(!result.succeeded)
        #expect(result.stderr.contains("File not found") || result.exitCode != 0)
    }

    @Test("Generate command - invalid template syntax")
    @MainActor
    func testGenerateInvalidSyntax() async throws {
        // Given
        let templateURL = try loadTestResource(named: "invalid-syntax.mtl", subdirectory: "templates")
        let outputDir = try createTemporaryDirectory()
        defer { cleanupTemporaryDirectory(outputDir) }

        // When
        let result = try await executeSwiftMTL(
            command: "generate",
            arguments: [
                templateURL.path,
                "--output", outputDir.path
            ]
        )

        // Then
        #expect(!result.succeeded)
    }

    // MARK: - Parse Command Tests

    @Test("Parse command - simple template")
    @MainActor
    func testParseSimpleTemplate() async throws {
        // Given
        let templateURL = try loadTestResource(named: "simple-hello.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "parse",
            arguments: [templateURL.path]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("Module: SimpleHello"))
        #expect(result.stdout.contains("Templates (1)"))
    }

    @Test("Parse command - template with expressions")
    @MainActor
    func testParseTemplateWithExpressions() async throws {
        // Given
        let templateURL = try loadTestResource(named: "with-expressions.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "parse",
            arguments: [templateURL.path]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("Module: WithExpressions"))
        #expect(result.stdout.contains("Queries (1)"))
    }

    @Test("Parse command - detailed output")
    @MainActor
    func testParseDetailedOutput() async throws {
        // Given
        let templateURL = try loadTestResource(named: "with-control-flow.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "parse",
            arguments: [
                templateURL.path,
                "--detailed"
            ]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("Module: WithControlFlow"))
        #expect(result.stdout.contains("Templates (1)"))
        #expect(result.stdout.contains("main"))
    }

    @Test("Parse command - JSON output")
    @MainActor
    func testParseJSONOutput() async throws {
        // Given
        let templateURL = try loadTestResource(named: "simple-hello.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "parse",
            arguments: [
                templateURL.path,
                "--json"
            ]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("\"module\""))
        #expect(result.stdout.contains("\"templates\""))
        #expect(result.stdout.contains("SimpleHello"))
    }

    @Test("Parse command - invalid syntax")
    @MainActor
    func testParseInvalidSyntax() async throws {
        // Given
        let templateURL = try loadTestResource(named: "invalid-syntax.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "parse",
            arguments: [templateURL.path]
        )

        // Then
        // Parse command doesn't fail, it just prints error message
        #expect(result.stdout.contains("Error parsing"))
    }

    @Test("Parse command - multiple templates")
    @MainActor
    func testParseMultipleTemplates() async throws {
        // Given
        let template1 = try loadTestResource(named: "simple-hello.mtl", subdirectory: "templates")
        let template2 = try loadTestResource(named: "with-expressions.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "parse",
            arguments: [
                template1.path,
                template2.path
            ]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("SimpleHello"))
        #expect(result.stdout.contains("WithExpressions"))
    }

    // MARK: - Validate Command Tests

    @Test("Validate command - valid template")
    @MainActor
    func testValidateValidTemplate() async throws {
        // Given
        let templateURL = try loadTestResource(named: "simple-hello.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "validate",
            arguments: [templateURL.path]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("Valid"))
        #expect(result.stdout.contains(templateURL.lastPathComponent))
    }

    @Test("Validate command - verbose output")
    @MainActor
    func testValidateVerboseOutput() async throws {
        // Given
        let templateURL = try loadTestResource(named: "with-expressions.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "validate",
            arguments: [
                templateURL.path,
                "--verbose"
            ]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("Valid"))
        #expect(result.stdout.contains("Module:"))
        #expect(result.stdout.contains("Templates:"))
    }

    @Test("Validate command - invalid template")
    @MainActor
    func testValidateInvalidTemplate() async throws {
        // Given
        let templateURL = try loadTestResource(named: "invalid-syntax.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "validate",
            arguments: [templateURL.path]
        )

        // Then
        #expect(!result.succeeded)
        #expect(result.stdout.contains(templateURL.lastPathComponent))
    }

    @Test("Validate command - multiple templates")
    @MainActor
    func testValidateMultipleTemplates() async throws {
        // Given
        let valid1 = try loadTestResource(named: "simple-hello.mtl", subdirectory: "templates")
        let valid2 = try loadTestResource(named: "with-expressions.mtl", subdirectory: "templates")
        let invalid = try loadTestResource(named: "invalid-syntax.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "validate",
            arguments: [
                valid1.path,
                valid2.path,
                invalid.path
            ]
        )

        // Then
        #expect(!result.succeeded)
        #expect(result.stdout.contains("simple-hello.mtl"))
        #expect(result.stdout.contains("with-expressions.mtl"))
        #expect(result.stdout.contains("invalid-syntax.mtl"))
    }

    @Test("Validate command - file not found")
    @MainActor
    func testValidateFileNotFound() async throws {
        // When
        let result = try await executeSwiftMTL(
            command: "validate",
            arguments: ["/nonexistent/template.mtl"]
        )

        // Then
        #expect(!result.succeeded)
        #expect(result.stdout.contains("File not found"))
    }

    @Test("Validate command - all valid templates")
    @MainActor
    func testValidateAllValid() async throws {
        // Given
        let template1 = try loadTestResource(named: "simple-hello.mtl", subdirectory: "templates")
        let template2 = try loadTestResource(named: "with-expressions.mtl", subdirectory: "templates")
        let template3 = try loadTestResource(named: "with-control-flow.mtl", subdirectory: "templates")

        // When
        let result = try await executeSwiftMTL(
            command: "validate",
            arguments: [
                template1.path,
                template2.path,
                template3.path
            ]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("Valid") || !result.stdout.contains("Error"))
    }

    // MARK: - Help and Version Tests

    @Test("Help command")
    @MainActor
    func testHelpCommand() async throws {
        // When
        let result = try await executeSwiftMTL(
            command: "--help",
            arguments: []
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("swift-mtl"))
        #expect(result.stdout.contains("USAGE:"))
        #expect(result.stdout.contains("generate"))
        #expect(result.stdout.contains("parse"))
        #expect(result.stdout.contains("validate"))
    }

    @Test("Version command")
    @MainActor
    func testVersionCommand() async throws {
        // When
        let result = try await executeSwiftMTL(
            command: "--version",
            arguments: []
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("1.0"))
    }

    @Test("Generate help")
    @MainActor
    func testGenerateHelp() async throws {
        // When
        let result = try await executeSwiftMTL(
            command: "generate",
            arguments: ["--help"]
        )

        // Then
        #expect(result.succeeded)
        #expect(result.stdout.contains("generate"))
        #expect(result.stdout.contains("--model"))
        #expect(result.stdout.contains("--output"))
        #expect(result.stdout.contains("--template"))
    }
}
