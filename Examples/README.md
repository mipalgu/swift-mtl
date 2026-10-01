# MTL Examples

This directory holds seven small templates that show the main features of the
language. Each one parses and runs. The language itself is described in
`SYNTAX.md` at the root of the package.

## The examples

| File | Demonstrates |
| --- | --- |
| `01-hello-world.mtl` | the module header and a template that emits plain text |
| `02-expressions.mtl` | arithmetic, string concatenation and calls to queries from expression tags |
| `03-control-flow.mtl` | `if`, `elseif`, `else` and nested `let` bindings |
| `04-file-blocks.mtl` | `file` blocks that write three files from one template, using `'overwrite'` mode and `'UTF-8'` |
| `05-queries.mtl` | typed queries returning integers, Booleans and strings, including a multi-line query |
| `06-macros.mtl` | macros with `Body` parameters, called with a body between opening and closing tags |
| `07-protected-areas.mtl` | `protected` areas using the `startTagPrefix` and `endTagPrefix` clauses |

Example 07 writes three protected areas into a Swift class. With the clauses
`startTagPrefix('// ')` and `endTagPrefix('// ')`, the markers it produces read
`// START PROTECTED REGION custom-methods` and
`// END PROTECTED REGION custom-methods`, and likewise for `custom-init` and
`custom-description`.

Examples 01 to 03 and 05 to 07 write to the main output. Example 04 writes its
content to the files named in its `file` blocks; its main output holds only the
blank lines between the blocks.

## Running an example from Swift

Parse the template with `MTLParser`, then generate with `MTLGenerator` and one of
the generation strategies. `MTLInMemoryStrategy` keeps the results in memory
(the main output is stored under the file name `stdout`);
`MTLFileSystemStrategy` writes files below a base directory.

```swift
import Foundation
import MTL

let url = URL(fileURLWithPath: "Examples/05-queries.mtl")
let module = try await MTLParser().parse(url)

let strategy = MTLInMemoryStrategy()
let generator = MTLGenerator(module: module, generationStrategy: strategy)
try await generator.generate(mainTemplate: "main", arguments: [], models: [:])

let files = await strategy.getGeneratedFiles()
print(files["stdout"] ?? "")
```

To write files to disk, use the file system strategy instead:

```swift
let strategy = MTLFileSystemStrategy(basePath: "generated")
let generator = MTLGenerator(module: module, generationStrategy: strategy)
try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
```

The examples declare no model parameters, so the argument list and the model
dictionary are empty. A template with parameters receives its arguments in
`arguments`, and input models are supplied in `models`, keyed by alias.

The swift-mtl command-line tool of the swift-modelling package can also run these
templates.
