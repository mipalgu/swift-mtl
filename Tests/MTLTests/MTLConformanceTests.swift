//
//  MTLConformanceTests.swift
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

@Suite("MTL Conformance")
struct MTLConformanceTests {

    /// Fixtures that are deliberately malformed and must be rejected.
    private static let malformedFixtures: Set<String> = [
        "invalid-syntax.mtl", "missing-module.mtl", "unclosed-block.mtl"
    ]

    /// The package directory, derived from the location of this file.
    private static var packageDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// The directory of the example templates.
    private static var examplesDirectory: URL {
        packageDirectory.appendingPathComponent("Examples")
    }

    /// Lists the `.mtl` files below a directory.
    private static func templates(below directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == MTLSyntax.moduleFileExtension }
            .sorted { $0.path < $1.path }
    }

    @Test("Every well-formed test fixture parses")
    func fixturesParse() async throws {
        let files = Self.templates(below: MTLTestSupport.resource(""))
            .filter { !Self.malformedFixtures.contains($0.lastPathComponent) }
        #expect(files.count >= 20)
        for file in files {
            do {
                _ = try await MTLParser().parseWithoutLinking(file)
            } catch {
                Issue.record("\(file.lastPathComponent) failed to parse: \(error)")
            }
        }
    }

    @Test("The malformed fixtures are rejected")
    func malformedFixturesRejected() async throws {
        let files = Self.templates(below: MTLTestSupport.resource("templates"))
            .filter { Self.malformedFixtures.contains($0.lastPathComponent) }
        #expect(files.count == Self.malformedFixtures.count)
        for file in files {
            await #expect(throws: MTLParseError.self) {
                _ = try await MTLParser().parseWithoutLinking(file)
            }
        }
    }

    @Test("Every example template parses")
    func examplesParse() async throws {
        let files = Self.templates(below: Self.examplesDirectory)
        #expect(files.count >= 7)
        for file in files {
            do {
                _ = try await MTLParser().parseWithoutLinking(file)
            } catch {
                Issue.record("\(file.lastPathComponent) failed to parse: \(error)")
            }
        }
    }

    @Test("Every example template runs and produces output")
    @MainActor
    func examplesRun() async throws {
        for file in Self.templates(below: Self.examplesDirectory) {
            do {
                let module = try await MTLParser().parse(file)
                let files = try await MTLTestSupport.run(module)
                #expect(!files.isEmpty, "\(file.lastPathComponent) generated nothing")
            } catch {
                Issue.record("\(file.lastPathComponent) failed to run: \(error)")
            }
        }
    }

    @Test("The example outputs are as documented")
    @MainActor
    func exampleOutputs() async throws {
        func output(_ name: String, file: String = MTLTestSupport.standardOutput) async throws -> String {
            let module = try await MTLParser().parse(Self.examplesDirectory.appendingPathComponent(name))
            return try await MTLTestSupport.run(module)[file] ?? ""
        }

        let expressions = try await output("02-expressions.mtl")
        #expect(expressions.contains("5 + 3 = 8"))
        #expect(expressions.contains("Version: 1.0.0"))
        #expect(expressions.contains("Sum: 30"))

        let queries = try await output("05-queries.mtl")
        #expect(queries.contains("Square of 5: 25"))
        #expect(queries.contains("Is 4 even? true"))
        #expect(queries.contains("Is 7 even? false"))

        let macros = try await output("06-macros.mtl")
        #expect(macros.contains("```swift\nfunc greet"))
        #expect(macros.contains("*** emphasize important text ***"))

        let control = try await output("03-control-flow.mtl")
        #expect(control.contains("Value is between 10 and 20 (current: 15)"))
        #expect(control.contains("Full Name: John Doe"))

        let greeting = try await output("04-file-blocks.mtl", file: "greeting.txt")
        #expect(greeting.hasPrefix("Hello from MTL!\n"))
    }

    @Test("The Acceleo feature fixture runs")
    @MainActor
    func acceleoFeaturesRun() async throws {
        let module = try await MTLParser().parse(MTLTestSupport.resource("conformance/acceleo-features.mtl"))
        #expect(module.metamodelURIs.count == 2)
        #expect(module.templates["main"]?.isMain == true)
        let files = try await MTLTestSupport.run(module)
        let output = try #require(files[MTLTestSupport.standardOutput])
        #expect(output.contains("label:x many (1=1, 2=2, 3=3)"), "\(output)")
        #expect(output.contains("[inner]"))
        #expect(files["features.txt"] == "2\n")
    }

    @Test("The LLFSM templates still parse")
    func llfsmTemplatesParse() async throws {
        let files = Self.templates(below: MTLTestSupport.resource("conformance"))
            .filter { $0.lastPathComponent.hasPrefix("llfsm2") }
        #expect(files.count == 8)
        for file in files {
            let module = try await MTLParser().parseWithoutLinking(file)
            #expect(module.templates["main"] != nil, "\(file.lastPathComponent) has no main template")
        }
    }
}

@Suite("MTL LLFSM Regression")
struct MTLLLFSMRegressionTests {

    /// The generated file extension for each LLFSM template.
    private static let templates: [(template: String, fileExtension: String)] = [
        ("llfsm2c", "c"), ("llfsm2dot", "dot"), ("llfsm2lisp", "lisp"), ("llfsm2mips", "asm"),
        ("llfsm2nusmv", "smv"), ("llfsm2prism", "pm"), ("llfsm2tla", "tla"), ("llfsm2uppaal", "xml")
    ]

    private static let modelName = "PingPongTikiTakaForC"

    /// The lines of a text that contain anything other than white space.
    private static func significantLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.allSatisfy(\.isWhitespace) }
    }

    @Test("The LLFSM templates generate the recorded output apart from blank lines", arguments: templates.map(\.template))
    @MainActor
    func generatesRecordedOutput(template: String) async throws {
        let fileExtension = try #require(Self.templates.first { $0.template == template }?.fileExtension)

        let resourceSet = ResourceSet()
        let package = try await EPackage(url: MTLTestSupport.resource("llfsm/newGITmetamodelwithtypes.ecore"))
        await resourceSet.registerMetamodel(package, uri: package.nsURI)
        let resource = try await XMIParser(resourceSet: resourceSet)
            .parse(MTLTestSupport.resource("llfsm/\(Self.modelName).xmi"))
        let roots = await resource.getRootObjects().map { Optional($0) }

        let module = try await MTLParser().parse(MTLTestSupport.resource("conformance/\(template).mtl"))
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.generate(mainTemplate: "main", arguments: roots, models: [Self.modelName: resource])

        let files = await strategy.getGeneratedFiles()
        let generated = try #require(files["\(Self.modelName).\(fileExtension)"])
        let recorded = try String(
            contentsOf: MTLTestSupport.resource("llfsm/\(Self.modelName).\(fileExtension)"), encoding: .utf8)

        #expect(Self.significantLines(generated) == Self.significantLines(recorded))
        #expect(generated.hasPrefix("\n") == false, "block tag lines must not leave a leading blank line")
    }
}
