# MTL Tests

Tests for the MTL parser and generator, written with Swift Testing. They are the source of truth for the behaviour of the library.

## Running Tests

```sh
swift test --scratch-path /tmp/build-swift-mtl
```

## Test Suites

- `MTLCommentAndHeaderTests.swift`: module headers, metamodel URIs and binding, comments, documentation comments, and encoding
- `MTLTemplateHeaderTests.swift`: template visibility, guards, post-expressions, `overrides`, and overloading
- `MTLForAndFileSyntaxTests.swift`: `for` clauses, the implicit counter, `file` modes and charsets, and protected block syntax
- `MTLExpressionSyntaxTests.swift`: operators, literals, collection literals, `->` calls, lambdas, qualified names, and type operations
- `MTLInvocationSyntaxTests.swift`: template, query, and macro invocation, receiver style, and overload resolution
- `MTLWhitespaceTests.swift`: the MOFM2T whitespace rule for lines with only block tags
- `MTLModuleLoadingTests.swift`: imports, extends, search paths, cycles, missing modules, and visibility across modules
- `MTLConformanceTests.swift`: parses and runs the fixture and example templates
- `MTLParserTests.swift`: parser behaviour
- `MTLModuleTests.swift`: module structure
- `MTLStatementTests.swift`: statement execution
- `MTLMacroTests.swift`: macro expansion
- `MTLGeneratorTests.swift`: the generation engine and strategies
- `MTLIntegrationTests.swift`: end-to-end generation from parsed and constructed modules
- `MTLIndentationTests.swift`: indentation handling
- `MTLProtectedAreaTests.swift`: protected area handling
- `MTLTests.swift`: index of the suites (no tests of its own)

`Support/MTLTestSupport.swift` holds the shared helpers for parsing a module, running a template with `MTLInMemoryStrategy`, and locating fixtures.

## Test Resources

Resources are copied into the test bundle from `Resources/`.

- `Resources/templates/`: small templates, `simple-hello.mtl`, `with-expressions.mtl`, `with-control-flow.mtl`, and `with-file-blocks.mtl`, plus malformed ones (`invalid-syntax.mtl`, `unclosed-block.mtl`, `missing-module.mtl`) for error reporting
- `Resources/modules/`: modules for import and extends tests (`base.mtl`, `derived.mtl`, `main.mtl`, `util.mtl`, `left.mtl`, `right.mtl`, `middle.mtl`, `diamond.mtl`, `transitive.mtl`, `importsderived.mtl`, `importsvendor.mtl`, `extendsmissing.mtl`, `missing.mtl`), with subdirectories `common/` (qualified names), `cyclic/` (import cycles), `dup/` (duplicate signatures), and `searchroot/` (search path lookup, including `vendor/`)
- `Resources/conformance/`: `acceleo-features.mtl`, which uses each supported construct once, and the `llfsm2*.mtl` templates (C, dot, Lisp, MIPS, NuSMV, PRISM, TLA, and UPPAAL), which are checked for parsing only
