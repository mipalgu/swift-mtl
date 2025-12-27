//
//  MTLModuleTests.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//

import Testing
@testable import MTL
import AQL

@Suite("MTL Module Tests")
struct MTLModuleTests {

    // MARK: - Module Creation

    @Test("Create simple module")
    func testSimpleModule() {
        let module = MTLModule(
            name: "TestModule",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        #expect(module.name == "TestModule")
        #expect(module.encoding == "UTF-8")
        #expect(module.templates.isEmpty)
        #expect(module.queries.isEmpty)
        #expect(module.macros.isEmpty)
    }

    @Test("Module with templates")
    func testModuleWithTemplates() {
        let template = MTLTemplate(
            name: "test",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [], inlined: false),
            isMain: false,
            overrides: nil,
            documentation: nil
        )

        let module = MTLModule(
            name: "TestModule",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: ["test": template],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        #expect(module.templates.count == 1)
        #expect(module.templates["test"]?.name == "test")
    }

    @Test("Module with queries")
    func testModuleWithQueries() {
        let query = MTLQuery(
            name: "testQuery",
            visibility: .public,
            parameters: [],
            returnType: "String",
            body: MTLExpression(AQLLiteralExpression(value: "result")),
            documentation: nil
        )

        let module = MTLModule(
            name: "TestModule",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: ["testQuery": query],
            macros: [:],
            encoding: "UTF-8"
        )

        #expect(module.queries.count == 1)
        #expect(module.queries["testQuery"]?.name == "testQuery")
    }

    @Test("Module with macros")
    func testModuleWithMacros() {
        let macro = MTLMacro(
            name: "testMacro",
            parameters: [],
            bodyParameter: nil,
            body: MTLBlock(statements: [], inlined: false),
            documentation: nil
        )

        let module = MTLModule(
            name: "TestModule",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: ["testMacro": macro],
            encoding: "UTF-8"
        )

        #expect(module.macros.count == 1)
        #expect(module.macros["testMacro"]?.name == "testMacro")
    }

    @Test("Module with extends")
    func testModuleWithExtends() {
        let module = MTLModule(
            name: "ChildModule",
            metamodels: [:],
            extends: "ParentModule",
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        #expect(module.extends == "ParentModule")
    }

    @Test("Module with imports")
    func testModuleWithImports() {
        let module = MTLModule(
            name: "TestModule",
            metamodels: [:],
            extends: nil,
            imports: ["Module1", "Module2"],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        #expect(module.imports.count == 2)
        #expect(module.imports.contains("Module1"))
        #expect(module.imports.contains("Module2"))
    }

    // MARK: - Template Tests

    @Test("Template creation")
    func testTemplateCreation() {
        let template = MTLTemplate(
            name: "myTemplate",
            visibility: .public,
            parameters: [
                MTLVariable(name: "param1", type: "String")
            ],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [
                MTLTextStatement(value: "Hello")
            ], inlined: false),
            isMain: true,
            overrides: nil,
            documentation: "Test template"
        )

        #expect(template.name == "myTemplate")
        #expect(template.visibility == .public)
        #expect(template.parameters.count == 1)
        #expect(template.parameters[0].name == "param1")
        #expect(template.isMain == true)
        #expect(template.documentation == "Test template")
    }

    @Test("Template with guard")
    func testTemplateWithGuard() {
        let template = MTLTemplate(
            name: "guarded",
            visibility: .public,
            parameters: [],
            guard: MTLExpression(AQLLiteralExpression(value: true)),
            post: nil,
            body: MTLBlock(statements: [], inlined: false),
            isMain: false,
            overrides: nil,
            documentation: nil
        )

        #expect(template.guard != nil)
    }

    @Test("Template with post condition")
    func testTemplateWithPost() {
        let template = MTLTemplate(
            name: "posted",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: MTLExpression(AQLLiteralExpression(value: true)),
            body: MTLBlock(statements: [], inlined: false),
            isMain: false,
            overrides: nil,
            documentation: nil
        )

        #expect(template.post != nil)
    }

    @Test("Template visibility levels")
    func testTemplateVisibility() {
        let publicTemplate = MTLTemplate(
            name: "public",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [], inlined: false),
            isMain: false,
            overrides: nil,
            documentation: nil
        )

        let protectedTemplate = MTLTemplate(
            name: "protected",
            visibility: .protected,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [], inlined: false),
            isMain: false,
            overrides: nil,
            documentation: nil
        )

        let privateTemplate = MTLTemplate(
            name: "private",
            visibility: .private,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [], inlined: false),
            isMain: false,
            overrides: nil,
            documentation: nil
        )

