//
//  MTLProtectedAreaTests.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Foundation
import Testing
@testable import MTL
import AQL

@Suite("MTL Protected Area Tests")
struct MTLProtectedAreaTests {

    // MARK: - Protected Area Manager

    @Test("Protected area manager stores and retrieves content")
    func testProtectedAreaManager() async {
        let manager = MTLProtectedAreaManager()

        // Store content
        await manager.setContent(
            "area1",
            content: "User code here",
            markers: ("START", "END")
        )

        // Retrieve content
        let content = await manager.getContent("area1")
        #expect(content == "User code here")
    }

    @Test("Protected area manager returns nil for unknown ID")
    func testProtectedAreaManagerUnknown() async {
        let manager = MTLProtectedAreaManager()

        let content = await manager.getContent("unknown")
        #expect(content == nil)
    }

    @Test("Protected area manager generates markers")
    func testGenerateMarkers() async {
        let manager = MTLProtectedAreaManager()

        let markers = await manager.generateMarkers(id: "test123", prefix: "//")
        #expect(markers.0.contains("test123"))
        #expect(markers.1.contains("test123"))
        #expect(markers.0.hasPrefix("//"))
        #expect(markers.1.hasPrefix("//"))
    }

    @Test("Protected area manager scans file content")
    func testScanFile() async throws {
        let manager = MTLProtectedAreaManager()

        // Create temporary file with protected area
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("mtl-test-\(UUID().uuidString).txt").path
        let content = """
        Generated code
        // START PROTECTED REGION area1
        User code preserved
        // END PROTECTED REGION area1
        More generated code
        """

        try content.write(toFile: tempFile, atomically: true, encoding: .utf8)

        // Scan file
        try await manager.scanFile(tempFile)

        // Check preserved content
        let preserved = await manager.getContent("area1")
        #expect(preserved != nil)
        #expect(preserved?.contains("User code preserved") == true)

        // Clean up
        try? FileManager.default.removeItem(atPath: tempFile)
    }

    // MARK: - Protected Area Statement

    @Test("Protected area statement preserves existing content")
    @MainActor
    func testProtectedAreaPreservation() async throws {
        let module = MTLModule(
            name: "Test",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        // Set existing protected content
        await context.setProtectedAreaContent("myArea", content: "PRESERVED CONTENT")

        // Execute protected area statement
        let stmt = MTLProtectedArea(
            id: MTLExpression(AQLLiteralExpression(value: "myArea")),
            startTagPrefix: MTLExpression(AQLLiteralExpression(value: "//")),
            endTagPrefix: MTLExpression(AQLLiteralExpression(value: "//")),
            body: MTLBlock(statements: [
                MTLTextStatement(value: "DEFAULT CONTENT")
            ], inlined: false)
        )

        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output.contains("PRESERVED CONTENT"))
        #expect(!output.contains("DEFAULT CONTENT"))
    }

    @Test("Protected area statement uses default when no preserved content")
    @MainActor
    func testProtectedAreaDefault() async throws {
        let module = MTLModule(
            name: "Test",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        // Execute protected area statement with no preserved content
        let stmt = MTLProtectedArea(
            id: MTLExpression(AQLLiteralExpression(value: "newArea")),
            startTagPrefix: MTLExpression(AQLLiteralExpression(value: "//")),
            endTagPrefix: MTLExpression(AQLLiteralExpression(value: "//")),
            body: MTLBlock(statements: [
                MTLTextStatement(value: "DEFAULT CONTENT")
            ], inlined: false)
        )

        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output.contains("DEFAULT CONTENT"))
    }

    @Test("Protected area statement includes markers")
    @MainActor
    func testProtectedAreaMarkers() async throws {
        let module = MTLModule(
            name: "Test",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        let stmt = MTLProtectedArea(
            id: MTLExpression(AQLLiteralExpression(value: "markerTest")),
            startTagPrefix: MTLExpression(AQLLiteralExpression(value: "//")),
            endTagPrefix: MTLExpression(AQLLiteralExpression(value: "//")),
            body: MTLBlock(statements: [
                MTLTextStatement(value: "Content")
            ], inlined: false)
        )

        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output.contains("PROTECTED REGION"))
        #expect(output.contains("markerTest"))
        #expect(output.contains("START"))
        #expect(output.contains("END"))
    }

    @Test("Protected area without markers uses default prefix")
    @MainActor
    func testProtectedAreaWithoutMarkers() async throws {
        let module = MTLModule(
            name: "Test",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let strategy = MTLInMemoryStrategy()
        let context = MTLExecutionContext(
            module: module,
            generationStrategy: strategy
        )

        // Execute protected area without explicit markers (uses defaults)
        let stmt = MTLProtectedArea(
            id: MTLExpression(AQLLiteralExpression(value: "testArea")),
            body: MTLBlock(statements: [
                MTLTextStatement(value: "CONTENT")
            ], inlined: false)
        )

        try await stmt.execute(in: context)

        let output = await context.getGeneratedText()
        #expect(output.contains("CONTENT"))
        #expect(output.contains("PROTECTED REGION"))
        #expect(output.contains("testArea"))
    }
}
