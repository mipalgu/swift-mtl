# Understanding MTL

The concepts behind modules, invocations, whitespace handling, file output and protected areas.

## Overview

This article describes how the MTL package interprets the MOFM2T / Acceleo dialect. It
covers what the language does today and the limits that remain.

## Modules

A module is one `.mtl` file, represented by ``MTLModule``. Its header names the module and
lists at least one metamodel namespace URI:

```mtl
[module name('http://example.com/one', 'http://example.com/two') extends other::module/]
```

The trailing `/` is optional. The URIs are kept in ``MTLModule/metamodelURIs``, bound to
`EPackage` values with ``MTLModule/binding(to:)``, and the ones without a package are
listed in ``MTLModule/unboundMetamodelURIs``. A `[comment encoding = UTF-8 /]` before or
after the header sets ``MTLModule/encoding``.

A module contains templates, queries, macros and imports. Imports (`[import a::b/]`) may
appear anywhere at the top level. Text outside templates is ignored.

### Comments

- `[comment text /]` ends at the first `/]`.
- `[comment]...[/comment]` is a block comment holding any text.
- `[-- text]` ends at the next `]`.
- `[** ... **/]` is a documentation comment, attached to the following template, query
  or macro (see ``MTLTemplate/documentation``).

## Templates, queries and macros

A ``MTLTemplate`` produces text:

```mtl
[template protected name(p : Type, q : Other) ? (guard) post (expr) overrides parent]
...
[/template]
```

- Visibility is `public` (the default), `protected` or `private` (see ``MTLVisibility``).
- A guard is written `? (condition)` or `guard (condition)`. A template whose guard is
  false produces nothing.
- `post (expr)` is applied to the generated text with `self` bound to that text, so
  `post (trim())` strips surrounding white space. A Boolean result acts as a
  post-condition instead.
- `overrides name` records which template is overridden. The clauses may appear in any
  order.
- Parameter types may be qualified (`ecore::EClass`) or collection types with an element
  type (`Sequence(String)`).
- A template marked with `[comment @main /]` in its body, or `@main` in its documentation
  comment, has ``MTLTemplate/isMain`` set.

A ``MTLQuery`` is a named expression: `[query public name(p : T) : R = expr/]`.

A ``MTLMacro`` is `[macro name(p : T, body : Body)]...[/macro]`. Macros have no
visibility. A parameter of type `Body` receives the text between the tags of the call,
`[name(args)]body[/name]`, generated in the caller's scope.

`self` is bound to the first argument of every template, query and macro.

## Statements

Template bodies are sequences of ``MTLStatement`` values:

- literal text: ``MTLTextStatement``
- `[expression/]`: ``MTLExpressionStatement``
- line breaks: ``MTLNewLineStatement``
- comments: ``MTLComment``
- `[for ...]`: ``MTLForStatement``
- `[if]`, `[elseif]`, `[else]`: ``MTLIfStatement``
- `[let ...]`: ``MTLLetStatement``
- `[file ...]`: ``MTLFileStatement``
- `[protected ...]`: ``MTLProtectedArea``
- `[name(args)]...[/name]`: ``MTLMacroInvocation``

### For loops

```mtl
[for (x : T | coll) separator(', ') before('(') after(')')]...[/for]
```

The type is optional, the older `in` form (`x : T in coll`) is accepted, and the
binding may be left out entirely (`[for (coll)]`), in which case the iterator is `self`.
The `separator`, `before` and `after` clauses may come in any order. `before` and `after`
produce output only for a non-empty collection. Inside the body, `i` is a one-based
counter, unless a loop variable is itself named `i`. Nested loops each have their own
counter.

### Let and if

`[let a = e, b = f]...[/let]` binds several variables for its body. A variable may declare
a type, as in `[let names : Sequence(String) = e]`; a value that does not conform to the
declared type is a type error, while `null` conforms to every type. With
``MTLOptions/checksLetTypes`` set to `false`, as in version 0.6, declared types are not checked
and every value is bound as it is. `[if (cond)]`,
`[elseif (cond)]` and `[else]` select text, and `if ... then ... else ... endif` is also an
expression.

