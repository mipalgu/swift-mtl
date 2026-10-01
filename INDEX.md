# swift-mtl Index

swift-mtl is a Swift library (product `MTL`) for model-to-text transformation with the OMG MOFM2T / Acceleo template language. It contains no executable; the `swift-mtl` command-line tool is part of the swift-modelling package.

## Documentation

- [README.md](README.md): overview, installation, quick start, syntax tour, known limits
- [SYNTAX.md](SYNTAX.md): full syntax reference
- [Examples/README.md](Examples/README.md): the example templates
- [Tests/MTLTests/README.md](Tests/MTLTests/README.md): the test suites and fixtures
- `Sources/MTL/MTL.docc`: DocC articles (`GettingStarted.md`, `UnderstandingMTL.md`) and the module page (`MTL.md`)
- [LICENCE](LICENCE)

## Sources (Sources/MTL)

- `MTL.swift`: placeholder source file
- `MTLParser.swift`: lexer and parser; `parse` links imports and parents, `parseWithoutLinking` does not
- `MTLSyntax.swift`: keywords, reserved names, and markers
- `MTLModule.swift`: the module model
- `MTLModuleLoader.swift`: `MTLModuleResolver` and `MTLModuleLoader` for imports and extends
- `MTLTemplate.swift`, `MTLQuery.swift`, `MTLMacro.swift`, `MTLVariable.swift`: declarations
- `MTLBlock.swift`, `MTLStatement.swift`: statements and blocks
- `MTLExpression.swift`, `MTLExpressions.swift`, `MTLInvocation.swift`, `MTLTypeMatcher.swift`: expressions, invocation, and overload matching
- `MTLGenerator.swift`, `MTLGenerationStrategy.swift`: the generation engine and its in-memory and file system strategies
- `MTLExecutionContext.swift`, `MTLWriter.swift`, `MTLIndentation.swift`, `MTLStandaloneLines.swift`: execution state, output, indentation, and the block-tag whitespace rule
- `MTLProtectedAreaManager.swift`: protected area content
- `MTLErrors.swift`: runtime errors

## Examples

`Examples/01-hello-world.mtl` to `Examples/07-protected-areas.mtl`: hello world, expressions, control flow, file blocks, queries, macros, and protected areas.

## Tests (Tests/MTLTests)

See [Tests/MTLTests/README.md](Tests/MTLTests/README.md). Run them with:

```sh
swift test
```

## Links

- [swift-mtl on GitHub](https://github.com/mipalgu/swift-mtl)
- [OMG MOFM2T](https://www.omg.org/spec/MOFM2T/)
- [Acceleo](https://eclipse.dev/acceleo/)
