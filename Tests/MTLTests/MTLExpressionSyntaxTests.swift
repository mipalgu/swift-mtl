//
//  MTLExpressionSyntaxTests.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import AQL
import Testing

@testable import MTL

@Suite("MTL Expression Syntax")
struct MTLExpressionSyntaxTests {

    /// Parses the single expression statement of a one-line template.
    private static func expression(_ text: String) async throws -> any AQLExpression {
        let module = try await MTLTestSupport.parse("[module m('u')/][template main()][\(text)/][/template]")
        let statement = try #require(module.templates["main"]?.body.statements.first as? MTLExpressionStatement)
        return statement.expression.aqlExpression
    }

    /// Evaluates a one-line expression in a template.
    @MainActor
    private static func evaluate(_ text: String) async throws -> String {
        try await MTLTestSupport.output("[module m('u')/][template main()][\(text)/][/template]")
    }

    // MARK: - Conditional and Let

    @Test("An if expression chooses between two values")
    @MainActor
    func conditionalExpression() async throws {
        #expect(try await Self.evaluate("if 3 > 1 then 'big' else 'small' endif") == "big")
        #expect(try await Self.evaluate("if 0 > 1 then 'big' else 'small' endif") == "small")
    }

    @Test("An if expression is an AQLConditionalExpression")
    func conditionalNode() async throws {
        let node = try await Self.expression("if true then 1 else 2 endif")
        #expect(node is AQLConditionalExpression)
    }

    @Test("An if expression may be parenthesised, nested, and used inside other expressions")
    @MainActor
    func conditionalNesting() async throws {
        #expect(try await Self.evaluate("if (1 > 2) then 'a' else if (2 > 1) then 'b' else 'c' endif endif") == "b")
        #expect(try await Self.evaluate("'<' + if true then 'x' else 'y' endif + '>'") == "<x>")
    }