The [OMG MOFM2T specification](https://www.omg.org/spec/MOFM2T/1.0) and Acceleo 3 treat a
typed `let` as a type test instead: when the value does not conform, the body is skipped
silently. To follow them, set the
``MTLOptions/letTypeMismatches`` of the options of the ``MTLGenerator`` (or
``MTLExecutionContext``) to ``MTLLetTypeMismatches/skip``. A mismatch then
skips the remaining bindings and the body of the block, generation continues after it, and a
warning with the code ``MTLDiagnosticCode/letTypeMismatch`` that names the variable, its
declared type and the type of the value is recorded in ``MTLGenerationStatistics/warnings``:

```swift
let generator = MTLGenerator(
    module: module, generationStrategy: strategy, options: MTLOptions(letTypeMismatches: .skip))
try await generator.generate(mainTemplate: "main", arguments: arguments, models: models)
for warning in generator.statistics.warnings {
    print("warning: \(warning.message)")
}
```

The same mismatch is reported once, even when it recurs in every iteration of a loop.

## Expressions

Expressions are swift-aql nodes (`AQLExpression`) built by ``MTLParser`` and evaluated by
swift-aql against the registered models. The parser supports:

- `if/then/else/endif`, `let x = e in body`, `implies` (right associative and loosest),
  `xor`, `or`, `and`, comparisons, `+ - * /`, `mod`, `div` (the AQL integer division operator), unary `not` and `-`;
- integer, real, string (with `\\` and `\'` escapes) and `null` literals;
- qualified names: `pkg::Type` is an `AQLTypeLiteralExpression` and `pkg::Enum::literal` an
  `AQLEnumLiteralExpression`; inside the arguments of a type operation every qualified name
  is a type;
- collection literals `Sequence{...}`, `OrderedSet{...}`, `Set{...}` and `Bag{...}`
  (`AQLCollectionLiteralExpression`);
- navigation `a.b` and calls `a.b(x)`. A call written with `.` on a collection applies to
  each element, as navigation does, so `[names.size()/]` gives the length of each name while
  `[names->size()/]` gives the number of names. With the `dotCalls` option of
  ``MTLOptions/aql`` set to `.collection`, as in version 0.6, both give the number of names.
  A dot call that reaches an element without the service while the collection has one, as in
  `[Sequence{1, 2}.size()/]`, adds a warning with its line and column, suggesting `->`, to
  ``MTLExecutionContext/warnings`` and ``MTLGenerationStatistics/warnings``;
- `->name(args)` for any name. The known iterators `select`, `reject`, `collect`, `any`,
  `exists`, `forAll`, `indexOf`, `size`, `isEmpty`, `notEmpty`, `first` and `last`
  become AQL collection expressions, other names become `AQLCallExpression` nodes that
  use the arrow, so the library receives the collection. A lambda argument `(x | body)`
  or `(x : T | body)` becomes an `AQLLambdaExpression`;
- iterator bodies without a variable, such as `->select(oclIsKindOf(EClass))` or
  `->sortedBy(size())`, which use `self` as the implicit iterator;
- the type operations `oclIsKindOf`, `oclIsTypeOf`, `oclAsType` and `oclIsUndefined`. The
  bare form applies to `self`.

### Model objects in the output

An expression tag whose value is a model object, such as `[person/]`, writes the name of the
class of the object followed by the values of its attributes, as in
`Person (name: Alice, age: 42)`. This follows the text that Acceleo writes for an object of a
class generated by the Eclipse Modeling Framework, without the Java class name and hash code,
which change from run to run: the same model always gives the same text. Each class in the
hierarchy of the object contributes its own parenthesised group, from the most general class
to the class of the object, as in `Employee (name: Bob, age: 0) (salary: 100)`. References
and volatile attributes are left out, an unset attribute shows its default value (or
`<unset>` if it is unsettable), a value without text shows as `null`, and a many-valued
attribute as a bracketed list such as `[a, b]`. An enumeration literal is written as its
literal. A collection of objects writes the text of each object in turn, and `[collect]`
collects the same text. With the ``MTLOptions/objectText`` of the ``MTLOptions`` set to
``MTLObjectText/swift``, as in version 0.6, an object is written as its Swift description
instead. Other values, such as strings, numbers and Booleans, are written the same way under
either choice. The AQL `toString()` service and the `+` operator give an object the text that
swift-aql gives it, which is not affected by this option.

### Unset features

Reading a feature that has not been set follows the Eclipse Modeling Framework's `eGet`.
An unset single-valued attribute reads as its declared default or the default of its data
type (`false`, `0`, `0.0` or the first literal of an enumeration), and an unset many-valued
feature reads as an empty collection. An unset string, wrapper, character, date or
arbitrary-precision attribute without a declared default, or an unset single-valued
reference, reads as `nil`, and `[expression/]` prints nothing for `nil`, so an unset string
appears as empty text while an unset integer prints `0`. To read every unset feature as
`nil` instead, set the ``MTLOptions/unsetFeatureReads`` of the ``MTLOptions`` of the
``MTLGenerator`` (or ``MTLExecutionContext``) to `.undefined`.

The text escapes `['['/]` and `[']'/]` produce literal brackets.

An ``MTLExpression`` wraps one of these nodes. Calls to templates, queries and macros are
``MTLInvocationExpression`` nodes. They can occur inside any expression, so
`[if (isBig(n))]` and `[for (x | items())]` work.

## Invocation resolution

For `[name(args)/]` the runtime looks for a matching element in this order:

1. elements declared in the current module, including private ones;
2. public and protected elements of the modules it extends;
3. public elements of imported modules and of their parent modules;
4. services registered with the generator or the execution context (see
   <doc:UnderstandingMTL#AQL-services>);
5. the AQL standard library (functions such as `min`, `max`, `abs` and `toString`).

Imports are not transitive. Protected and private elements are never visible through an
import, and protected elements are visible only to extending modules. The receiver form
`[x.name(a)/]` passes `x` as the first argument, and a template called on a collection
(`[coll.tmpl()/]`) runs once per element with the texts concatenated.

### Overloading

Templates and queries may share a name when their parameter types differ. Identical
signatures are an error. Among the applicable overloads the one with the smallest total
type distance wins: an exact metaclass match costs 0, each supertype step adds 1, and
`OclAny` or `null` cost a large amount. Ties go to the most derived module.

With ``MTLCollectionParameters/conforming``, the default ``MTLOptions/collectionParameters``,
a collection, such as the value of a many-valued feature, matches a collection type such
as `Sequence(T)` when every element conforms to `T`; nested types such as
`Sequence(Sequence(String))` are checked level by level. It costs 1 plus the cost of its
least specific element, so `Sequence(Assignment)` is preferred to `Sequence(Statement)`
for a collection of assignments, and any collection type is preferred to `OclAny`. A
collection type without an element type, such as `Sequence`, accepts any collection for 1.
An empty collection matches every collection type for 1, whatever its element type. A
single model object also matches a collection type of its own type, as its only element,
but less specifically than any other type. A parameter of a collection type holds its
argument as a collection. The same rules decide whether a value conforms to the declared
type of a `let` variable. With ``MTLCollectionParameters/exact``, as in version 0.6, any
collection value of the expression language matches any collection type for 1, whatever
its elements, and arguments are passed as they are.

### Extends and overriding

A module that `extends` another inherits its public and protected templates and queries.
Calls inside the base module dispatch dynamically to the most specific override in the
module being run, so a template in the parent that calls `[greet(name)/]` uses the
overriding `greet` of the derived module:

```mtl
[module derived('http://example.com/derived') extends base/]
[template public greet(name : String) overrides greet]Howdy [name/][/template]
```

Overriding templates record their target in ``MTLTemplate/overrides``. Inheritance
and imports are discovered through ``MTLModule/extendedModule``,
``MTLModule/importedModules``, ``MTLModule/templates(named:)`` and
``MTLModule/queries(named:)``.

### Loading modules

``MTLModuleResolver`` maps `a::b::c` to `a/b/c.mtl`. It tries the importing file's
directory first and then each search path in order. ``MTLModuleLoader`` loads a module
file with its imports and parent recursively, visiting each file once per call. A cycle
throws ``MTLModuleResolutionError/cycle(_:)`` and a missing module throws
``MTLModuleResolutionError/notFound(module:searched:requiredBy:)``. ``MTLParser`` performs
the same work when parsing a file, and ``MTLParser/parseWithoutLinking(_:)`` skips it.

To link without touching the file system, for example from the documents an editor has open,
give the parser an ``MTLModuleSource``, which returns the text and a location for a module
name. The linker asks the source first and falls back to the search paths for modules it
does not know:

```swift
let parser = MTLParser(moduleSource: openDocuments)
let module = try await parser.link(try await parser.parse(text, filename: "main.mtl"))
```

## AQL services

Operations written as `receiver.name(args)`, `receiver->name(args)` and `name(args)` that
are not templates, queries or macros of the module are resolved against registered AQL
services, and finally against the AQL standard library. A dot call on a collection is
resolved for each element (see <doc:UnderstandingMTL#Expressions>). Register additional
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

Every model passed to ``MTLGenerator/generate(mainTemplate:arguments:models:)`` or registered
with ``MTLExecutionContext/registerModel(_:resource:)`` is also made known to AQL, so
`eContainer()` and `allInstances()` can see its objects. The AQL library counts strings and
collections from one (`'hello'.substring(1, 2)`, `seq->at(1)`).

With ``MTLOptions/cachesContainers`` set (the default), the container of each model object is
looked up once during a generation run and reused by `eContainer()`, `ancestors()` and the
sibling services. Templates do not change their models; a service that does must be created
with `modifiesModels: true`, so that later containment queries see the change.

## Whitespace

MTL follows the MOFM2T rule for standalone lines. A line holding only block tags (template,
macro, `for`, `if`, `elseif`, `else`, `let`, `file`, `protected`, macro invocation tags and
their closing tags, and comments) plus white space produces no output: its leading white
space and line break are dropped. A line with text or an expression tag keeps its line
break. For example:

```mtl
[for (x | Sequence{'a', 'b'})]
- [x/]
[/for]
done
```

produces `- a`, `- b` and `done`, each followed by a line break. A block that shares its
line with text, such as `[if (true)]a[/if]`, keeps the line break.

A line break directly after an expression tag is not duplicated, and with
``MTLBlockLineBreaks/acceleo``, the default ``MTLOptions/blockLineBreaks``, neither is one
after a closing block tag. It is dropped when the expression, or the block that closes
there, wrote text ending in a line break, so a template call such as `[helper()/]` or
`[if (c)][helper()/][/if]` on a line of its own adds no blank line after the output of
`helper`. The line break is also dropped when nothing has been written on its line: an expression tag that produces nothing, an
`[if (c)]...[/if]` written on one line whose condition does not hold, or a `[for]` written
on one line over an empty collection produces no line when it starts its line. Text before
it on its line, including white space, keeps the line break. With
``MTLBlockLineBreaks/kept``, as in version 0.6, the line break after a closing block tag is
always written.

Text is otherwise emitted literally, as in Acceleo 3. Block bodies are not re-indented
automatically. A multi-line result of an expression, for example from a template call,
inherits the leading white space of the line on which the expression starts. A collection
result of an expression tag is written as the concatenation of its elements. Windows line
endings are handled like Unix ones.

## File blocks and modes

`[file (url, mode, charset)]...[/file]` sends its content to a separate file obtained
from the generation strategy. The mode is one of:

- `false`, `'overwrite'` or `overwrite` (the default), which replaces earlier content;
- `true`, `'append'` or `append`, which adds to what was written before;
- `'create'` or `create`, which leaves an existing file untouched (the body is not evaluated and no error is raised);
- any other expression, evaluated when the file opens. The value must be a Boolean or one
  of the mode strings. Anything else is an error.

An unknown mode string is a syntax error. The charset is honoured by the bundled
strategies (``MTLCharset``): UTF-8, UTF-16, UTF-16BE, UTF-16LE, ISO-8859-1 and US-ASCII.
A character the charset cannot represent, or an unsupported charset, is an error and
nothing is written. Further `'key=value'` options may follow the charset
(``MTLFileOptions``): `'merge=false'` excludes the file from the module's `[merge]`
declaration and `'layout=false'` from its `[layout]` declaration. A file block on its own
lines contributes only its content.

Two built-in services expose the file context to templates:

- `fileExists(path)` is true if a file exists at the path, relative to the generation base
  path (or absolute). Files written earlier in the same run count.
- `forceOverwrite()` returns the `forceOverwrite` generator option.

```mtl
[if (not fileExists('plugin.xml'))]
[file ('build.properties')]...[/file]
[/if]
```

## Collected sets and deferred blocks

Values such as imports or includes can be gathered while a file is generated and rendered
once the file body is complete. Sets are scoped to the enclosing `[file]` block, keep
insertion order and ignore duplicates.

```mtl
[collect ('imports', 'a.b.C')/]
[collect ('imports', typeNames)/]
[emit ('imports') in(items->sortedBy(s | s)) separator('\n')]import [item/];[/emit]
```

- `[collect ('set', expr)/]` adds a string or a collection of strings.
- `[emit ('set') ...]...[/emit]` marks where the set is rendered. The block is rendered once
  per element with `item` bound to the element and `items` bound to the whole collection.
  Optional clauses: `separator(text)` between elements, `in(expr)` to sort, group or filter
  the elements (evaluated with `items` bound), and `once` to render the block a single time
  with `items` bound and `item` unbound. Emit blocks cannot be nested.
- `collected('set')` returns the values collected so far, for example for conflict checks.

## Regeneration merge

A module can declare how an existing target file is merged with new output:

```mtl
[merge ('/**', '*/', '@generated', '@generated NOT', 'braces')/]
```

The arguments are the start and end of a leading comment (an empty end means a line
comment), the generated tag, the keep tag and the strategy (`braces` or `indentation`, by
default `braces`). Further `'key=value'` arguments adjust the lexical conventions:
`lineComments` (space-separated markers), `blockComment` (start and end separated by a
space), `quotes`, `terminators` (characters that end a member; `\n` for languages whose
statements end at a line break), `opener` and `files`.

`files` restricts the merge to matching files, as a space-separated list of glob patterns
such as `'files=*.java'`. `*` matches any characters except `/`, `**` matches any
characters, and `?` matches one character. A pattern without `/` is matched against the
last path component of the file URL, any other pattern against the whole URL. Files that do
not match, and file blocks with the `'merge=false'` option, are written as plain overwrites.
Without `files` the merge applies to every file.

When the target exists and force overwrite is off, blocks whose leading comment contains the
keep tag, or no tag at all, are preserved; blocks with the generated tag are replaced; new
tagged blocks are added; and generated blocks that are no longer produced are removed.
Blocks are matched by normalised signature within the matching parent. Lines of an `[emit]`
region present in the old file but missing from the new one are kept.

Only the leading comment of a block, written in the declared comment form, carries the
tags. Tags in other comments (line comments inside a body, comments of another form, or
comments further above that are not part of the leading comment) and in string literals
are ignored, so a generated method whose body mentions the keep tag is replaced as a whole.
When the comment end is empty, only the unbroken run of line comments directly above the
block counts; a blank line ends the run.

A generated block that contains tagged members is merged member by member: its header and
closing line come from the new text, and kept members retain their text verbatim. A kept
container stays exactly as it is in the existing file.

## Layout conversion

`[layout ('indent=\t', 'targetIndent=  ', 'opener=sameLine', 'files=*.java')/]` converts the
layout of generated files to a code style without any knowledge of the target language
(``MTLLayoutConfiguration``). Each leading indentation unit is replaced, and with
`opener=sameLine` an opener that stands alone on its line moves to the end of the preceding
line unless that line ends in a statement terminator or a comment, or is itself an opener.
Comments and string literals are never altered by opener placement. The comment markers
(`lineComments`, `blockComment`), `quotes`, `terminators` and opener token (`openerToken`,
by default `{`) are data of the declaration, and `files` scopes it with the same globs as
`[merge]`.

Layout conversion runs on the freshly generated text before it is merged with an existing
file, so that the merge compares like with like, and protected areas preserved from an
existing file are left as they are. The generator option ``MTLGeneratorOptions/layout``
overrides the module declaration, `'layout=false'` on a `file` block opts that file out
(``MTLFileOptions``), and ``MTLLayoutPostProcessor`` applies a configuration as a
post-processor. After a layout change, regenerated headers and closing lines of merged
blocks follow the new layout, and a second run changes nothing.

## Protected areas

`[protected (id)]default[/protected]` writes a pair of marker lines around the body:

```text
START PROTECTED REGION id
...
END PROTECTED REGION id
```

The marker lines can be preceded by prefixes, positionally as
`[protected ('id', '// ', '// ')]` or with the Acceleo clauses
`[protected ('id') startTagPrefix('// ') endTagPrefix('// ')]`. No prefix is derived from the
file extension.

If the execution context already holds content for that identifier, it is written instead
of the body. When a file block overwrites an existing file, the protected areas of that file
are read first, so their content is preserved automatically on regeneration. Content can
also be supplied with ``MTLExecutionContext/setProtectedAreaContent(_:content:markers:)`` or
directly on an ``MTLProtectedAreaManager``, which can scan text or a file for existing
regions with ``MTLProtectedAreaManager/scanContent(_:)`` and
``MTLProtectedAreaManager/scanFile(_:)``.

## Generation strategies and the execution context

``MTLGenerator`` owns an ``MTLExecutionContext`` for one module and a generation
strategy. ``MTLGenerator/generate(mainTemplate:arguments:models:)`` registers the models,
finds the main template in the module or its parents (overloads are told apart by argument
count), runs it and finalises the output.

An ``MTLGenerationStrategy`` creates and finalises an ``MTLWriter`` for each output
target. ``MTLInMemoryStrategy`` stores text by file name, with the main output under
`stdout` (``MTLStandardOutput/fileName``). ``MTLFileSystemStrategy`` writes below a base path
and never writes text produced outside a file block to disk; it discards that text, keeps it
for ``MTLFileSystemStrategy/standardOutput`` or passes it to a handler, as chosen with
``MTLStandardOutputSink``. The context tracks variable
scopes, the current ``MTLIndentation``, protected areas and trace links
(``MTLTraceLink``). Implement the protocol to send output elsewhere.

### Generator options and post-processing

``MTLFileSystemStrategy`` and ``MTLInMemoryStrategy`` accept ``MTLGeneratorOptions``
(``MTLGeneratorOptions/forceOverwrite``, ``MTLGeneratorOptions/redirectionPattern`` such as
`.{0}.new`, ``MTLGeneratorOptions/lineDelimiter`` and ``MTLGeneratorOptions/layout``) and an
ordered list of ``MTLFilePostProcessor`` values that transform the content before it is
written.

Line endings in generated output follow the template text: templates with CRLF line endings
parse like LF ones and produce CRLF output. Setting ``MTLGeneratorOptions/lineDelimiter`` to
a value other than `"\n"` rewrites every line ending in the written file to that delimiter.
On Windows, keep template files byte-exact with a `.gitattributes` entry such as
`*.mtl -text` if the output must use LF.

### Progress and cancellation

``MTLGenerator/generate(mainTemplate:arguments:models:progress:)`` reports an
``MTLProgress`` (templates executed, files written, the current template and file) on the
main actor. Generation checks for task cancellation at the start of every block and loop
iteration and regularly lets other work on the main actor proceed, so a cancelled run throws
`CancellationError` and a run on the main actor keeps the user interface responsive.

## Global variables and parameters

Global variables are visible to every template, query and macro, and are read like any other
variable (`[name/]`). Set them before generating, either through the initialiser or with
``MTLGenerator/setGlobalVariable(_:value:)``:

```swift
let generator = MTLGenerator(
    module: module, generationStrategy: strategy, options: .standard, globals: ["version": "1.2"])
generator.setGlobalVariable("author", value: "A. Person")
```

A template parameter or `let` variable of the same name hides a global inside its own scope
only. Templates, queries and macros are invoked with parentheses, so they never clash with a
global of the same name.

``MTLParameterServices`` turns `name=value` text, for example from command-line options, into
global variables and services. Names must be identifiers that the syntax does not reserve;
`true` and `false` become Booleans, canonical whole numbers become integers, and everything
else is a string:

```swift
let parameters = try MTLParameterServices(arguments: ["package=org.example", "verbose=true"])
parameters.bind(to: generator)   // [package/] now reads the value
generator.register(parameters)   // parameter('package') and hasParameter('package')
```

Use ``MTLParameterServices/init(parameters:)`` for text values,
``MTLParameterServices/init(values:)`` for typed values, and
``MTLParameterServices/parse(_:)`` to read a single `name=value`. Problems throw
``MTLParameterError``.

### Text resources

``MTLResourceServices`` lets templates emit text files that are shipped beside them, such as
support headers or licence texts, without copying that text into a template. Give it one or
more root directories, searched in order; ``MTLResourceServices/init(module:roots:)``
searches the directory of the parsed module first:

```swift
let module = try await MTLParser().parse(templateURL)
generator.register(MTLResourceServices(module: module, roots: [sharedResources]))
```

`resourceText('support/a.h')` returns the file content exactly as stored, and
`resourceExists('support/a.h')` tells whether a root contains the file, so that
`[file ('a.h', false, 'UTF-8')][resourceText('support/a.h')/][/file]` writes it verbatim.
Paths are relative; empty or absolute paths, drive names and `..` components are rejected.
Missing files, files that are not UTF-8 text and invalid paths throw
``MTLResourceServicesError``.

### Calling queries from other hosts

``MTLQueryHelpers/helpers(for:generator:)`` and ``MTLQueryHelpers/helpers(for:options:)``
list the `[query]` definitions of a module and the public queries of its imports as
``MTLQueryHelper`` values, each with a name, parameter types, return type and an
asynchronous `call` closure. The first argument is the receiver, the first declared
parameter, so `e.render('c')` maps onto `render(e : Expression, lang : String)`.
``MTLQueryHelpers/call(_:arguments:among:)`` picks the overload that fits the arguments,
matching collection arguments as the ``MTLOptions/collectionParameters`` of the generator's
options say. Queries that follow references need the models that hold the objects: register
them with ``MTLGenerator/registerModel(_:resource:)`` on the generator that you pass in.
``MTLQueryServices`` offers the same queries to AQL-based hosts as services, callable as
`e.render('c')` and `render(e, 'c')`:

```swift
let generator = MTLGenerator(
    module: module, generationStrategy: MTLInMemoryStrategy(), options: .standard)
await generator.registerModel("IN", resource: resource)
let helpers = MTLQueryHelpers.helpers(for: module, generator: generator)
let text = try await MTLQueryHelpers.call("render", arguments: [element, "c"], among: helpers)
generator.register(MTLQueryServices(module: module, generator: generator))
```

## Editor support

``MTLParser/parseDiagnosing(_:filename:)`` parses without stopping at the first mistake. It
skips to the end of a broken directive (or to the matching closing tag of a broken block)
and to the end of a broken template, query or macro, and returns the module that could be
read, the diagnostics (`SourceDiagnostic` values with ranges and stable
``MTLDiagnosticCode`` codes) and an outline of the module. ``MTLSyntax/tokens(in:)`` splits
template text, directives and expressions into highlighting tokens and never fails. Parsed
statements, declarations and expressions carry an `origin` with their range in the source
text; origins never take part in equality.

## Limits

- Types are matched by classifier name. A package qualifier, as in
  `oclIsKindOf(ecore::EClass)`, does not restrict the match.
- No protected area marker prefix is derived from the file extension; prefixes are given in
  the `protected` block.
- Only the charsets listed under <doc:UnderstandingMTL#File-blocks-and-modes> are
  supported.
- Macros have no visibility.
- Imports are not transitive.
