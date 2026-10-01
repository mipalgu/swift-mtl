//
//  MTLInvocationSyntaxTests.swift
//  MTL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import ECore
import EMFBase
import Testing

@testable import MTL

@Suite("MTL Invocation Syntax")
struct MTLInvocationSyntaxTests {

    // MARK: - Queries

    @Test("A query is invoked by name from template text")
    @MainActor
    func queryByName() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query getVersion() : String = '1.0.0'/]
            [template main()]Version [getVersion()/][/template]
            """)
        #expect(output == "Version 1.0.0")
    }

    @Test("A query may take arguments")
    @MainActor
    func queryWithArguments() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query greet(name : String, punctuation : String) : String = 'Hi ' + name + punctuation/]
            [template main()][greet('Bob', '!')/][/template]
            """)
        #expect(output == "Hi Bob!")
    }

    @Test("A query is invoked with the receiver as first argument")
    @MainActor
    func queryWithReceiver() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query shout(s : String, suffix : String) : String = s + suffix/]
            [template main(x : String)][x.shout('!')/],[self.shout('?')/][/template]
            """, arguments: ["hey"])
        #expect(output == "hey!,hey?")
    }

    @Test("A query may call other queries")
    @MainActor
    func queryCallsQuery() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query a() : String = 'a'/]
            [query b() : String = a() + 'b'/]
            [template main()][b()/][/template]
            """)
        #expect(output == "ab")
    }

    @Test("Overloaded queries are selected by argument type")
    @MainActor
    func overloadedQueries() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query kind(x : String) : String = 'string'/]
            [query kind(x : Integer) : String = 'integer'/]
            [template main()][kind('a')/][kind(1)/][/template]
            """)
        #expect(output == "stringinteger")
    }

    @Test("A query can be used inside conditions and for loops")
    @MainActor
    func queryInControlFlow() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query isBig(n : Integer) : Boolean = n > 2/]
            [query items() : Sequence(Integer) = Sequence{1, 2, 3, 4}/]
            [template main()][for (n | items()) separator(',')][if (isBig(n))][n/][else]-[/if][/for][/template]
            """)
        #expect(output == "-,-,3,4")
    }

    // MARK: - Templates

    @Test("A template is invoked as an expression")
    @MainActor
    func templateByName() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template body(n : String)]<[n/]>[/template]
            [template main()][body('x')/][/template]
            """)
        #expect(output == "<x>")
    }

    @Test("A template is invoked on a receiver")
    @MainActor
    func templateOnReceiver() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template body(n : String)]<[n/]>[/template]
            [template main(x : String)][x.body()/][/template]
            """, arguments: ["y"])
        #expect(output == "<y>")
    }

    @Test("A template invoked on a collection runs once per element")
    @MainActor
    func templateOnCollection() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template item(n : String)]<[n/]>[/template]
            [template main()][Sequence{'a', 'b'}.item()/][/template]
            """)
        #expect(output == "<a><b>")
    }

    @Test("A template result can be used as a value")
    @MainActor
    func templateResultAsValue() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template word()]hello[/template]
            [template main()][word().size()/][/template]
            """)
        #expect(output == "5")
    }

    @Test("A recursive template keeps each call's parameters")
    @MainActor
    func recursiveTemplate() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template count(n : Integer)][n/][if (n > 0)],[count(n - 1)/][/if][/template]
            [template main()][count(3)/][/template]
            """)
        #expect(output == "3,2,1,0")
    }

    @Test("A multi-line template result inherits the indentation of the call")
    @MainActor
    func indentationOfMultiLineResult() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template block()]
            first
            second
            [/template]
            [template main()]
            {
                [block()/]
            }
            [/template]
            """)
        #expect(output == "{\n    first\n    second\n\n}\n")
    }

    @Test("A guarded-out template invoked as an expression yields no text")
    @MainActor
    func guardedTemplateCall() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template maybe(n : Integer) ? (n > 1)]yes[/template]
            [template main()]a[maybe(0)/]b[maybe(2)/][/template]
            """)
        #expect(output == "abyes")
    }

    // MARK: - Macros

    @Test("A macro is invoked with arguments and a body")
    @MainActor
    func macroWithBody() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [macro wrap(tag : String, content : Body)]<[tag/]>[content/]</[tag/]>[/macro]
            [template main()][wrap('b')]bold[/wrap][/template]
            """)
        #expect(output == "<b>bold</b>")
    }

    @Test("The macro body is evaluated in the scope of the invocation")
    @MainActor
    func macroBodyScope() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [macro twice(content : Body)][content/][content/][/macro]
            [template main(x : String)][twice()][x/][/twice][/template]
            """, arguments: ["ab"])
        #expect(output == "abab")
    }

    @Test("A macro without a body is invoked like a call")
    @MainActor
    func macroWithoutBody() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [macro hello(name : String)]Hello [name/][/macro]
            [template main()][hello('you')/][/template]
            """)
        #expect(output == "Hello you")
    }

    @Test("The generator expands a macro with body content")
    @MainActor
    func generatorExpandsMacroBody() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [macro wrap(content : Body)]<[content/]>[/macro]
            """)
        let macro = try #require(module.macros["wrap"])
        let strategy = MTLInMemoryStrategy()
        let generator = MTLGenerator(module: module, generationStrategy: strategy)
        try await generator.expandMacro(
            macro,
            arguments: [],
            bodyContent: MTLBlock(statements: [MTLTextStatement(value: "inner")])
        )
    }

    @Test("A macro that expects a body cannot be invoked without one")
    @MainActor
    func macroBodyMissing() async {
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.output("""
                [module m('u')/]
                [macro wrap(content : Body)][content/][/macro]
                [template main()][wrap()/][/template]
                """)
        }
    }

    // MARK: - Standalone and Library Calls

    @Test("Standalone library functions can be called")
    @MainActor
    func standaloneCalls() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main()][min(3, 2)/],[max(3, 2)/],[abs(-4)/][/template]
            """)
        #expect(output == "2,3,4")
    }

    @Test("Library methods can be called on strings")
    @MainActor
    func libraryMethods() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main(s : String)][s.toUpperCase()/],[s.size()/],[s.substring(0, 2)/][/template]
            """, arguments: ["hello"])
        #expect(output == "HELLO,5,he")
    }

    @Test("A query shadows a library function of the same name")
    @MainActor
    func queryShadowsLibrary() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query max(a : Integer, b : Integer) : Integer = 99/]
            [template main()][max(1, 2)/][/template]
            """)
        #expect(output == "99")
    }

    @Test("A library call is used when no overload accepts the arguments")
    @MainActor
    func fallbackToLibrary() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query min(a : String, b : String) : String = 'strings'/]
            [template main()][min(5, 4)/],[min('a', 'b')/][/template]
            """)
        #expect(output == "4,strings")
    }

    @Test("A call of an unknown name is an error")
    @MainActor
    func unknownCall() async {
        await #expect(throws: (any Error).self) {
            try await MTLTestSupport.output("[module m('u')/][template main()][nothingLikeThis(1)/][/template]")
        }
    }

    @Test("A call with a wrong argument count reports a clear error")
    @MainActor
    func wrongArgumentCount() async {
        await #expect(throws: (any Error).self) {
            try await MTLTestSupport.output("""
                [module m('u')/]
                [query one(x : Integer) : Integer = x/]
                [template main()][one(1, 2)/][/template]
                """)
        }
    }

    // MARK: - Scope

    @Test("Self is bound to the first argument")
    @MainActor
    func selfBinding() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template main(a : String, b : String)][self/][b/][/template]
            """, arguments: ["1", "2"])
        #expect(output == "12")
    }

    @Test("Variables of the caller are restored after a call")
    @MainActor
    func scopeRestored() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [template inner(x : String)][x/][/template]
            [template main(x : String)][inner('inner')/][x/][/template]
            """, arguments: ["outer"])
        #expect(output == "innerouter")
    }
}

@Suite("MTL Invocation Errors and Output")
struct MTLInvocationErrorTests {

    @Test("No applicable overload gives a message naming the argument types")
    @MainActor
    func noApplicableOverload() async {
        do {
            _ = try await MTLTestSupport.output("""
                [module m('u')/]
                [query kind(x : Integer) : String = 'integer'/]
                [template main()][kind('text')/][/template]
                """)
            Issue.record("Expected an error")
        } catch let error as MTLExecutionError {
            guard case .invalidOperation(let message) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(message.contains("'kind'"))
            #expect(message.contains("String"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test("A collection receiver whose elements fit no overload is an error")
    @MainActor
    func collectionElementsWithoutOverload() async {
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.output("""
                [module m('u')/]
                [template kind(x : Integer)]integer[/template]
                [template main()][Sequence{'a'}.kind()/][/template]
                """)
        }
    }

    @Test("A collection receiver collects the results of queries")
    @MainActor
    func queryOnCollection() async throws {
        let output = try await MTLTestSupport.output("""
            [module m('u')/]
            [query double(x : Integer) : Integer = x * 2/]
            [template main()][Sequence{1, 2, 3}.double()/][/template]
            """)
        #expect(output == "246")
    }

    @Test("A failure inside a called template restores the output")
    @MainActor
    func failureInCalledTemplate() async throws {
        let module = try await MTLTestSupport.parse("""
            [module m('u')/]
            [template bad()][missing(1)/][/template]
            [template main()]before[bad()/][/template]
            """)
        await #expect(throws: (any Error).self) {
            _ = try await MTLTestSupport.run(module)
        }
    }

    @Test("A post expression that is null fails")
    @MainActor
    func nullPost() async {
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.output("[module m('u')/][template main() post (null)]x[/template]")
        }
    }

    @Test("A post expression that is not text replaces the output by its description")
    @MainActor
    func numericPost() async throws {
        let output = try await MTLTestSupport.output("[module m('u')/][template main() post (1 + 1)]x[/template]")
        #expect(output == "2")
    }

    @Test("A collection value is written as the concatenation of its elements")
    @MainActor
    func collectionOutput() async throws {
        let output = try await MTLTestSupport.output("[module m('u')/][template main()][Sequence{'a', Sequence{'b', 'c'}}/][/template]")
        #expect(output == "abc")
    }

    @Test("The generator checks the argument count of templates")
    @MainActor
    func generatorArgumentCount() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/][template main(x : String)]x[/template]")
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        await #expect(throws: MTLExecutionError.self) {
            try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        }
    }

    @Test("The generator reports a missing main template")
    @MainActor
    func generatorMissingMain() async throws {
        let module = try await MTLTestSupport.parse("[module m('u')/][template other()]x[/template]")
        let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy())
        await #expect(throws: MTLExecutionError.self) {
            try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
        }
    }

    @Test("Overloaded main templates are selected by argument count")
    @MainActor
    func overloadedMain() async throws {
        let source = """
            [module m('u')/]
            [template main()]none[/template]
            [template main(x : String)]one[/template]
            """
        #expect(try await MTLTestSupport.output(source) == "none")
        #expect(try await MTLTestSupport.output(source, arguments: ["x"]) == "one")
    }

    @Test("A macro invoked with the wrong number of arguments is an error")
    @MainActor
    func macroArgumentCount() async {
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.output("""
                [module m('u')/]
                [macro wrap(a : String, content : Body)][content/][/macro]
                [template main()][wrap(1, 2)]x[/wrap][/template]
                """)
        }
    }

    @Test("An unknown macro with a body is reported")
    @MainActor
    func unknownMacro() async {
        await #expect(throws: MTLExecutionError.self) {
            try await MTLTestSupport.output("""
                [module m('u')/]
                [template main()][nothing()]x[/nothing][/template]
                """)
        }
    }
}