    @Test("An if statement is not mistaken for an if expression")
    @MainActor
    func ifStatementUnchanged() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()][if (1 > 0)]yes[else]no[/if][/template]
            """)
        #expect(output == "yes")
    }

    @Test("A let expression binds a variable for its body")
    @MainActor
    func letExpression() async throws {
        #expect(try await Self.evaluate("let y = 2 in y * 3") == "6")
        #expect(try await Self.evaluate("let y : Integer = 2 in y * 3") == "6")
    }

    @Test("A let expression is an AQLLetExpression")
    func letNode() async throws {
        let node = try await Self.expression("let y = 2 in y")
        let let_ = try #require(node as? AQLLetExpression)
        #expect(let_.bindings.map(\.0) == ["y"])
    }

    @Test("A let expression may bind several variables and nest")
    @MainActor
    func letExpressionNesting() async throws {
        #expect(try await Self.evaluate("let a = 1, b = 2 in a + b") == "3")
        #expect(try await Self.evaluate("let a = 1 in let b = a + 1 in a + b") == "3")
    }

    @Test("A let statement is not mistaken for a let expression")
    @MainActor
    func letStatementUnchanged() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()][let y = 4][y/][/let][/template]
            """)
        #expect(output == "4")
    }

    // MARK: - Operators and Literals

    @Test("The logical operators implies and xor are supported")
    @MainActor
    func logicalOperators() async throws {
        #expect(try await Self.evaluate("true implies false") == "false")
        #expect(try await Self.evaluate("false implies false") == "true")
        #expect(try await Self.evaluate("true xor false") == "true")
        #expect(try await Self.evaluate("true xor true") == "false")
    }

    @Test("Implies binds looser than or, and associates to the right")
    func impliesPrecedence() async throws {
        let node = try await Self.expression("false or true implies false implies true")
        let outer = try #require(node as? AQLBinaryExpression)
        #expect(outer.op == .implies)
        #expect(outer.right is AQLBinaryExpression)
        #expect((outer.left as? AQLBinaryExpression)?.op == .or)
    }

    @Test("Mod is a binary operator")
    @MainActor
    func modOperator() async throws {
        #expect(try await Self.evaluate("7 mod 3") == "1")
        #expect(try await Self.evaluate("2 + 7 mod 3 * 2") == "4")
    }

    @Test("Div parses as an integer division call")
    func divParses() async throws {
        let node = try await Self.expression("7 div 2")
        let call = try #require(node as? AQLCallExpression)
        #expect(call.methodName == "div")
        #expect(call.arguments.count == 1)
    }

    @Test("Real literals are supported")
    @MainActor
    func realLiterals() async throws {
        let node = try await Self.expression("3.25")
        #expect((node as? AQLLiteralExpression)?.value as? Double == 3.25)
        #expect(try await Self.evaluate("1.5 + 2.5") == "4.0")
    }

    @Test("Subtraction without spaces is not a negative literal")
    @MainActor
    func subtractionWithoutSpaces() async throws {
        #expect(try await Self.evaluate("5-1") == "4")
        #expect(try await Self.evaluate("5 - -1") == "6")
        #expect(try await Self.evaluate("(5)-1") == "4")
        #expect(try await Self.evaluate("-3 + 1") == "-2")
    }

    @Test("Null is a literal")
    @MainActor
    func nullLiteral() async throws {
        let node = try await Self.expression("null")
        #expect((node as? AQLLiteralExpression)?.value == nil)
        #expect(try await Self.evaluate("null.oclIsUndefined()") == "true")
        #expect(try await Self.evaluate("'a'.oclIsUndefined()") == "false")
    }

    @Test("Qualified names are kept as written")
    func qualifiedNames() async throws {
        let node = try await Self.expression("ecore::EClass")
        #expect((node as? AQLVariableExpression)?.name == "ecore::EClass")
        let enumeration = try await Self.expression("genmodel::GenProviderKind::Singleton")
        #expect((enumeration as? AQLVariableExpression)?.name == "genmodel::GenProviderKind::Singleton")
    }

    @Test("Qualified type names are passed to type operations")
    func qualifiedTypeArguments() async throws {
        for operation in ["oclIsKindOf", "oclIsTypeOf", "oclAsType"] {
            let node = try await Self.expression("self.\(operation)(ecore::EClass)")
            let call = try #require(node as? AQLCallExpression)
            #expect(call.methodName == operation)
            #expect((call.arguments.first as? AQLVariableExpression)?.name == "ecore::EClass")
        }
    }

    @Test("A type operation without receiver applies to self")
    func typeOperationOnSelf() async throws {
        let node = try await Self.expression("oclIsKindOf(EClass)")
        let call = try #require(node as? AQLCallExpression)
        #expect((call.source as? AQLVariableExpression)?.name == "self")
    }

    // MARK: - Collection Operations

    @Test("The known iterator operations keep their dedicated node")
    func knownOperations() async throws {
        for name in ["select", "reject", "collect", "any", "exists", "forAll"] {
            let node = try await Self.expression("Sequence{1}->\(name)(x | x > 0)")
            let operation = try #require(node as? AQLCollectionExpression)
            #expect(operation.iterator == "x")
            #expect(operation.operation.rawValue == name)
        }
    }

    @Test("Any operation name is accepted after an arrow")
    func genericOperationNames() async throws {
        for name in ["including", "excluding", "union", "asSet", "asSequence", "sum", "flatten", "reverse"] {
            let node = try await Self.expression("Sequence{1}->\(name)(2)")
            let call = try #require(node as? AQLCallExpression)
            #expect(call.methodName == name)
            #expect(call.arguments.count == 1)
        }
    }

    @Test("An operation without parentheses has no arguments")
    func genericOperationWithoutParentheses() async throws {
        let node = try await Self.expression("Sequence{1}->asSet")
        let call = try #require(node as? AQLCallExpression)
        #expect(call.arguments.isEmpty)
    }

    @Test("A lambda argument of another operation keeps its iterator")
    func lambdaArgument() async throws {
        let node = try await Self.expression("Sequence{1}->sortedBy(e : Integer | e)")
        let call = try #require(node as? AQLCallExpression)
        let lambda = try #require(call.arguments.first as? MTLLambdaExpression)
        #expect(lambda.iterator == "e")
        #expect(lambda.iteratorType == "Integer")
    }

    @Test("The lambda parameter may have a type")
    @MainActor
    func typedLambdaParameter() async throws {
        #expect(try await Self.evaluate("Sequence{1, 2, 3}->select(x : Integer | x > 1)->size()") == "2")
    }

    @Test("An iterator body may omit the iterator and use self implicitly")
    @MainActor
    func implicitIterator() async throws {
        #expect(try await Self.evaluate("Sequence{'a', 'bb', 'cc'}->select(size() > 1)->size()") == "2")
        #expect(try await Self.evaluate("Sequence{'a', 1}->select(oclIsKindOf(String))->size()") == "1")
    }

    @Test("Exists and forAll evaluate")
    @MainActor
    func existsForAll() async throws {
        #expect(try await Self.evaluate("Sequence{1, 2}->exists(x | x = 2)") == "true")
        #expect(try await Self.evaluate("Sequence{1, 2}->forAll(x | x > 1)") == "false")
    }

    @Test("Collection literals evaluate to ordered values")
    @MainActor
    func collectionLiterals() async throws {
        #expect(try await Self.evaluate("Sequence{3, 1, 2}->first()") == "3")
        #expect(try await Self.evaluate("Sequence{}->isEmpty()") == "true")
        #expect(try await Self.evaluate("OrderedSet{1, 1, 2}->size()") == "2")
        #expect(try await Self.evaluate("Sequence{1, 1, 2}->size()") == "3")
        #expect(try await Self.evaluate("Set{'a', 'a'}->size()") == "1")
        #expect(try await Self.evaluate("Bag{'a', 'a'}->size()") == "2")
    }

    // MARK: - Escapes

    @Test("String literals escape the brackets of text")
    @MainActor
    func bracketEscapes() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()]['['/]x[']'/] and ['[' + ']'/][/template]
            """)
        #expect(output == "[x] and []")
    }

    @Test("Quote characters can be escaped in strings")
    @MainActor
    func quoteEscapes() async throws {
        #expect(try await Self.evaluate("'it\\'s'") == "it's")
        #expect(try await Self.evaluate("'tab\\there'") == "tab\there")
    }
}
