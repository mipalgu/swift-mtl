# Understanding MTL

The concepts behind modules, invocations, whitespace handling, file output and protected areas.

## Overview

This article describes how the MTL package interprets the MOFM2T / Acceleo dialect. It
covers what the language does today, including the limits that come from the current
swift-aql release.

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

`[let a = e, b = f]...[/let]` binds several variables for its body. `[if (cond)]`,
`[elseif (cond)]` and `[else]` select text, and `if ... then ... else ... endif` is also an
expression.

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
- navigation `a.b` and calls;
- `->name(args)` for any name. The known iterators `select`, `reject`, `collect`, `any`,
  `exists`, `forAll`, `indexOf`, `size`, `isEmpty`, `notEmpty`, `first` and `last`
  become AQL collection expressions, other names become `AQLCallExpression` nodes that
  use the arrow, so the library receives the collection. A lambda argument `(x | body)`
  or `(x : T | body)` becomes an `AQLLambdaExpression`;
- iterator bodies without a variable, such as `->select(oclIsKindOf(EClass))` or
  `->sortedBy(size())`, which use `self` as the implicit iterator;
- the type operations `oclIsKindOf`, `oclIsTypeOf`, `oclAsType` and `oclIsUndefined`. The
  bare form applies to `self`.

The text escapes `['['/]` and `[']'/]` produce literal brackets.

An ``MTLExpression`` wraps one of these nodes. Calls to templates, queries and macros are
``MTLInvocationExpression`` nodes. They can occur inside any expression, so
`[if (isBig(n))]` and `[for (x | items())]` work.

## Invocation resolution

For `[name(args)/]` the runtime looks for a matching element in this order:

1. elements declared in the current module, including private ones;
2. public and protected elements of the modules it extends;
3. public elements of imported modules and of their parent modules;
4. the AQL library (functions such as `min`, `max`, `abs` and `toString`).

Imports are not transitive. Protected and private elements are never visible through an
import, and protected elements are visible only to extending modules. The receiver form
`[x.name(a)/]` passes `x` as the first argument, and a template called on a collection
(`[coll.tmpl()/]`) runs once per element with the texts concatenated.

### Overloading

Templates and queries may share a name when their parameter types differ. Identical
signatures are an error. Among the applicable overloads the one with the smallest total
type distance wins: an exact metaclass match costs 0, each supertype step adds 1, and
`OclAny` or `null` cost a large amount. Ties go to the most derived module.

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
A character the charset cannot represent is an error. Further `'key=value'` options may
follow the charset (``MTLFileOptions``): `'merge=false'` excludes the file from the
module's `[merge]` declaration. The built-in `fileExists(path)` and `forceOverwrite()`
services let a template inspect the file context. A file block on its own lines contributes only its content.

## Layout conversion

`[layout ('indent=\t', 'targetIndent=  ', 'opener=sameLine', 'files=*.java')/]` converts the
layout of generated files to a code style without any knowledge of the target language
(``MTLLayoutConfiguration``). Each leading indentation unit is replaced, and with
`opener=sameLine` an opener that stands alone on its line moves to the end of the preceding
line unless that line ends in a statement terminator or a comment, or is itself an opener.
Comments and string literals are never altered by opener placement, and the comment markers,
quotes, terminators and opener token are data of the declaration.

Layout conversion runs on the freshly generated text before it is merged with an existing
file, so that the merge compares like with like, and protected areas preserved from an
existing file are left as they are. The generator option ``MTLGeneratorOptions/layout``
overrides the module declaration, `'layout=false'` on a `file` block opts that file out
(``MTLFileOptions``), and ``MTLLayoutPostProcessor`` applies a configuration as a
post-processor.

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
of the body. Content can be supplied with
``MTLExecutionContext/setProtectedAreaContent(_:content:markers:)`` or directly on an
``MTLProtectedAreaManager``, which can also scan text or a file for existing regions with
``MTLProtectedAreaManager/scanContent(_:)`` and ``MTLProtectedAreaManager/scanFile(_:)``.
Automatic scanning of the files about to be overwritten by a generation run is not part
of the package yet.

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

## Limits

- The swift-aql release this package builds on lacks most of the Acceleo standard
  library. String services such as `toUpperFirst`, `replaceAll` and `tokenize`, and
  collection services such as `sortedBy`, `asSet`, `including`, `sum`, `reverse` and `at`,
  are parsed but cannot be evaluated yet. Neither can `div`.
- `toString` of a number prints `Optional(7)`, `trim()` does not remove line breaks, and
  `String + Integer` is a type error.
- Method-style calls on collections such as `coll.size()` do not evaluate. Write
  `coll->size()`.
- Qualified type names in `oclIsKindOf(ecore::EClass)` are passed as the full string, and
  the released AQL compares unqualified names for dynamic objects only.
- Protected area scanning of existing files, deferred blocks, tagged-block merging and
  post-processors are not part of the package.
- Imports are not transitive.
