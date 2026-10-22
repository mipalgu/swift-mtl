//
// MTLParameterServicesTests.swift
// MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import MTL

/// Tests for the services that give templates access to named parameters.
@Suite("MTL Parameter Services")
struct MTLParameterServicesTests {

    @Test("Values are typed as Boolean, Integer or String")
    func typing() throws {
        let services = try MTLParameterServices(arguments: ["a=true", "b=false", "c=42", "d=042", "e=x=y", "f=-7", "g="])
        #expect(services.values["a"] as? Bool == true)
        #expect(services.values["b"] as? Bool == false)
        #expect(services.values["c"] as? Int == 42)
        #expect(services.values["d"] as? String == "042")
        #expect(services.values["e"] as? String == "x=y")
        #expect(services.values["f"] as? Int == -7)
        #expect(services.values["g"] as? String == "")
    }

    @Test("Parsing splits at the first equals sign")
    func parsing() throws {
        let (name, value) = try MTLParameterServices.parse("package=org.example")
        #expect(name == "package")
        #expect(value as? String == "org.example")
    }

    @Test("A later argument replaces an earlier one")
    func laterWins() throws {
        let services = try MTLParameterServices(arguments: ["a=1", "a=2"])
        #expect(services.values["a"] as? Int == 2)
    }

    @Test("Text without a name or equals sign is rejected")
    func malformed() {
        for text in ["novalue", "=value", ""] {
            #expect(throws: MTLParameterError.invalidParameter(text)) { try MTLParameterServices.parse(text) }
        }
    }

    @Test("Names must be identifiers")
    func invalidNames() {
        for name in ["1a", "a-b", "a b", "a.b"] {
            #expect(throws: MTLParameterError.invalidParameterName(name)) {
                try MTLParameterServices.parse("\(name)=1")
            }
        }
    }

    @Test("Reserved words are rejected")
    func reservedNames() {
        for name in ["module", "self", "true", "Sequence"] {
            #expect(throws: MTLParameterError.reservedParameterName(name)) {
                try MTLParameterServices(values: [name: 1])
            }
        }
    }

    @Test("Errors describe the problem")
    func messages() {
        #expect(MTLParameterError.invalidParameter("x").errorDescription?.contains("name=value") == true)
        #expect(MTLParameterError.invalidParameterName("1a").errorDescription?.contains("identifier") == true)
        #expect(MTLParameterError.reservedParameterName("module").errorDescription?.contains("reserved") == true)
    }

    @Test("Typed values are kept")
    func typedValues() throws {
        let services = try MTLParameterServices(values: ["n": 3, "s": "t"])
        #expect(services.values["n"] as? Int == 3)
        #expect(services.values["s"] as? String == "t")
    }

    @Test("Bound parameters are readable as variables and services")
    @MainActor
    func binding() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template main()][package/]|[n + 1/]|[parameter('package')/]|[hasParameter('n')/]|[hasParameter('zz')/]|[if (verbose)]V[/if][/template]
            """)
        let services = try MTLParameterServices(arguments: ["package=org.x", "n=4", "verbose=true"])
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        services.bind(to: generator)
        generator.register(services)
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        let text = await strategy.getGeneratedFiles()[MTLTestSupport.standardOutput] ?? ""
        #expect(text == "org.x|5|org.x|true|false|V")
    }

    @Test("An unknown parameter reads as null")
    @MainActor
    func unknownParameter() async throws {
        let module = try await MTLTestSupport.parse(
            "[module m('u')/]\n[template main()][parameter('nope').oclIsUndefined()/][/template]")
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        generator.register(try MTLParameterServices(parameters: [:]))
        try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
    }
}
