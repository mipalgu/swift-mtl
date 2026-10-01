//
//  MTLTemplateHeaderTests.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import MTL

@Suite("MTL Template Header Syntax")
struct MTLTemplateHeaderTests {

    // MARK: - Visibility

    @Test("Templates carry their declared visibility", arguments: [
        ("public", MTLVisibility.public),
        ("protected", MTLVisibility.protected),
        ("private", MTLVisibility.private)
    ])
    func visibility(keyword: String, expected: MTLVisibility) async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template \(keyword) t(x : String)]body[/template]
            """)
        #expect(module.templates["t"]?.visibility == expected)
    }

    @Test("A template without visibility is public")
    func defaultVisibility() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/][template t()]x[/template]")
        #expect(module.templates["t"]?.visibility == .public)
    }

    @Test("A visibility keyword followed by a parenthesis is the template name")
    func visibilityKeywordAsName() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/][template public()]x[/template]")
        #expect(module.templates["public"]?.visibility == .public)
    }

    @Test("Queries carry their declared visibility")
    func queryVisibility() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [query private secret(x : String) : String = x/]
            [query protected shared(x : String) : String = x/]
            """)
        #expect(module.queries["secret"]?.visibility == .private)
        #expect(module.queries["shared"]?.visibility == .protected)
    }

    // MARK: - Guard

    @Test("The question mark guard selects whether the body runs")
    @MainActor
    func questionMarkGuard() async throws {
        let source = """
            [module m('u')/]
            [template main(x : Integer) ? (x > 1)]big[/template]
            """
        #expect(try await MTLTestSupport.output(source, arguments: [5]) == "big")
        #expect(try await MTLTestSupport.output(source, arguments: [0]) == "")
    }

    @Test("The guard keyword form still works")
    @MainActor
    func guardKeyword() async throws {
        let source = """
            [module m('u')/]
            [template main(x : Integer) guard (x > 1)]big[/template]
            """
        #expect(try await MTLTestSupport.output(source, arguments: [5]) == "big")
        #expect(try await MTLTestSupport.output(source, arguments: [0]) == "")
    }

    @Test("A guard is recorded on the template")
    func guardRecorded() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template t(x : Integer) ? (x > 1)]b[/template]
            """)
        #expect(module.templates["t"]?.guard != nil)
        #expect(module.templates["t"]?.post == nil)
    }

    @Test("A duplicate guard is a syntax error")
    func duplicateGuard() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse("""
                [module m('u')/]
                [template t(x : Integer) ? (x > 1) ? (x > 2)]b[/template]
                """)
        }
    }

    // MARK: - Post

    @Test("A post expression is applied to the generated text")
    @MainActor
    func postTrim() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main() post (trim())]   padded   [/template]
            """)
        #expect(output == "padded")
    }

    @Test("A post expression applies to text captured from a call")
    @MainActor
    func postOnCall() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template inner() post (trim())]  inner  [/template]
            [template main()]<[inner()/]>[/template]
            """)
        #expect(output == "<inner>")
    }

    @Test("A post expression may use the generated text as self")
    @MainActor
    func postUsesSelf() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main() post (self + '!')]hi[/template]
            """)
        #expect(output == "hi!")
    }

    @Test("A Boolean post expression acts as a post-condition")
    @MainActor
    func postCondition() async throws {
        let failing = """
            [module m('u')/]
            [template main() post (false)]hi[/template]
            """
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.output(failing)
        }
        let passing = """
            [module m('u')/]
            [template main() post (true)]hi[/template]
            """
        #expect(try await MTLTestSupport.output(passing) == "hi")
    }

    @Test("Guard, post and overrides may appear in any order")
    func clausesInAnyOrder() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template public t(x : String) post (trim()) overrides base ? (true)]b[/template]
            """)
        let template = try #require(module.templates["t"])
        #expect(template.guard != nil)
        #expect(template.post != nil)
        #expect(template.overrides == "base")
    }

    @Test("Overrides may name a qualified template")
    func overridesQualified() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u') extends base/]
            [template public t(x : String) overrides base::t]b[/template]
            """)
        #expect(module.templates["t"]?.overrides == "base::t")
    }

    // MARK: - Parameters and Types

    @Test("Parameter types may be qualified or have element types")
    func parameterTypes() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template t(c : ecore::EClass, names : Sequence(String), n : OrderedSet(ecore::EClass))]b[/template]
            """)
        let types = module.templates["t"]?.parameters.map(\.type)
        #expect(types == ["ecore::EClass", "Sequence(String)", "OrderedSet(ecore::EClass)"])
    }

    @Test("A parameter without a type is a syntax error")
    func parameterWithoutType() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse("[module m('u')/][template t(x)]b[/template]")
        }
    }

    // MARK: - Overloading

    @Test("Templates with different parameter types are overloads")
    func overloadsParsed() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template t(x : String)]s[/template]
            [template t(x : Integer)]i[/template]
            """)
        #expect(module.templates(named: "t").count == 2)
        #expect(module.templateOverloads.count == 1)
    }

    @Test("Templates with identical signatures are duplicates")
    func duplicateTemplate() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse("""
                [module m('u')/]
                [template t(x : String)]a[/template]
                [template t(y : String)]b[/template]
                """)
        }
    }

    @Test("Queries with different parameter types are overloads")
    func queryOverloadsParsed() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [query q(x : String) : String = 's'/]
            [query q(x : Integer) : String = 'i'/]
            """)
        #expect(module.queries(named: "q").count == 2)
    }

    @Test("Overloads are selected by the type of the argument")
    @MainActor
    func overloadByPrimitiveType() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template describe(x : String)]string[/template]
            [template describe(x : Integer)]integer[/template]
            [template describe(x : Boolean)]boolean[/template]
            [template main()][describe('a')/],[describe(1)/],[describe(true)/][/template]
            """)
        #expect(output == "string,integer,boolean")
    }

    @Test("Overloads on metaclasses pick the most specific one")
    @MainActor
    func overloadByMetaclass() async throws {
        let animal = EClass(name: "Animal")
        let dog = EClass(name: "Dog", eSuperTypes: [animal])
        let puppy = EClass(name: "Puppy", eSuperTypes: [dog])
        let source = """
            [module m('u')/]
            [template describe(x : Animal)]animal[/template]
            [template describe(x : Dog)]dog[/template]
            [template main(x : OclAny)][describe(x)/][/template]
            """
        #expect(try await MTLTestSupport.output(source, arguments: [DynamicEObject(eClass: animal)]) == "animal")
        #expect(try await MTLTestSupport.output(source, arguments: [DynamicEObject(eClass: dog)]) == "dog")
        #expect(try await MTLTestSupport.output(source, arguments: [DynamicEObject(eClass: puppy)]) == "dog")
    }
}
