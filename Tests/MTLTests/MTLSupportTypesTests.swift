//
//  MTLSupportTypesTests.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import ECore
import EMFBase
import Foundation
import Testing

@testable import MTL

@Suite("MTL Support Types")
struct MTLSupportTypesTests {

    // MARK: - File Modes

    @Test("Boolean modes map to overwrite and append")
    func booleanFileModes() {
        #expect(MTLOpenMode.mode(append: false) == .overwrite)
        #expect(MTLOpenMode.mode(append: true) == .append)
        #expect(MTLOpenMode(value: true) == .append)
        #expect(MTLOpenMode(value: false) == .overwrite)
    }

    @Test("String modes map to their file modes")
    func stringFileModes() {
        #expect(MTLOpenMode(value: "overwrite") == .overwrite)
        #expect(MTLOpenMode(value: "append") == .append)
        #expect(MTLOpenMode(value: "create") == .create)
    }

    @Test("Other values are not file modes")
    func invalidFileModes() {
        #expect(MTLOpenMode(value: "truncate") == nil)
        #expect(MTLOpenMode(value: 3) == nil)
        #expect(MTLOpenMode(value: nil) == nil)
    }

    // MARK: - Type Matching

    @Test("Type names lose their package qualification")
    func simpleNames() {
        #expect(MTLTypeMatcher.simpleName(of: "ecore::EClass") == "EClass")
        #expect(MTLTypeMatcher.simpleName(of: "EClass") == "EClass")
        #expect(MTLTypeMatcher.simpleName(of: "Sequence(ecore::EClass)") == "Sequence(ecore::EClass)")
        #expect(MTLTypeMatcher.simpleName(of: "a::b::Sequence(X)") == "Sequence(X)")
    }

    @Test("Primitive values match their declared types")
    func primitiveMatching() {
        #expect(MTLTypeMatcher.distance(of: "text", to: "String") == 0)
        #expect(MTLTypeMatcher.distance(of: 3, to: "Integer") == 0)
        #expect(MTLTypeMatcher.distance(of: true, to: "Boolean") == 0)
        #expect(MTLTypeMatcher.distance(of: 1.5, to: "Real") == 0)
        #expect(MTLTypeMatcher.distance(of: 2, to: "Real") == 1)
        #expect(MTLTypeMatcher.distance(of: "text", to: "Integer") == nil)
        #expect(MTLTypeMatcher.distance(of: 3, to: "String") == nil)
        #expect(MTLTypeMatcher.distance(of: 1.5, to: "Integer") == nil)
    }

    @Test("Ecore data type names are accepted for primitives")
    func ecoreDataTypeAliases() {
        #expect(MTLTypeMatcher.distance(of: "x", to: "ecore::EString") == 0)
        #expect(MTLTypeMatcher.distance(of: 1, to: "EInt") == 0)
        #expect(MTLTypeMatcher.distance(of: false, to: "EBoolean") == 0)
        #expect(MTLTypeMatcher.distance(of: 1.5, to: "EDouble") == 0)
    }

    @Test("Null and OclAny match everything with the loosest score")
    func looseMatching() {
        #expect(MTLTypeMatcher.distance(of: nil, to: "String") == MTLTypeMatcher.unspecificDistance)
        #expect(MTLTypeMatcher.distance(of: "x", to: "OclAny") == MTLTypeMatcher.unspecificDistance)
    }

    @Test("Collections match collection types only")
    func collectionMatching() {
        let sequence = EcoreValueArray([1, 2])
        #expect(MTLTypeMatcher.distance(of: sequence, to: "Sequence(Integer)") == 1)
        #expect(MTLTypeMatcher.distance(of: sequence, to: "OrderedSet(ecore::EClass)") == 1)
        #expect(MTLTypeMatcher.distance(of: sequence, to: "Collection") == 1)
        #expect(MTLTypeMatcher.distance(of: "text", to: "Sequence(String)") == nil)
        #expect(MTLTypeMatcher.distance(of: sequence, to: "String") == nil)
        #expect(MTLTypeMatcher.distance(of: sequence, to: "Table(String)") == nil)
    }

    @Test("Dynamic objects match their metaclass and its supertypes by distance")
    func objectMatching() {
        let thing = EClass(name: "Thing")
        let animal = EClass(name: "Animal", eSuperTypes: [thing])
        let dog = EClass(name: "Dog", eSuperTypes: [animal])
        let object = DynamicEObject(eClass: dog)

        #expect(MTLTypeMatcher.distance(of: object, to: "Dog") == 0)
        #expect(MTLTypeMatcher.distance(of: object, to: "model::Animal") == 1)
        #expect(MTLTypeMatcher.distance(of: object, to: "Thing") == 2)
        #expect(MTLTypeMatcher.distance(of: object, to: "Cat") == nil)
        #expect(MTLTypeMatcher.distance(of: object, to: "EObject") == MTLTypeMatcher.unverifiableDistance)
        #expect(MTLTypeMatcher.distance(of: "text", to: "Dog") == nil)
    }

