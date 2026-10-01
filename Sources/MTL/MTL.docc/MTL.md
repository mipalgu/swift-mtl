# ``MTL``

Parse OMG MOFM2T (Acceleo style) templates and generate text from models.

## Overview

MTL is a Swift implementation of the [OMG MOFM2T](https://www.omg.org/spec/MOFM2T/)
model-to-text language, using the Acceleo dialect of the syntax. A template module is
plain text with bracketed tags. Tags navigate a model, loop, branch and call other
templates, and everything between the tags is copied to the output.

```mtl
[module greetings('http://www.eclipse.org/emf/2002/Ecore')/]
[template public main(name : String)]
Hello, [name/]!
[/template]
```

Expressions inside tags are swift-aql abstract syntax trees built by ``MTLParser`` and
evaluated against models loaded with swift-ecore. The package provides a single library
product, `MTL`. It has no executable: the `swift-mtl` command-line tool is part of the
separate swift-modelling package.

The workflow has three steps. ``MTLParser`` turns template files or source text into an
``MTLModule``, resolving imports and `extends` relationships along the way.
``MTLGenerator`` runs a main template of that module against input models. A
``MTLGenerationStrategy`` decides where the generated text goes: ``MTLInMemoryStrategy``
collects it in memory and ``MTLFileSystemStrategy`` writes it to disk.

### Current limits

The swift-aql release that MTL builds on lacks most of the Acceleo standard library, such
as the string services `toUpperFirst` and `replaceAll` and the collection services
`sortedBy`, `asSet` and `sum`. These expressions parse, but evaluation needs a later
swift-aql release. See <doc:UnderstandingMTL> for details.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingMTL>

### Parsing and Modules

- ``MTLParser``
- ``MTLModule``
- ``MTLTemplate``
- ``MTLQuery``
- ``MTLMacro``
- ``MTLVisibility``
- ``MTLBlock``
- ``MTLVariable``
- ``MTLBinding``
- ``MTLSyntax``

### Imports and Search Paths

- ``MTLModuleResolver``
- ``MTLModuleLoader``
- ``MTLModuleResolutionError``

### Generating Text

- ``MTLGenerator``
- ``MTLGenerationStatistics``
- ``MTLGenerationStrategy``
- ``MTLInMemoryStrategy``
- ``MTLFileSystemStrategy``
- ``MTLExecutionContext``
- ``MTLWriter``
- ``MTLIndentation``

### Statements

- ``MTLStatement``
- ``MTLTextStatement``
- ``MTLExpressionStatement``
- ``MTLNewLineStatement``
- ``MTLComment``
- ``MTLForStatement``
- ``MTLIfStatement``
- ``MTLLetStatement``
- ``MTLFileStatement``
- ``MTLOpenMode``
- ``MTLProtectedArea``
- ``MTLMacroInvocation``
- ``MTLTrace``
- ``MTLTraceLink``

### Expressions

- ``MTLExpression``
- ``MTLInvocationExpression``
- ``MTLLambdaExpression``
- ``MTLCollectionLiteralExpression``

### Protected Areas

- ``MTLProtectedAreaManager``

### Errors

- ``MTLParseError``
- ``MTLExecutionError``
- ``MTLResourceError``
- ``MTLModuleResolutionError``
