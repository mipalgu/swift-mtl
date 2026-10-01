# Getting Started with MTL

Write a template, parse it, and generate text in memory or into files.

## Overview

This tutorial builds a small generator step by step. Every template shown here follows the
syntax covered by the package's tests. Add the `MTL` product to your target, and import
`MTL` (plus `ECore` and `EMFBase` when you pass model objects to a template).

### Write a template

A module starts with a header naming the module and the metamodels it uses by namespace
URI. At least one URI is required. Everything between `[template ...]` and
`[/template]` is the body.

```mtl
[comment encoding = UTF-8 /]
[module hello('http://www.eclipse.org/emf/2002/Ecore')/]

[template public main(name : String)]
Hello, [name/]!
[for (n | Sequence{1, 2, 3}) separator(', ') before('Counting: ') after('.')][n/][/for]
[/template]
```

A line that holds only block tags (such as `[for ...]` or `[/template]`) and white space
produces no output. Lines with text or an expression tag keep their line break. The
template above therefore produces `Hello, World!` followed by a line break, then
`Counting: 1, 2, 3.` and a line break when called with `'World'`.

### Parse a module

``MTLParser`` is an actor. Use ``MTLParser/parse(_:filename:)`` for source text, or
``MTLParser/parse(_:)`` for a file, which also links the imports and parent module.

```swift
import MTL

let source = """
    [module hello('http://www.eclipse.org/emf/2002/Ecore')/]
    [template public main(name : String)]
    Hello, [name/]!
    [/template]
    """

let parser = MTLParser()
let module = try await parser.parse(source, filename: "hello.mtl")
print(module.name)  // hello
```

The parsed ``MTLModule`` exposes its ``MTLModule/templates``, ``MTLModule/queries``,
``MTLModule/macros`` and ``MTLModule/metamodelURIs``. Use
``MTLModule/binding(to:)`` to bind the declared URIs to loaded `EPackage` values, and
``MTLModule/unboundMetamodelURIs`` to see which ones are still unbound.

### Generate in memory

Create an ``MTLInMemoryStrategy``, hand it to an ``MTLGenerator`` and run the main
template. The main output is stored under the file name `stdout`.

```swift
let strategy = MTLInMemoryStrategy()
let generator = MTLGenerator(module: module, generationStrategy: strategy)

try await generator.generate(
    mainTemplate: "main",
    arguments: ["World"],
    models: [:]
)

let files = await strategy.getGeneratedFiles()
print(files["stdout"] ?? "")  // Hello, World!
```

The `arguments` array holds the values for the template parameters in order. Pass model
objects (for example the root of an input model) as arguments, and register whole
models in `models` by alias such as `"IN"`. If several templates share the main
template's name, the one whose parameter count matches the arguments is used.
``MTLGenerator/statistics`` reports counts and timing after a run.

### Generate to files

A `[file (...)]` block redirects its content into a named file. Use
``MTLFileSystemStrategy`` to write those files below a base directory.

```mtl
[module files('http://www.eclipse.org/emf/2002/Ecore')/]
[template public main()]
[for (n | Sequence{'a', 'b'})]
[file (n + '.txt', false)]
This is file [n/].
[/file]
[/for]
[/template]
```

```swift
let strategy = MTLFileSystemStrategy(basePath: "output")
let generator = MTLGenerator(module: module, generationStrategy: strategy)
try await generator.generate(mainTemplate: "main", arguments: [], models: [:])
```

The second argument of `file` is the mode. `false` overwrites, `true` appends, and
`'overwrite'`, `'append'` and `'create'` (which fails if the file exists) are also
accepted, as are the bare keywords `overwrite`, `append` and `create`. An optional third
argument names the charset. It is recorded and passed to the strategy, but the bundled
writers always write UTF-8. With ``MTLInMemoryStrategy`` the same blocks end up in the
dictionary returned by ``MTLInMemoryStrategy/getGeneratedFiles()``, keyed by file name.

### Queries, templates and macros

A query is a named expression. A template produces text. A macro is like a template, but
its last parameter may be of type `Body` and receives the text between the call's tags.

```mtl
[module helpers('http://www.eclipse.org/emf/2002/Ecore')/]

[query public twice(n : Integer) : Integer = n * 2/]

[macro bracketed(open : String, content : Body)][open/][content/][']'/][/macro]

[template public item(label : String)]<[label/]>[/template]

[template public main()]
[twice(4)/]
[item('x')/]
[bracketed('[')]inner[/bracketed]
[Sequence{'a', 'b'}.item()/]
[/template]
```

Calling `[name(args)/]` finds queries, templates and macros by name. `[x.name(a)/]`
passes the receiver as the first argument. A template called on a collection runs once
per element, and the texts are concatenated. Write `['['/]` and `[']'/]` to produce
literal brackets. Overloads with the same name but different parameter types are
allowed and chosen by argument type.

### Imports and search paths

Use `[import qualified::module::name/]` to use another module. A module that begins
`[module derived('uri') extends base/]` inherits from `base`. Qualified names map to
files: `common::naming` is the file `common/naming.mtl`.

```mtl
[module app('http://www.eclipse.org/emf/2002/Ecore')/]
[import vendor::shared/]
[template public main()][shared()/][/template]
```

``MTLParser/parse(_:)`` looks in the importing file's directory first, then in each of
the parser's search paths in order.

```swift
let libraries = URL(fileURLWithPath: "libraries")
let parser = MTLParser(searchPaths: [libraries])
let module = try await parser.parse(URL(fileURLWithPath: "app.mtl"))
```

For modules parsed from source text, call ``MTLParser/link(_:relativeTo:)`` to attach
their imports afterwards. ``MTLModuleResolver`` and ``MTLModuleLoader`` offer the same
resolution on their own, for example
``MTLModuleResolver/candidates(for:relativeTo:)`` to see which files are tried.

### Handle errors

Each stage throws its own error type.

```swift
do {
    let module = try await parser.parse(URL(fileURLWithPath: "app.mtl"))
    try await generator(for: module).generate(
        mainTemplate: "main", arguments: [], models: [:])
} catch let error as MTLModuleResolutionError {
    // A missing module lists every location that was searched.
    print(error.localizedDescription)
} catch let error as MTLParseError {
    print("Syntax problem: \(error.localizedDescription)")
} catch let error as MTLExecutionError {
    print("Generation failed: \(error.localizedDescription)")
}
```

(Here `generator(for:)` stands for your own helper that builds an ``MTLGenerator``.)

- ``MTLModuleResolutionError`` reports a missing module (`notFound`, with the paths
  searched and the requiring module) or an import cycle (`cycle`).
- ``MTLParseError`` reports invalid syntax, such as a `for` without `in` or `|`, or an
  unknown file mode string.
- ``MTLExecutionError`` reports runtime problems: a template that cannot be found, a
  failed guard or post-condition, a type error, or a file that already exists in
  `create` mode.

### Next steps

Read <doc:UnderstandingMTL> for how invocations are resolved, how whitespace is handled
and which parts of the Acceleo standard library are not available yet.
