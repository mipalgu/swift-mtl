//
//  MTLMultiLevelTests.swift
//  MTLMultiLevelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import AQL
import AQLMultiLevel
import ECore
import EMFBase
import MultiLevel
import Testing

@testable import MTL

/// Tests MTL templates over deep level views: deep queries, deep template dispatch and the
/// deep services, without changes to the MTL generator.
@Suite("MTL deep generation")
@MainActor
struct MTLDeepGenerationTests {
    static let products = """
        Model Commerce@2 {
          Node ProductType {
            vat@1 : double = 7.5;
            price : double = 10.0;
          }
        }

        Commerce BookStore {
          ProductType Book {
            vat = 4.0;
          }
          ProductType Disc {
            vat = 10.0;
          }
        }

        BookStore Shop {
          Book patterns {
            price = 35.0;
          }
          Disc album {
            price = 20.0;
          }
          Book draft {}
        }
        """

    /// Generates text from a template over the deep view of level 0.
    func generate(_ template: String) async throws -> String? {
        let result = MetaDepthReader.parse(Self.products)
        let model = try #require(result.model)
        let views = try await model.deepLevelViews(in: ResourceSet())
        let view = try #require(views.last)
        let module = try await MTLParser().parse(template, filename: "deep.mtl")
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(
            module: module, generationStrategy: strategy, options: .standard,
            serviceProviders: [AQLMultiLevelServices(views: views)])
        let first = await view.resource.resolve(try #require(model.clabject(named: "patterns")).id)
        try await generator.generate(mainTemplate: "main", arguments: [first], models: ["shop": view.resource])
        return await strategy.getGeneratedFiles()["stdout"]
    }

    @Test("a query over a level-2 type finds its deep instances at level 0")
    func deepQuery() async throws {
        let text = try await generate("""
            [module deep('urn:swift-ecore:multilevel:view:Commerce:Shop:deep')/]
            [template public main(any : BookStore::ProductType)][for (p | BookStore::ProductType.allInstances()->sortedBy(x | x.clabjectName())) separator(',')][p.clabjectName()/][/for][/template]
            """)
        #expect(text == "album,draft,patterns")
    }

    @Test("template overloads dispatch on the nearest deep type")
    func deepDispatch() async throws {
        let text = try await generate("""
            [module deep('urn:swift-ecore:multilevel:view:Commerce:Shop:deep')/]
            [template public main(any : BookStore::ProductType)][for (p | BookStore::ProductType.allInstances()->sortedBy(x | x.clabjectName())) separator(',')][describe(p)/][/for][/template]
            [template public describe(p : BookStore::ProductType)]product [p.clabjectName()/][/template]
            [template public describe(p : BookStore::Book)]book [p.clabjectName()/][/template]
            """)
        #expect(text == "product album,book draft,book patterns")
    }

    @Test("type-level slots and deep services are available to templates")
    func deepServices() async throws {
        let text = try await generate("""
            [module deep('urn:swift-ecore:multilevel:view:Commerce:Shop:deep')/]
            [template public main(any : BookStore::ProductType)][any.ontologicalType().name/]:[any.level()/]:[any.typeAtLevel(1).clabjectName()/]:[if (any.vat = 4.0)]reduced[else]standard[/if][/template]
            """)
        #expect(text == "Book:0:Book:reduced")
    }
}
