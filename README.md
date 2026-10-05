# swift-mtl

[![CI](https://github.com/mipalgu/swift-mtl/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-mtl/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-mtl/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-mtl/actions/workflows/documentation.yml)

A Swift library for model-to-text transformation with the OMG MOFM2T / Acceleo template language.

## Overview

swift-mtl parses MTL (Model-to-Text Language) modules and executes their templates to generate code, documentation, and other text from models. It provides a single library product, `MTL`. Expressions inside templates are [swift-aql](https://github.com/mipalgu/swift-aql) expression nodes built by the MTL parser, and models come from [swift-ecore](https://github.com/mipalgu/swift-ecore).

This package contains no executable. The `swift-mtl` command-line tool is provided by the separate [swift-modelling](https://github.com/mipalgu/swift-modelling) package.

## Features

- Parser for the Acceleo dialect of MTL: module headers, `extends` and `import`, templates, queries, macros, `for`, `if`/`elseif`/`else`, `let`, `file`, and `protected` blocks, comments, and documentation comments
- Template visibility (`public`, `protected`, `private`), guards, post-expressions, `overrides`, and overloading by parameter types
- Module resolution through search paths, with `import` and `extends` linked recursively and cycles reported as errors
- Expression syntax including collection literals, `->` calls, lambdas, type operations, and qualified names
- The MOFM2T whitespace rule for lines that contain only block tags
- A generator with pluggable output strategies: in-memory (`MTLInMemoryStrategy`) and file system (`MTLFileSystemStrategy`)
- Protected areas written with configurable start and end prefixes, preserved automatically when files are regenerated
- Deferred `[collect]` and `[emit]` blocks, `[merge]` regeneration merging, `[layout]` code style conversion, generator options and file post-processors

## Installation

Add swift-mtl to the dependencies of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-mtl", from: "0.1.4"),
],
targets: [
    .target(
        name: "MyGenerator",
        dependencies: [
            .product(name: "MTL", package: "swift-mtl")
        ]
    ),
]
```

Adjust the version requirement to the release you want to use.

The package itself depends on [swift-collections](https://github.com/apple/swift-collections) (`OrderedCollections`), [swift-ecore](https://github.com/mipalgu/swift-ecore) (`ECore`, `EMFBase`, `OCL`), and [swift-aql](https://github.com/mipalgu/swift-aql) (`AQL`).

## Quick Start

Write a template, for example `hello.mtl`:

```mtl
[comment encoding = UTF-8 /]
[module hello('http://www.eclipse.org/emf/2002/Ecore')/]

[template public main(name : String)]
Hello, [name/]!
[/template]
```

Parse it and generate text into memory:

```swift
import ECore
import MTL

let module = try await MTLParser().parse(URL(fileURLWithPath: "hello.mtl"))

let strategy = MTLInMemoryStrategy()
let generator = MTLGenerator(module: module, generationStrategy: strategy)
try await generator.generate(
    mainTemplate: "main",
    arguments: ["World"],
    models: [:]
)

let files = await strategy.getGeneratedFiles()
print(files["stdout"] ?? "")   // the main output is stored under "stdout"
```

`MTLParser().parse(_:filename:)` parses template source held in a string instead of a file. Templates that write `[file (...)]` blocks add one entry per file to the dictionary. To write files to disk, use `MTLFileSystemStrategy(basePath:)` in place of `MTLInMemoryStrategy`.

## Syntax Tour

This is a condensed overview of the syntax. All constructs shown here are covered by the tests.

```mtl
[comment encoding = UTF-8 /]
[module shapes('http://www.eclipse.org/emf/2002/Ecore') extends common::base/]
[import common::naming/]

[** Generates a class for each EClass. @main **/]
[template public main(p : ecore::EPackage)]
[for (c : ecore::EClass | p.eClassifiers->select(oclIsKindOf(ecore::EClass))) separator(', ') before('Classes: ') after('.')]
[i/]. [c.name/]
[/for]
[file ('classes.txt', 'overwrite', 'UTF-8')]
[if (p.name.size() > 0)]Package [p.name/][else]Anonymous[/if]
[let n = 'x'][n/][/let]
[/file]
[/template]

[query public describe(c : ecore::EClass) : String = c.name + '!'/]

[macro wrap(body : Body)]<[body/]>[/macro]
```

Key points:

- Module header: `[module name('uri1', 'uri2')/]`, with at least one metamodel URI. `extends` names a parent module; `[import a::b::c/]` imports one. Both map `a::b::c` to `a/b/c.mtl`.
- Comments: `[comment text /]`, `[comment]...[/comment]`, `[-- text]`, and documentation comments `[** ... **/]` that attach to the next template, query, or macro. `[comment @main /]` inside a template, or `@main` in its documentation comment, marks the main template.
- Templates: `[template visibility name(params) ? (guard) post (expr) overrides other]`. Clauses may appear in any order.
- Queries and macros: `[query name(p : T) : R = expr/]` and `[macro name(p : T, body : Body)]...[/macro]`. Macros are called as `[name(args)]body[/name]`.
- Loops: `[for (x : T | collection) separator(s) before(b) after(a)]`. The loop variable type and binding are optional, and the implicit counter `i` is available in the body.
- Invocations: `[name(args)/]`, `[x.name(a)/]`, and `[self.name()/]`. Resolution looks at the current module, its parents, its imports, and then the AQL library; among overloads the nearest parameter types win.
- Literal brackets: `['['/]` and `[']'/]`.
- Protected areas: `[protected ('id', 'startPrefix', 'endPrefix')]...[/protected]`.

The full syntax reference is in [SYNTAX.md](SYNTAX.md).

### Imports, extends, and the module resolver

`[import qualified::module::name/]` and `extends` look modules up through `MTLModuleResolver`. It tries the directory of the importing file first and then each search path in order. Pass search paths to the parser:

```swift
let parser = MTLParser(searchPaths: [URL(fileURLWithPath: "templates")])
let module = try await parser.parse(URL(fileURLWithPath: "app/main.mtl"))
```

`parse(_:)` with a file URL parses and links imports and parents; `parseWithoutLinking(_:)` skips linking, and `link(_:relativeTo:)` links a module parsed from source text. `MTLModuleLoader` loads each file once per call. A missing module throws `MTLModuleResolutionError.notFound`, and a cycle throws `.cycle`. Imports are not transitive, and only public elements are visible through an import; protected elements are visible to extending modules.

### Collected Sets and Deferred Blocks

Values such as imports or includes are gathered while a file is generated and
rendered once the file body is complete. Sets are scoped to the enclosing
`[file]` block, keep insertion order and ignore duplicates.

```
[collect ('imports', 'a.b.C')/]
[collect ('imports', typeNames)/]
[emit ('imports') in(items->sortedBy(s | s)) separator('\n')]import [item/];[/emit]
```

- `[collect ('set', expr)/]` adds a string or a collection of strings.
- `[emit ('set') ...]...[/emit]` marks where the set is rendered. The block is
  rendered once per element with `item` bound to the element and `items` bound
  to the whole collection. Optional clauses: `separator(text)` between
  elements, `in(expr)` to sort, group or filter the elements (evaluated with
  `items` bound), and `once` to render the block a single time with `items`
  bound and `item` unbound. Emit blocks cannot be nested.
- `collected('set')` returns the values collected so far, for conflict checks.

### Regeneration Merge

A module can declare how an existing target file is merged with new output:

```
[merge ('/**', '*/', '@generated', '@generated NOT', 'braces')/]
```

The arguments are the comment start and end of leading comments (an empty end
means a line comment), the generated tag, the keep tag and the strategy
(`braces` or `indentation`, default `braces`). Further arguments of the form
`'key=value'` adjust the lexical conventions: `lineComments` (space-separated
markers), `blockComment` (start and end separated by a space), `quotes`,
`terminators` (characters that end a member; `\n` for newline-terminated
languages), `opener` and `files`.

`files` restricts the merge to matching files: a space-separated list of glob
patterns, for example `'files=*.java'`. `*` matches any characters except `/`,
`**` matches any characters, and `?` matches one character. A pattern without
`/` is matched against the last path component of the file URL, any other
pattern against the whole URL. Files that do not match are written as plain
overwrites. Without `files` the merge applies to every file. A `[file]` block
can also opt out with a trailing option, as in
`[file ('plugin.xml', 'overwrite', 'UTF-8', 'merge=false')]`.

When the target exists and force overwrite is off, blocks whose leading
comment contains the keep tag, or no tag at all, are preserved; blocks with
the generated tag are replaced; new tagged blocks are added; generated blocks
that are no longer produced are removed. Blocks are matched by normalised
signature within the matching parent. Lines of an `[emit]` region present in
the old file but missing from the new one are kept.

Only the leading comment of a block, written in the declared comment form,
carries the tags. That form starts with the comment start and, if the
declaration gives a comment end, ends with it. Tags in other comments, such
as line comments inside a body, comments of another form, comments further
above that are not part of the block's leading comment, and string literals,
are ignored. A generated method whose body mentions the keep tag (as the stub
text of an unimplemented operation does) is therefore replaced as a whole.
When the comment end is empty, only the unbroken run of line comments
directly above the block counts; a blank line ends the run.

A block that is generated and contains tagged members is merged member by
member: its header and closing line come from the new text, and kept members
retain their text verbatim. A kept container stays exactly as it is in the
existing file. After a layout change, regenerated headers and closing lines
therefore follow the new layout and a second run changes nothing.

### Layout Conversion

A module can convert the layout of its generated files to a code style, using
lexical data only:

```
[layout ('indent=\t', 'targetIndent=  ', 'opener=sameLine', 'files=*.java')/]
```

`indent` and `targetIndent` replace each leading indentation unit of a line;
`opener=sameLine` moves a block opener (`openerToken`, default `{`) that stands
alone on its line to the end of the preceding line, unless that line ends in a
statement terminator or comment, or is itself an opener. Comment markers,
quotes and terminators are configurable (`lineComments`, `blockComment`,
`quotes`, `terminators`), and `files` scopes the declaration with the same
globs as `[merge]`. A `[file]` block opts out with `'layout=false'`.

The programmatic equivalent is `MTLGeneratorOptions(layout:)` with an
`MTLLayoutConfiguration`, which overrides the module declaration;
`MTLLayoutPostProcessor` applies a configuration as a post-processor. Freshly
generated text is converted before it is merged with an existing file, which
is already in the target layout, and preserved protected areas are never
converted. See SYNTAX.md for the exact rules.

### File Context

In `create` mode an existing file is left untouched: no error is raised and the
body is not evaluated (no output, no `[collect]`, no nested `[file]`).

Two built-in services expose the file context to templates:

- `fileExists(path)` is true if a file exists at the path, relative to the
  generation base path (or absolute). Files written earlier in the same run count.
- `forceOverwrite()` returns the generator's `forceOverwrite` option.

```
[if (not fileExists('plugin.xml'))]
[file ('build.properties')]...[/file]
[/if]
```

The charset of a `file` block is honoured: `UTF-8` (the default), `UTF-16`
(big-endian with byte order mark), `UTF-16BE`, `UTF-16LE`, `ISO-8859-1`
(`Latin-1`) and `US-ASCII`. A character that the charset cannot represent, or an
unsupported charset, is an error and nothing is written.

### Generator Options and Post-Processing

`MTLFileSystemStrategy` and `MTLInMemoryStrategy` accept
`MTLGeneratorOptions` (`forceOverwrite`, `redirectionPattern` such as
`.{0}.new`, `lineDelimiter`, `layout`) and an ordered list of `MTLFilePostProcessor`
values that transform the content before it is written. Existing `[protected]`
areas are preserved automatically when a file is regenerated.

Line endings in generated output follow the template text: templates with CRLF
line endings parse like LF ones and produce CRLF output. Setting
`lineDelimiter` to a value other than `"\n"` rewrites every line ending in the
written file to that delimiter. On Windows, keep template files byte-exact with
a `.gitattributes` entry such as `*.mtl -text` if the output must use LF.


### AQL services

Operations written as `receiver.name(args)`, `receiver->name(args)` and `name(args)` are
resolved against the templates, queries and macros of the module first, then against
registered AQL services, and finally against the AQL standard library. Register additional
services through the generator or the execution context:

```swift
import AQL

struct GreetingServices: AQLServiceProvider {
    var services: [AQLService] {
        [AQLService("greet", receiver: .string, arity: 1) { call in
            "\(try call.string(0)), \(try call.receiverString())"
        }]
    }
}

let generator = MTLGenerator(
    module: module, generationStrategy: strategy, serviceProviders: [GreetingServices()])
generator.register(GreetingServices())  // later registrations take precedence
```

Every model passed to `generate(mainTemplate:arguments:models:)` or registered with
`MTLExecutionContext.registerModel(_:resource:)` is also made known to AQL, so `eContainer()`
and `allInstances()` can see its objects. Note that the AQL library counts strings and
collections from one (`'hello'.substring(1, 2)`, `seq->at(1)`).

### Global variables

Global variables are visible to every template, query and macro, and are read like any other
variable (`[name/]`). Set them before generating, either through the initialiser or with
`setGlobalVariable(_:value:)`:

```swift
let generator = MTLGenerator(
    module: module, generationStrategy: strategy, globals: ["version": "1.2"])
generator.setGlobalVariable("author", value: "A. Person")
```

A global shadows nothing: a template parameter or `let` variable of the same name hides it
inside its own scope only. Templates, queries and macros are invoked with parentheses, so they
never clash with a global of the same name.

## Project Structure

```
swift-mtl/
  Package.swift
  Sources/MTL/
    MTL.swift                    Placeholder source file
    MTLParser.swift              Lexer and parser for MTL modules
    MTLSyntax.swift              Keywords, reserved names, and markers of the syntax
    MTLModule.swift              Module model: metamodel URIs, templates, queries, macros, imports
    MTLModuleLoader.swift        Module resolver and loader for imports and extends
    MTLTemplate.swift            Templates and their visibility
    MTLQuery.swift               Queries
    MTLMacro.swift               Macros
    MTLVariable.swift            Parameter and variable declarations
    MTLBlock.swift               Blocks of statements
    MTLStatement.swift           Statements: text, for, if, let, file, protected
    MTLExpression.swift          Wrapper around swift-aql expressions
    MTLExpressions.swift         MTL-specific expression support
    MTLInvocation.swift          Invocable templates, queries, and macros
    MTLTypeMatcher.swift         Parameter type matching for overloads
    MTLGenerator.swift           The generation engine
    MTLGenerationStrategy.swift  Output strategies (in-memory and file system)
    MTLExecutionContext.swift    Execution state during generation
    MTLWriter.swift              Output accumulation with indentation
    MTLIndentation.swift         Indentation handling
    MTLStandaloneLines.swift     The whitespace rule for block-tag lines
    MTLProtectedAreaManager.swift Protected area content
    MTLErrors.swift              Runtime errors
    MTL.docc/                    DocC documentation
  Tests/MTLTests/                Swift Testing suites, with Support and Resources
  Examples/                      Example templates (01 to 07)
```

## Testing

```sh
swift test
```

The test suites are described in [Tests/MTLTests/README.md](Tests/MTLTests/README.md).

## Known Limits

- The released swift-aql lacks most of the Acceleo standard library. String services (`toUpperFirst`, `replaceAll`, `tokenize`, and similar), collection services (`sortedBy`, `asSet`, `including`, `sum`, `reverse`, `at`, and similar), and `div` parse but do not yet evaluate. `toString` of a number prints `Optional(7)`, `trim()` does not remove line breaks, `String + Integer` is a type error, and method-style calls on collections such as `coll.size()` do not evaluate (use `coll->size()`). Evaluation arrives with the next swift-aql release.
- Qualified type names in `oclIsKindOf(ecore::EClass)` are passed as the full string, and the released AQL compares unqualified names for dynamic objects only.
- Automatic scanning of protected areas in existing files, deferred blocks, tagged-block merge, and post-processors are not available.
- Protected area markers are `START PROTECTED REGION id` and `END PROTECTED REGION id` preceded by the configured prefixes; there are no default prefixes derived from the file extension.
- Only the charsets listed under File Context are supported.
- Macros have no visibility.

## Compatibility

Package.swift requires swift-tools 6.0 and declares macOS 15. The code is portable Swift 6, but only the platforms covered by the repository's CI workflows are exercised.

## Licence

Copyright (c) 2025, 2026 Rene Hexel. Distributed under a BSD-style licence with an advertising clause, or alternatively under the GNU General Public License version 2 or later, at your option. See [LICENCE](LICENCE) for the full wording.

## References

- [OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/)
- [Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)

### Related Packages

- [swift-ecore](https://github.com/mipalgu/swift-ecore): EMF/Ecore metamodelling
- [swift-aql](https://github.com/mipalgu/swift-aql): AQL model queries
- [swift-atl](https://github.com/mipalgu/swift-atl): ATL model transformations
- [swift-modelling](https://github.com/mipalgu/swift-modelling): the toolkit that provides the `swift-mtl` command-line tool
