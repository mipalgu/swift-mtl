//
//  MTLCommentAndHeaderTests.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import Testing

@testable import MTL

@Suite("MTL Comment and Header Syntax")
struct MTLCommentAndHeaderTests {

    // MARK: - Comments

    @Test("Encoding comment before the module header sets the encoding")
    func encodingComment() async throws {
        let module = try await MTLTestSupport.parse("""
            [comment encoding = ISO-8859-1 /]
            [module m('http://example.com')/]
            """)
        #expect(module.encoding == "ISO-8859-1")
        #expect(module.name == "m")
    }

    @Test("Encoding comment after the module header sets the encoding")
    func encodingCommentAfterHeader() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('http://example.com')/]
            [comment encoding = UTF-16 /]
            """)
        #expect(module.encoding == "UTF-16")
    }

    @Test("Encoding defaults to UTF-8")
    func defaultEncoding() async throws {
        let module = try await MTLTestSupport.parse("[module m('http://example.com')/]")
        #expect(module.encoding == "UTF-8")
    }

    @Test("A line comment produces an MTLComment and no output")
    @MainActor
    func lineComment() async throws {
        let source = """
            [module m('http://example.com')/]
            [template main()]
            before[comment this is ignored /]after
            [/template]
            """
        let module = try await MTLTestSupport.parse(source)
        let statements = module.templates["main"]!.body.statements
        #expect(statements.contains { $0 is MTLComment })
        let output = try await MTLTestSupport.output(source)
        #expect(output == "beforeafter\n")
    }

    @Test("A comment may contain brackets and expression syntax")
    @MainActor
    func commentWithBrackets() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            x[comment see [1] and (nothing) /]y
            [/template]
            """)
        #expect(output == "xy\n")
    }

    @Test("A block comment produces no output and may span lines")
    @MainActor
    func blockComment() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            [comment]
            Several lines
            of [documentation]
            [/comment]
            text
            [/template]
            """)
        #expect(output == "text\n")
    }

    @Test("A block comment may appear between declarations")
    func blockCommentAtModuleLevel() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [comment]
              Documentation of the module.
            [/comment]
            [template main()]x[/template]
            """)
        #expect(module.templates["main"] != nil)
    }

    @Test("The old bracket-dash-dash comment still works in templates")
    @MainActor
    func dashDashComment() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]
            a[-- ignored]b
            [/template]
            """)
        #expect(output == "ab\n")
    }

    @Test("An unterminated line comment is a syntax error")
    func unterminatedLineComment() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse("[module m('u')/][comment never ends]")
        }
    }

    @Test("An unterminated block comment is a syntax error")
    func unterminatedBlockComment() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse("[module m('u')/][comment] never ends")
        }
    }

    @Test("A comment marker inside a template marks it as main")
    func mainAnnotation() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template public run(x : String)]
            [comment @main /]
            body
            [/template]
            [template other(x : String)]body[/template]
            """)
        #expect(module.templates["run"]?.isMain == true)
        #expect(module.templates["other"]?.isMain == false)
    }

    @Test("A documentation comment is attached to the declaration and may mark main")
    func documentationComment() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [**
             * Generates the thing.
             * @main
             **/]
            [template public run(x : String)]body[/template]
            [query helper(x : String) : String = x/]
            """)
        let template = module.templates["run"]!
        #expect(template.isMain)
        #expect(template.documentation?.contains("Generates the thing.") == true)
        #expect(module.queries["helper"]?.documentation == nil)
    }

    // MARK: - Module Header

    @Test("The module header records every metamodel URI")
    func multipleMetamodelURIs() async throws {
        let module = try await MTLTestSupport.parse("[module m('http://a', 'http://b')/]")
        #expect(module.metamodelURIs == ["http://a", "http://b"])
    }

    @Test("The module header may end with a slash or without")
    func headerWithAndWithoutSlash() async throws {
        let withSlash = try await MTLTestSupport.parse("[module m('http://a')/]")
        let withoutSlash = try await MTLTestSupport.parse("[module m('http://a')]")
        #expect(withSlash.metamodelURIs == ["http://a"])
        #expect(withoutSlash.metamodelURIs == ["http://a"])
    }

    @Test("The module header records the extended module")
    func headerExtends() async throws {
        let plain = try await MTLTestSupport.parse("[module m('u') extends base/]")
        #expect(plain.extends == "base")
        let qualified = try await MTLTestSupport.parse("[module m('u') extends other::module::base]")
        #expect(qualified.extends == "other::module::base")
    }

    @Test("The module header requires a metamodel URI")
    func headerWithoutURI() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse("[module m()/]")
        }
    }

    @Test("The module header requires a closing bracket")
    func headerWithoutClosingBracket() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse("[module m('u')")
        }
    }

    @Test("Imports are recorded in order, with or without slash")
    func importDeclarations() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [import a::b::common /]
            [import other]
            [template main()]x[/template]
            """)
        #expect(module.imports == ["a::b::common", "other"])
    }

    @Test("An extends declaration after the header is recorded")
    func extendsDeclaration() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [extends base/]
            """)
        #expect(module.extends == "base")
    }

    @Test("An import without a name is a syntax error")
    func importWithoutName() async {
        await #expect(throws: MTLParseError.self) {
            try await MTLTestSupport.parse("[module m('u')/][import /]")
        }
    }
}

@Suite("MTL Metamodel Binding")
struct MTLMetamodelBindingTests {

    @Test("Header URIs are unbound until packages are supplied")
    func unboundInitially() async throws {
        let module = try await MTLTestSupport.parse("[module m('http://a', 'http://b')/]")
        #expect(module.metamodels.isEmpty)
        #expect(module.unboundMetamodelURIs == ["http://a", "http://b"])
    }

    @Test("Packages are bound by namespace URI, including subpackages")
    func bindsByNamespaceURI() async throws {
        let module = try await MTLTestSupport.parse("[module m('http://a', 'http://b', 'http://c')/]")
        let nested = EPackage(name: "nested", nsURI: "http://b")
        let root = EPackage(name: "root", nsURI: "http://a", eSubpackages: [nested])
        let unrelated = EPackage(name: "other", nsURI: "http://other")

        let bound = module.binding(to: [root, unrelated])
        #expect(Array(bound.metamodels.keys) == ["root", "nested"])
        #expect(bound.metamodels["nested"]?.nsURI == "http://b")
        #expect(bound.unboundMetamodelURIs == ["http://c"])
        #expect(bound.metamodelURIs == module.metamodelURIs)
    }
}
