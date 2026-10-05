# MTL Language Reference

This document describes the dialect of the OMG MOFM2T / Acceleo model-to-text
language implemented by swift-mtl. Every construct described here is parsed by
`MTLParser` and covered by the package tests. Where a construct parses but cannot
yet be evaluated, the text says so (see
[Differences from Acceleo and current limits](#differences-from-acceleo-and-current-limits)).

Expressions are swift-aql expressions: the parser builds swift-aql AST nodes,
and models are read through swift-ecore.

## Contents

1. [Module structure](#module-structure)
2. [Comments](#comments)
3. [Imports and extends](#imports-and-extends)
4. [Templates](#templates)
5. [Queries](#queries)
6. [Macros](#macros)
7. [Statements](#statements)
8. [Invocations and resolution order](#invocations-and-resolution-order)
9. [Expressions and operators](#expressions-and-operators)
10. [Collection operations](#collection-operations)
11. [Escapes](#escapes)
12. [Whitespace rules](#whitespace-rules)
13. [Grammar summary](#grammar-summary)
14. [Differences from Acceleo and current limits](#differences-from-acceleo-and-current-limits)

## Module structure

A module is a file with the extension `.mtl`. It starts with a module header,
followed by any number of imports, templates, queries and macros. Text outside
these declarations is not generated.

```mtl
[module HelloWorld('http://example.com')/]

[template main()]
Hello, World!
[/template]
```

The header lists one or more metamodel URIs in single quotes, separated by
commas. At least one URI is required. The closing `/` before `]` is optional.

```mtl
[module generate('http://www.eclipse.org/emf/2002/Ecore', 'http://example.com/other')/]
```

The URIs are recorded in `MTLModule.metamodelURIs`. Supplying the corresponding
packages to `MTLModule.binding(to:)` returns a module in which the matched URIs
are bound; the ones that no package matched remain in
`MTLModule.unboundMetamodelURIs`.

A module may extend another module:

```mtl
[module derived('http://example.com') extends base/]
```

A module name may be qualified when used in `extends` and `import`
(`other::module`).

### Layout conversion

A module can ask for generated files to be converted to a code style, without
the engine knowing anything about the target language:

```mtl
[layout ('indent=\t', 'targetIndent=  ', 'opener=sameLine', 'files=*.java')/]
```

Every argument is a string of the form `key=value`. Unknown keys and a second
`[layout]` declaration are syntax errors. The keys are:

| Key | Meaning | Default |
| --- | --- | --- |
| `indent` | the indentation unit the templates write | a tab |
| `targetIndent` | the indentation unit to produce | a tab |
| `opener` | `ownLine` (leave as generated) or `sameLine` | `ownLine` |
| `openerToken` | the opener, a single character | `{` |
| `lineComments` | space-separated line comment markers | `//` |
| `blockComment` | block comment start and end, separated by a space | `/* */` |
| `quotes` | the characters that delimit string and character literals | `"` and `'` |
| `terminators` | characters that end a statement | `;` |
| `files` | space-separated glob patterns (as for `[merge]`) | all files |

Values keep their white space, so `'indent=  '` is two spaces; the escapes `\t`
and `\n` work as in any string literal.

*Indentation.* Each occurrence of `indent` at the very start of a line becomes
`targetIndent`. Only the unbroken run of units at the start of a line is
converted: text inside a line, and anything after the first character that is
not a unit, is untouched, so continuation alignment survives. Lines that
contain only units are converted too. Lines inside comments are converted;
lines that begin inside a multi-line string literal are not. Applying the
conversion twice is harmless unless `targetIndent` starts with `indent` (for
example two spaces to four), so the generator applies it exactly once.

*Opener placement.* With `opener=sameLine`, an opener that stands alone on its
line moves to the end of the preceding line, separated by one space. The rules:

1. The opener is code: openers in comments and string literals never move.
2. Only spaces and tabs surround it on its line (a `\n` or `\r\n` must follow;
   an opener at the very end of the text does not move).
3. An earlier non-blank line exists; the blank lines between it and the opener
   are removed, along with trailing blanks of that line and the blanks around
   the opener. Everything else keeps its place, including the indentation of
   the earlier line and the line break that follows the opener.
4. The last character of the earlier line is not a terminator, so a block that
   follows a complete statement keeps its own line.
5. That character is not itself an opener, so two openers never share a line.
6. That character is code, or the end of a closed block comment or string
   literal. A line that ends in a line comment, or inside a block comment, is
   never joined.

The rules do not know any keyword: `else`, `catch`, `finally`, annotations,
anonymous classes and array initialisers all follow from the rules above. A
closer on the earlier line is joined as well (`}` then `{` becomes `} {`).

*Order and merging.* The generator converts the freshly generated text before
it is merged with an existing file, because the existing file is already in the
target layout. Kept blocks therefore compare and survive unchanged, and the
`[emit]` regions are re-aligned when lines disappear. Text preserved from an
existing file by `[protected]` is never converted.

*Scope and precedence.* `files` limits the declaration to matching files. A
`[file]` block opts out with `'layout=false'`:
`[file ('plugin.xml', 'overwrite', 'UTF-8', 'layout=false')]`. The generator
option `MTLGeneratorOptions.layout` replaces the module's declaration (its own
`files` patterns then apply), but a `layout=false` file stays unconverted.

## Comments

Four forms exist.

```mtl
[comment this comment ends at the first slash-bracket /]

[comment]
A block comment. It may contain any text, including [brackets].
[/comment]

[-- this comment ends at the next closing bracket]

[**
 * A documentation comment, attached to the next template, query or macro.
 * @main
 **/]
```

| Form | Ends at |
| --- | --- |
| `[comment text /]` | the first `/]` |
| `[comment]...[/comment]` | `[/comment]` |
| `[-- text]` | the first `]` |
| `[** ... **/]` | `**/]` |

Comments produce no output. A documentation comment is stored in the
`documentation` property of the template, query or macro that follows it.

Two comments carry meaning:

- `[comment encoding = UTF-8 /]`, before or after the module header, sets
  `MTLModule.encoding`.
- `@main`, either as `[comment @main /]` inside a template or as a line in its
  documentation comment, marks the template as a main template (`isMain`).

## Imports and extends

```mtl
[module m('http://example.com')/]
[import a::b::common /]
[import util/]
[extends base/]
```

`[import qualified::module::name /]` may appear anywhere at the top level of a
module. `[extends x/]` is also accepted as a declaration, in addition to the
`extends` clause of the module header.

A qualified name `a::b::c` is mapped to the file `a/b/c.mtl`. The loader looks
first in the directory of the importing file and then in each configured search
path, in order. The result of `MTLParser.parse(_ url:)` has its imports and
parent module already linked. Cyclic imports and missing modules are reported as
errors (see `MTLModuleResolutionError`).

Imports are not transitive. Only public elements of an imported module (and of
its parent modules) are visible through an import.

## Templates

```mtl
[template public name(p : String, q : Integer) ? (guard) post (expr) overrides other]
body
[/template]
```

A template has:

- an optional visibility: `public` (the default), `protected` or `private`;
- a name;
- zero or more typed parameters, in parentheses;
- optional clauses, in any order: a guard, a post-processing expression and an
  `overrides` clause.

Parameter types may be simple names (`String`, `Integer`, `Animal`), qualified
names (`ecore::EClass`) or collection types with an element type
(`Sequence(String)`, `OrderedSet(ecore::EClass)`).

```mtl
[template t(c : ecore::EClass, names : Sequence(String), n : OrderedSet(ecore::EClass))]b[/template]
```

Inside every template, query and macro, the variable `self` is bound to the
first argument.

### Visibility

| Visibility | Visible to |
| --- | --- |
| `public` | the module, modules extending it, and modules importing it |
| `protected` | the module and modules extending it |
| `private` | the module only |

### Guards

A guard is written `? (condition)` or `guard (condition)`. When the condition is
false the template produces no output. A template may have only one guard;
declaring a second one is a syntax error.

```mtl
[template main(x : Integer) ? (x > 1)]big[/template]
[template main(x : Integer) guard (x > 1)]big[/template]
```

### Post-processing

`post (expr)` is evaluated after the body, with `self` bound to the generated
text; its result replaces the text.

```mtl
[template main() post (self + '!')]hi[/template]
```

When the expression yields a Boolean, it acts as a post-condition instead of
transforming the text. Evaluating text services such as `trim()` depends on the
swift-aql release (see the limits below).

### Overrides

`overrides name` (or `overrides module::name`) records that the template
overrides a template of an extended module.

```mtl
[template public t(x : String) overrides base::t]b[/template]
```

Overriding is resolved dynamically: see
[Invocations and resolution order](#invocations-and-resolution-order).

### Overloading

Templates, and likewise queries, may share a name when their parameter types
differ. Declaring two elements of the same name with identical parameter types
is an error.

```mtl
[template describe(x : Integer)]integer[/template]
[template describe(x : String)]string[/template]
[template describe(x : Animal)]animal[/template]
[template describe(x : Dog)]dog[/template]
```

The overload with the smallest total type distance is chosen (see below).

### Main templates

`MTLGenerator.generate(mainTemplate:arguments:models:)` looks the named template
up in the module and its parents. Overloads are told apart by the number of
arguments.

## Queries

A query is a side-effect free expression with a return type.

```mtl
[query getVersion() : String = '1.0.0'/]
[query add(a : Integer, b : Integer) : Integer = a + b/]
[query private secret(x : String) : String = x/]
[query items() : Sequence(Integer) = Sequence{1, 2, 3, 4}/]
```

Visibility is optional and defaults to `public`. A query may span several lines.

## Macros

A macro is a template-like unit that can receive a block of text. A parameter of
type `Body` receives the text between the opening and closing tags of the call.
Macros have no visibility.

```mtl
[macro wrap(tag : String, content : Body)]<[tag/]>[content/]</[tag/]>[/macro]

[template main()][wrap('b')]bold[/wrap][/template]
```

A macro without a `Body` parameter is called like any other element:

```mtl
[macro hello(name : String)]Hello [name/][/macro]
```

The body text is generated in the scope of the caller and bound to the `Body`
parameter. The body argument is not written in the call: `[wrap('b')]...[/wrap]`
passes only the `tag` argument explicitly.

## Statements

The body of a template, macro, or any block is a mixture of literal text and the
following tags.

### Text

Anything that is not a tag is emitted literally.

### Expression

`[expression/]` evaluates the expression and writes its string form. A
collection result is written as the concatenation of its elements.

```mtl
[5 + 3/] [name/] [self.shout('?')/] [min(3, 2)/]
```

### If

```mtl
[if (n = 1)]
one
[elseif (n = 2)]
two
[else]
many
[/if]
```

`elseif` and `else` are optional; `elseif` may repeat.

### For

```mtl
[for (x : T | collection) separator(', ') before('(') after(')')]
[x/]
[/for]
```

The accepted forms are:

| Form | Meaning |
| --- | --- |
| `[for (x : T \| coll)]` | typed iterator |
| `[for (x \| coll)]` | untyped iterator |
| `[for (x : T in coll)]`, `[for (x in coll)]` | older `in` form |
| `[for (coll)]` | no binding, the iterator is `self` |

The clauses `separator(...)`, `before(...)` and `after(...)` may appear in any
order. The separator is written between iterations. `before` and `after` are
written only when the collection is not empty.

Inside the body, `i` is a one-based counter of the current iteration. A loop
variable named `i` shadows it.

```mtl
[for (x | Sequence{'a', 'b', 'c'}) separator(',')][i/]:[x/][/for]
```

### Let

```mtl
[let x = 1, y = 2][x/] [y/][/let]
[let count : Integer = 42][count/][/let]
```

Several bindings may be separated by commas; a binding may carry a type.

### File

```mtl
[file ('greeting.txt', 'overwrite', 'UTF-8')]
Hello.
[/file]
```

The arguments are the file name (an expression), the mode and, optionally, the
charset. The mode is one of:

| Mode | Spelling |
| --- | --- |
| overwrite (the default) | `false`, `'overwrite'`, `overwrite` |
| append | `true`, `'append'`, `append` |
| create | `'create'`, `create` |

Any other expression is evaluated when the file is opened and interpreted in the
same way (for example `1 > 0`). The charset is applied when the file is written (see "Charsets" below).

Options may follow the charset, each as a string literal `'key=value'`:

```mtl
[file ('plugin.xml', 'overwrite', 'UTF-8', 'merge=false')]
```

`merge=false` stops the module's `[merge]` declaration from applying to this
file (`merge=true` is the default). `layout=false` stops layout conversion for
the file (`layout=true` is the default). Unknown keys are syntax errors.

In `create` mode an existing file is left untouched: no error is raised, the
body is not evaluated (so it produces no output and its `[collect]` and nested
`[file]` blocks have no effect), and nothing is written. A missing file is
written normally.

#### Charsets

The charset names are matched ignoring case, hyphens and underscores:
`UTF-8` (the default), `UTF-16` (big-endian with a byte order mark), `UTF-16BE`,
`UTF-16LE`, `ISO-8859-1` (also `Latin-1`) and `US-ASCII`. Bytes are written in
that charset, and existing files are read in it when appending or merging. An
unsupported charset name, or a character that the charset cannot represent, is
an `MTLExecutionError.fileError` naming the file (and the character); nothing is
written. Templates that target formats with escapes (such as Java properties
files) should escape such characters themselves.

### Protected

```mtl
[protected ('custom-methods') startTagPrefix('// ') endTagPrefix('// ')]
    // Add your code here.
[/protected]
```

A protected area is a region whose content is meant to be preserved by hand
edits. The identifier is required. The comment prefixes are given either
positionally, `[protected ('id', '#', '#')]` (start prefix, then end prefix), or
with the clauses `startTagPrefix(...)` and `endTagPrefix(...)`. The markers
written around the body are `START PROTECTED REGION id` and
`END PROTECTED REGION id`, each preceded by the configured prefix. There are no
default prefixes.

With `startTagPrefix('// ')` and `endTagPrefix('// ')` the generated markers
read `// START PROTECTED REGION custom-methods` and
`// END PROTECTED REGION custom-methods`.

## Invocations and resolution order

An invocation is written `[name(args)/]` and may be used as a statement or inside
any expression. The elements it can call are templates, queries and macros.

Forms:

```mtl
[name(a, b)/]            plain call
[x.name(a)/]             receiver style, the receiver is the first argument
[self.name()/]           receiver style on self
[min(3, 2)/]             standalone call of a library function
[Sequence{'a', 'b'}.item()/]  template applied to each element of a collection
[wrap('b')]body[/wrap]   macro call with a body
```

When a template is called on a collection (`[coll.tmpl()/]`), it runs once per
element and the texts are concatenated.

`name(args)` is resolved in this order:

1. elements declared in the current module, including private ones;
2. public and protected elements of the modules it extends. When the running
   module is a more derived module that overrides an element, the most specific
   override is called (dynamic dispatch);
3. public elements of imported modules and of their parent modules (protected
   and private elements are never visible through an import);
4. the swift-aql library (for example `min`, `max`, `abs` and `toString`).

Among the applicable overloads the one with the smallest total type distance
wins. An exact metaclass match costs 0, each step up the supertype chain costs
1, and `OclAny` or a null argument costs a large amount. Ties go to the most
derived module.

```mtl
[template main(x : OclAny)][describe(x)/][/template]
```

A module element with the same name as a library function takes precedence over
the library function.

## Expressions and operators

### Literals

- integers (`42`) and reals (`3.14`);
- strings in single quotes (`'text'`);
- `true`, `false` and `null`;
- collection literals `Sequence{1, 2}`, `OrderedSet{1, 2}`, `Set{'a'}` and
  `Bag{'a'}`; `Sequence{}` is the empty sequence.

### Names and navigation

- variables by name (`x`, `self`);
- navigation `a.b` and calls `a.b(x)`;
- qualified names `pkg::Type` and `pkg::Enum::literal`, kept as written.

### Operators

From loosest to tightest binding:

| Level | Operators | Notes |
| --- | --- | --- |
| 1 | `implies` | right associative |
| 2 | `or`, `xor` | left associative |
| 3 | `and` | |
| 4 | `=`, `<>`, `<`, `>`, `<=`, `>=` | comparison |
| 5 | `+`, `-` | |
| 6 | `*`, `/`, `mod`, `div` | `div` is parsed only, see the limits |
| 7 | unary `not`, unary `-` | |
| 8 | `.`, `->`, calls | |

The precedence of `implies` and the associativity of `implies` are tested; the
ordering of the other levels follows the usual OCL convention.

### Conditional and let expressions

```mtl
[if n > 1 then 'many' else 'one' endif/]
[let x = 1, y = 2 in x + y/]
```

### Type operations

`oclIsKindOf`, `oclIsTypeOf`, `oclAsType` and `oclIsUndefined` take effect on the
receiver. The bare form applies to `self`.

```mtl
[e.oclIsKindOf(AndExpression)/]
[x.oclIsUndefined()/]
```

## Collection operations

`->name(args)` is accepted for any name. The following build collection
expressions: `select`, `reject`, `collect`, `any`, `exists`, `forAll`, `indexOf`,
`size`, `isEmpty`, `notEmpty`, `first` and `last`. All other names build a call
with the collection as the source.

```mtl
[items->select(x : Integer | x > 1)->size()/]
[Sequence{1, 2}->exists(x | x = 2)/]
[Sequence{3, 1, 2}->first()/]
[Sequence{'a', 'bb'}->select(size() > 1)->size()/]
```

An iterator body may name its variable (`x | body` or `x : T | body`) or omit it.
Without an iterator variable, `self` is the implicit iterator and the implicit
receiver, so `->select(oclIsKindOf(EClass))` tests each element.

Which names can be evaluated depends on the swift-aql release. Parsing does not.

## Escapes

Inside a string literal:

| Written | Meaning |
| --- | --- |
| `''` | a single quote |
| `\'` | a single quote |
| `\\` | a backslash |
| `\n`, `\t`, `\r` | line feed, tab, carriage return |

Because `[` and `]` delimit tags, literal brackets in the output are written as
string expressions:

```mtl
[template main()]['['/]x[']'/] and ['[' + ']'/][/template]
```

This generates `[x]` followed by ` and ` and `[]`.

## Whitespace rules

The rule is the one of MOFM2T:

- A line that contains only block tags (template, macro, for, if, elseif, else,
  let, file, protected, macro calls with a body, their closing tags and
  comments) and white space produces no output. Its leading white space and its
  line break are dropped.
- A line that contains text or an expression tag keeps its line break.
- Text is otherwise emitted literally. Block bodies are not re-indented.
- A multi-line result of an expression (for example from a template call)
  inherits the leading white space of the line on which the expression starts.
- Both LF and CRLF line endings are accepted.

```mtl
[template main(n : Integer)]
[for (x | Sequence{'a', 'b'})]
[x/]
[/for]
[/template]
```

generates the two lines `a` and `b`, with no blank lines from the tag lines.

## Grammar summary

This is a summary, not a formal grammar.

```text
module      ::= '[' 'module' name '(' uri {',' uri} ')' ['extends' qname] ['/'] ']'
                { import | extends | comment | layout | template | query | macro }
import      ::= '[' 'import' qname ['/'] ']'
layout      ::= '[' 'layout' '(' string {',' string} ')' ['/'] ']'   (each string is key=value)
extends     ::= '[' 'extends' qname ['/'] ']'
template    ::= '[' 'template' [visibility] name '(' [params] ')'
                { '?' '(' expr ')' | 'guard' '(' expr ')'
                | 'post' '(' expr ')' | 'overrides' qname } ']'
                body '[/template]'
query       ::= '[' 'query' [visibility] name '(' [params] ')' ':' type '=' expr ['/'] ']'
macro       ::= '[' 'macro' name '(' [params] ')' ']' body '[/macro]'
visibility  ::= 'public' | 'protected' | 'private'
params      ::= param {',' param}
param       ::= name ':' type
type        ::= qname | collectionKind '(' type ')'
body        ::= { text | statement }
statement   ::= '[' expr '/]'
              | '[' 'if' '(' expr ')' ']' body { '[' 'elseif' '(' expr ')' ']' body }
                [ '[else]' body ] '[/if]'
              | '[' 'for' '(' forBinding ')' { forClause } ']' body '[/for]'
              | '[' 'let' binding {',' binding} ']' body '[/let]'
              | '[' 'file' '(' expr ',' mode [',' expr] ')' ']' body '[/file]'
              | '[' 'protected' '(' expr [',' expr ',' expr] ')'
                    { 'startTagPrefix' '(' expr ')' | 'endTagPrefix' '(' expr ')' } ']'
                body '[/protected]'
              | '[' name '(' [args] ')' ']' body '[/' name ']'
forBinding  ::= name [':' type] ('|' | 'in') expr | expr
forClause   ::= 'separator' '(' expr ')' | 'before' '(' expr ')' | 'after' '(' expr ')'
binding     ::= name [':' type] '=' expr
```

## Differences from Acceleo and current limits

swift-mtl follows the OMG MOFM2T text and the Acceleo 3 syntax. The differences
and limits below are known.

Expression services:

- The released swift-aql library lacks most of the Acceleo standard library.
  String services (`toUpperFirst`, `replaceAll`, `tokenize` and others) and
  collection services (`sortedBy`, `asSet`, `including`, `sum`, `reverse`, `at`
  and others) are parsed but are not evaluated yet.
- `div` is parsed, but swift-aql cannot evaluate it yet.
- `toString` of a number currently prints `Optional(7)`.
- `trim()` does not remove line breaks.
- `String + Integer` is a type error.
- Method-style calls on collections, such as `coll.size()`, do not evaluate.
  Use `coll->size()`.
- Evaluation of all of the above is expected with the next swift-aql release.

Types:

- A qualified type name in `oclIsKindOf(ecore::EClass)` is passed as the full
  string. The released swift-aql compares unqualified names, and only for dynamic
  objects.

Protected areas and files:

- Scanning existing files for protected areas, deferred blocks, tagged-block
  merging and post-processors are not part of this package yet.
- The protected area markers are `START PROTECTED REGION id` and
  `END PROTECTED REGION id` preceded by the configured prefixes. No default
  prefixes are derived from the file extension.
- Only the charsets listed under "Charsets" are supported.

Modules:

- Macros have no visibility.
- Imports are not transitive.
- Protected elements are visible only to extending modules.
- Text is emitted literally, as in Acceleo 3: block bodies are not re-indented
  automatically.