        #expect(publicTemplate.visibility == .public)
        #expect(protectedTemplate.visibility == .protected)
        #expect(privateTemplate.visibility == .private)
    }

    // MARK: - Query Tests

    @Test("Query creation")
    func testQueryCreation() {
        let query = MTLQuery(
            name: "myQuery",
            visibility: .public,
            parameters: [
                MTLVariable(name: "input", type: "String")
            ],
            returnType: "Integer",
            body: MTLExpression(AQLLiteralExpression(value: 42)),
            documentation: "Test query"
        )

        #expect(query.name == "myQuery")
        #expect(query.visibility == .public)
        #expect(query.parameters.count == 1)
        #expect(query.returnType == "Integer")
        #expect(query.documentation == "Test query")
    }

    // MARK: - Variable Tests

    @Test("Variable creation")
    func testVariableCreation() {
        let variable = MTLVariable(name: "myVar", type: "String")

        #expect(variable.name == "myVar")
        #expect(variable.type == "String")
    }

    @Test("Binding creation")
    func testBindingCreation() {
        let binding = MTLBinding(
            variable: MTLVariable(name: "x", type: "Integer"),
            initExpression: MTLExpression(AQLLiteralExpression(value: 100))
        )

        #expect(binding.variable.name == "x")
        #expect(binding.variable.type == "Integer")
    }

    // MARK: - Equality and Hashing

    @Test("Module equality")
    func testModuleEquality() {
        let module1 = MTLModule(
            name: "Test",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let module2 = MTLModule(
            name: "Test",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        let module3 = MTLModule(
            name: "Different",
            metamodels: [:],
            extends: nil,
            imports: [],
            templates: [:],
            queries: [:],
            macros: [:],
            encoding: "UTF-8"
        )

        #expect(module1 == module2)
        #expect(module1 != module3)
    }

    @Test("Template equality")
    func testTemplateEquality() {
        let template1 = MTLTemplate(
            name: "test",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [], inlined: false),
            isMain: false,
            overrides: nil,
            documentation: nil
        )

        let template2 = MTLTemplate(
            name: "test",
            visibility: .public,
            parameters: [],
            guard: nil,
            post: nil,
            body: MTLBlock(statements: [], inlined: false),
            isMain: false,
            overrides: nil,
            documentation: nil
        )

        #expect(template1 == template2)
    }

    @Test("Query equality")
    func testQueryEquality() {
        let query1 = MTLQuery(
            name: "test",
            visibility: .public,
            parameters: [],
            returnType: "String",
            body: MTLExpression(AQLLiteralExpression(value: "x")),
            documentation: nil
        )

        let query2 = MTLQuery(
            name: "test",
            visibility: .public,
            parameters: [],
            returnType: "String",
            body: MTLExpression(AQLLiteralExpression(value: "x")),
            documentation: nil
        )

        #expect(query1 == query2)
    }

    @Test("Variable equality")
    func testVariableEquality() {
        let var1 = MTLVariable(name: "x", type: "String")
        let var2 = MTLVariable(name: "x", type: "String")
        let var3 = MTLVariable(name: "y", type: "String")

        #expect(var1 == var2)
        #expect(var1 != var3)
    }
}