    @Test("Native model objects match their own class and are otherwise unverifiable")
    func nativeObjectMatching() {
        let package = EPackage(name: "p")
        #expect(MTLTypeMatcher.distance(of: package, to: "EPackage") == 0)
        #expect(MTLTypeMatcher.distance(of: package, to: "ENamedElement") == MTLTypeMatcher.unverifiableDistance)
    }

    // MARK: - Expressions

    @Test("A lambda cannot be evaluated outside an operation")
    @MainActor
    func lambdaEvaluationFails() async {
        let context = AQLExecutionContext(executionEngine: ECoreExecutionEngine(models: [:]))
        let lambda = MTLLambdaExpression(iterator: "x", body: AQLVariableExpression(name: "x"))
        await #expect(throws: AQLExecutionError.self) {
            _ = try await lambda.evaluate(in: context)
        }
    }

    @Test("An invocation without a runtime falls back to the AQL library")
    @MainActor
    func invocationWithoutRuntime() async throws {
        let context = AQLExecutionContext(executionEngine: ECoreExecutionEngine(models: [:]))
        let call = AQLCallExpression(
            methodName: "max",
            arguments: [AQLLiteralExpression(value: 2), AQLLiteralExpression(value: 5)]
        )
        let invocation = MTLInvocationExpression(
            name: "max",
            receiver: nil,
            arguments: call.arguments,
            fallback: call
        )
        #expect(try await invocation.evaluate(in: context) as? Int == 5)
    }

    @Test("Collection literals drop nulls and deduplicate sets")
    @MainActor
    func collectionLiteralDetails() async throws {
        let context = AQLExecutionContext(executionEngine: ECoreExecutionEngine(models: [:]))
        let elements: [any AQLExpression] = [
            AQLLiteralExpression(value: 1), AQLLiteralExpression(value: nil), AQLLiteralExpression(value: 1)
        ]
        let sequence = MTLCollectionLiteralExpression(kind: "Sequence", elements: elements)
        let set = MTLCollectionLiteralExpression(kind: "Set", elements: elements)
        #expect((try await sequence.evaluate(in: context) as? EcoreValueArray)?.values.count == 2)
        #expect((try await set.evaluate(in: context) as? EcoreValueArray)?.values.count == 1)
    }

    @Test("Runtime handles compare by identity")
    @MainActor
    func runtimeHandleIdentity() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/]")
        let context = MTLExecutionContext(module: module, generationStrategy: MTLInMemoryStrategy())
        let first = MTLRuntimeHandle(runtime: context)
        let second = MTLRuntimeHandle(runtime: context)
        #expect(first == first)
        #expect(first != second)
        #expect(first.hashValue == first.hashValue)
        #expect(first.reference.runtime === context)
    }

    // MARK: - Errors

    @Test("Resolution errors describe what went wrong")
    func resolutionErrorDescriptions() {
        let notFound = MTLModuleResolutionError.notFound(module: "a::b", searched: ["/x/a/b.mtl"], requiredBy: "main")
        #expect(notFound.errorDescription == "Module 'a::b' not found (required by module 'main'); searched: /x/a/b.mtl")
        let unlocated = MTLModuleResolutionError.notFound(module: "a", searched: [], requiredBy: nil)
        #expect(unlocated.errorDescription == "Module 'a' not found; no search location is configured")
        let cycle = MTLModuleResolutionError.cycle(["a.mtl", "b.mtl", "a.mtl"])
        #expect(cycle.errorDescription == "Cyclic module dependency: a.mtl -> b.mtl -> a.mtl")
    }

    @Test("Syntax errors report the position")
    func syntaxErrorPositions() async {
        let sources = [
            "[module m('u')/][template t(]x[/template]",
            "[module m('u')/][template t()][for (x : T]a[/for][/template]",
            "[module m('u')/][template t()][if c then 1 else][/template]",
            "[module m('u')/][comment** never closed",
            "[module m('u')/][**\\nnever closed"
        ]
        for source in sources {
            do {
                _ = try await MTLTestSupport.parse(source)
                Issue.record("Expected a syntax error for \(source)")
            } catch let error as MTLParseError {
                #expect(error.errorDescription?.isEmpty == false)
            } catch {
                Issue.record("Unexpected error \(error)")
            }
        }
    }

    @Test("A division and the end of an expression are told apart")
    @MainActor
    func divisionVersusSlash() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()][8 / 2/]|[9/3/]|[(10 / 5) * 3/][/template]
            """)
        #expect(output == "4|3|6")
    }
}
