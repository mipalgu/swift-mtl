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
- The MOFM2T whitespace rule for lines that contain only block tags, and the Acceleo 4 rule for the line break after a block written on one line
- Behaviour options (`MTLOptions`) that select the behaviour of this release or that of version 0.6
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
let generator = MTLGenerator(module: module, generationStrategy: strategy, options: .standard)
try await generator.generate(
    mainTemplate: "main",
    arguments: ["World"],
    models: [:]
)

let files = await strategy.getGeneratedFiles()
print(files["stdout"] ?? "")   // the main output is stored under "stdout"
```

`options: .standard` selects the behaviour that this README describes (see [Behaviour options](#behaviour-options)). A generator created without `options` behaves as version 0.6 did (see [Compatibility with 0.6](#compatibility-with-06)).

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
- Let blocks: `[let x : T = e, y = f]...[/let]`. A value that does not conform to the declared type is a type error by default; with the `letTypeMismatches` option set to `.skip` the block is skipped with a warning instead, as in Acceleo 3 (see [Typed let blocks](#typed-let-blocks)).
- Literal brackets: `['['/]` and `[']'/]`.
- Protected areas: `[protected ('id', 'startPrefix', 'endPrefix')]...[/protected]`.

The full syntax reference is in [SYNTAX.md](SYNTAX.md).

### Imports, extends, and the module resolver

`[import qualified::module::name/]` and `extends` look modules up through `MTLModuleResolver`. It tries the directory of the importing file first (so `[import a::b/]` in `app/main.mtl` finds `app/a/b.mtl`) and then each search path in order. Pass search paths to the parser:

```swift
let parser = MTLParser(searchPaths: [URL(fileURLWithPath: "templates")])
let module = try await parser.parse(URL(fileURLWithPath: "app/main.mtl"))
```

`parse(_:)` with a file URL parses and links imports and parents; `parseWithoutLinking(_:)` skips linking, and `link(_:relativeTo:)` links a module parsed from source text. `MTLModuleLoader` loads each file once per call. A missing module throws `MTLModuleResolutionError.notFound`, and a cycle throws `.cycle`. Imports are not transitive, and only public elements are visible through an import; protected elements are visible to extending modules.

To link without touching the file system, give the parser an `MTLModuleSource`, which returns the text and a location for a module name. The linker asks the source first and falls back to the search paths for modules it does not know:

```swift
let parser = MTLParser(moduleSource: openDocuments)
let module = try await parser.link(try await parser.parse(text, filename: "main.mtl"))
```

### Editor Support

`MTLParser.parseDiagnosing(_:filename:)` parses without stopping at the first mistake. It skips to the end of a broken directive (or to the matching closing tag of a broken block) and to the end of a broken template, query or macro, and returns the module that could be read, the diagnostics (`SourceDiagnostic` values with ranges and stable `MTLDiagnosticCode` codes) and an outline of the module. `MTLSyntax.tokens(in:)` splits template text, directives and expressions into highlighting tokens and never fails. Parsed statements, declarations and expressions carry an `origin` with their range in the source text; origins never take part in equality.

### Progress and Cancellation

`MTLGenerator.generate(mainTemplate:arguments:models:progress:)` reports an `MTLProgress` (templates executed, files written, current template and file) on the main actor. Generation checks for task cancellation at the start of every block and loop iteration and gives other main actor work the chance to run every ten milliseconds, so a cancelled run throws `CancellationError` and a run on the main actor keeps the interface responsive.

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
    module: module, generationStrategy: strategy, options: .standard,
    serviceProviders: [GreetingServices()])
generator.register(GreetingServices())  // later registrations take precedence
```

Every model passed to `generate(mainTemplate:arguments:models:)` or registered with
`MTLExecutionContext.registerModel(_:resource:)` is also made known to AQL, so `eContainer()`
and `allInstances()` can see its objects. Note that the AQL library counts strings and
collections from one (`'hello'.substring(1, 2)`, `seq->at(1)`).

With the `cachesContainers` option (the default), the container of each model object is
looked up once during a generation run and reused by `eContainer()`, `ancestors()` and the
sibling services. Templates do not change their models; a service that does must be created
with `modifiesModels: true`, so that later containment queries see the change. Set
`cachesContainers` to `false` to look up every container afresh, as version 0.6 did.

### Typed let blocks

A `let` variable may declare a type, as in `[let names : Sequence(String) = e]...[/let]`. The
value is checked against the declared type as an argument is checked against a template
parameter (see [Collection parameters](#collection-parameters)): a value of a collection type
is bound as a collection, and `null` conforms to every type. By default, a value that does not
conform to the declared type is a type error that stops the generation. The OMG MOFM2T
specification and Acceleo 3 treat a typed `let` as a type test instead and skip its body
silently. Set the `letTypeMismatches` option to `.skip` to follow them: the block is skipped,
generation continues, and a warning that names the variable, its declared type and the type
of the value is recorded in the generation statistics:

```swift
let generator = MTLGenerator(
    module: module, generationStrategy: strategy, options: MTLOptions(letTypeMismatches: .skip))
try await generator.generate(mainTemplate: "main", arguments: arguments, models: models)
for warning in generator.statistics.warnings {
    print("warning: \(warning.message)")
}
```

Warnings are `SourceDiagnostic` values with the code `mtl.letTypeMismatch` and the range of
the `let` block in its template. The same mismatch is reported once per run, even when it
recurs in every iteration of a loop. With the `checksLetTypes` option set to `false`, declared
types are not checked at all and every value is bound as it is, as in version 0.6.

### Collection parameters

A template, query or macro parameter may declare a collection type, such as
`Sequence(String)`, `OrderedSet(ecore::EClass)` or `Collection(T)`. With the
`collectionParameters` option at its default, `.conforming`, any collection whose elements
conform to the element type is accepted, including the value of a many-valued feature, and
the parameter holds it as a collection. Overloads are chosen by how closely the elements fit,
so `Sequence(Assignment)` is preferred to `Sequence(Statement)` for a collection of
assignments. A single model object also conforms to a collection type of its own type, as the
only element, but less specifically than to any other type. With `.exact`, as in version 0.6,
only collection values of the expression language conform to a collection type, whatever
their elements, and arguments are passed as they are.

### Behaviour options

`MTLOptions` selects how the generator behaves. Pass it to
`MTLGenerator(module:generationStrategy:options:serviceProviders:globals:)` or
`MTLExecutionContext(module:generationStrategy:options:aqlContext:protectedAreaManager:serviceProviders:)`.
`MTLOptions()` and `MTLOptions.standard` give the behaviour of this release, and
`MTLOptions.legacy` that of version 0.6. Each property selects one behaviour:

| Property | Default | Alternative |
|--|--|--|
| `aql` | `AQLOptions.standard`: the expression language behaves as in this release of swift-aql | `AQLOptions.legacy`, or any combination of its options, as described in the swift-aql README |
| `blockLineBreaks` | `.acceleo`: the line break after a block written on one line is dropped when the line is empty once the block has run, as in Acceleo 4 | `.kept`: the line break is always written |
| `collectionParameters` | `.conforming`: collections conform to collection types by their elements (see [Collection parameters](#collection-parameters)) | `.exact`: collection types are matched as in version 0.6 |
| `checksLetTypes` | `true`: `let` values are checked against their declared types | `false`: values are bound as they are |
| `letTypeMismatches` | `.error`: a `let` value that does not conform is a type error | `.skip`: the block is skipped with a warning (see [Typed let blocks](#typed-let-blocks)) |
| `cachesContainers` | `true`: containers are looked up once per run | `false`: every container lookup sees the models as they are |
| `unsetFeatureReads` | `.defaults`: unset features read as their defaults | `.undefined`: unset features read as `nil` |

The enumerations' raw values (`acceleo`, `kept`, `conforming`, `exact`, `error`, `skip`) double
as command-line spellings. For a block written on one line, such as
`[if (c)][helper()/][/if]` on a line of its own, `.acceleo` adds no blank line after the
output of `helper`, and an `[if (c)]...[/if]` on one line whose condition does not hold
produces no line when it starts its line; text before the block on its line, including white
space, keeps the line break.

`MTLOptions(semantics:)` selects `.standard` or `.legacy` from a `ModellingSemantics` value,
and `MTLOptions.fromEnvironment()` reads that choice from the `SWIFT_MODELLING_SEMANTICS`
environment variable (`standard` or `legacy`; `.standard` if it is unset, and an error for any
other value). A generator keeps the options it is created with for every template it runs:

```swift
let generator = MTLGenerator(
    module: module, generationStrategy: strategy, options: try MTLOptions.fromEnvironment())
```

Containers are found as the `containerLookup` option of `aql` says; with `.resources`, each
resource answers in the `ContainerLookupScope` configured for it or its resource set (see the
swift-aql README).

### Global variables

Global variables are visible to every template, query and macro, and are read like any other
variable (`[name/]`). Set them before generating, either through the initialiser or with
`setGlobalVariable(_:value:)`:

```swift
let generator = MTLGenerator(
    module: module, generationStrategy: strategy, options: .standard, globals: ["version": "1.2"])
generator.setGlobalVariable("author", value: "A. Person")
```

A global shadows nothing: a template parameter or `let` variable of the same name hides it
inside its own scope only. Templates, queries and macros are invoked with parentheses, so they
never clash with a global of the same name.

### Named parameters

`MTLParameterServices` turns `name=value` text (for example from command line options) into global variables and services. Names must be identifiers that the syntax does not reserve; `true` and `false` become booleans, canonical whole numbers become integers, and everything else is a string:

```swift
let parameters = try MTLParameterServices(arguments: ["package=org.example", "verbose=true"])
parameters.bind(to: generator)   // [package/] now reads the value
generator.register(parameters)   // parameter('package') and hasParameter('package')
```

Use `init(parameters:)` for text values, `init(values:)` for typed values, and `MTLParameterServices.parse(_:)` to read a single `name=value`. Problems throw `MTLParameterError`.

### Text resources

`MTLResourceServices` lets templates emit text files that are shipped beside them, such as support headers or licence texts, without copying that text into a template. Give it one or more root directories, searched in order; `init(module:roots:)` searches the directory of the parsed module first:

```swift
let module = try await MTLParser().parse(templateURL)
generator.register(MTLResourceServices(module: module, roots: [sharedResources]))
```

`resourceText('support/a.h')` returns the file content exactly as stored, and `resourceExists('support/a.h')` tells whether a root contains the file, so that `[file ('a.h', false, 'UTF-8')][resourceText('support/a.h')/][/file]` writes it verbatim. Paths are relative; empty or absolute paths, drive names and `..` components are rejected. Missing files, files that are not UTF-8 text and invalid paths throw `MTLResourceServicesError`.

### Calling queries from other hosts

`MTLQueryHelpers.helpers(for:generator:)` and `MTLQueryHelpers.helpers(for:options:)` list the `[query]` definitions of a module and the public queries of its imports as `MTLQueryHelper` values, each with a name, parameter types, return type and an asynchronous `call` closure. The first argument is the receiver, the first declared parameter, so `e.render('c')` maps onto `render(e : Expression, lang : String)`. `MTLQueryHelpers.call(_:arguments:among:)` picks the overload that fits the arguments, matching collection arguments as the `collectionParameters` of the generator's options say; without a generator, `helpers(for:generator:)` uses the options of version 0.6. Queries that follow references need the models that hold the objects: register them with `MTLGenerator.registerModel(_:resource:)` on the generator that you pass to `helpers(for:generator:)`. `MTLQueryServices` offers the same queries to AQL-based hosts as services, callable as `e.render('c')` and `render(e, 'c')`:

```swift
let generator = MTLGenerator(module: module, generationStrategy: MTLInMemoryStrategy(), options: .standard)
await generator.registerModel("IN", resource: resource)
let helpers = MTLQueryHelpers.helpers(for: module, generator: generator)
let text = try await MTLQueryHelpers.call("render", arguments: [element, "c"], among: helpers)
generator.register(MTLQueryServices(module: module, generator: generator))
```

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

## Compatibility with 0.6

The initialisers `MTLGenerator(module:generationStrategy:serviceProviders:globals:unsetFeatureReads:)`
and `MTLExecutionContext(module:generationStrategy:aqlContext:protectedAreaManager:serviceProviders:unsetFeatureReads:)`
keep their 0.6 signatures and behave as in version 0.6: they use `MTLOptions.legacy`, with the
given `unsetFeatureReads`. They are deprecated in favour of the initialisers that take
`options:`; pass `options: .legacy` to keep the behaviour of version 0.6. Likewise,
`MTLQueryHelper(name:parameterTypes:returnType:call:)` is deprecated in favour of the
initialiser that takes `collectionParameters:`, and `MTLQueryHelpers.helpers(for:)` and
`MTLQueryServices(module:)` without a generator use the options of version 0.6.

This release changes the following behaviours. Each has an option in `MTLOptions`:

| Behaviour | New default | Option | 0.6 behaviour |
|--|--|--|--|
| Expression language: collection arguments added whole, collection kinds kept, `including` on a single value giving a set, containers found through the resources | as in this release of swift-aql | `aql` | `AQLOptions.legacy` |
| Line break after a block written on one line | dropped when the line is empty once the block has run, as in Acceleo 4 | `blockLineBreaks` | `.kept` |
| Collections passed to collection-typed parameters | any collection whose elements conform, including many-valued features; references resolved to objects; a single object as the only element; overloads chosen by element types; collection-typed parameters hold collections | `collectionParameters` | `.exact` |
| Declared types of `let` variables | checked | `checksLetTypes` | `false` |
| Container lookups during a generation run | cached, so models may change only through services that declare `modifiesModels` | `cachesContainers` | `false` |

`MTLOptions.legacy` sets all of these to their 0.6 behaviour. Some changes only affect templates
that version 0.6 rejected, so they need no option: `let` variables of qualified and collection
types such as `ecore::EClass` or `Sequence(String)` now parse, and a directive missing its `]` is
reported where it opens, with the diagnostic code `mtl.unterminatedDirective`. Generation
statistics also report warnings, such as those of `letTypeMismatches: .skip`.

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
