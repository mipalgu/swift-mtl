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

Expressions inside tags are [swift-aql](https://mipalgu.github.io/swift-aql/) abstract syntax
trees built by ``MTLParser`` and evaluated against models loaded with
[swift-ecore](https://mipalgu.github.io/swift-ecore/). The package provides a single library
product, `MTL`. It has no executable: the `swift-mtl` command-line tool is part of the
separate [swift-modelling](https://mipalgu.github.io/swift-modelling/documentation/swift_mtl/index.html) package.

The workflow has three steps. ``MTLParser`` turns template files or source text into an
``MTLModule``, resolving imports and `extends` relationships along the way.
``MTLGenerator`` runs a main template of that module against input models. A
``MTLGenerationStrategy`` decides where the generated text goes: ``MTLInMemoryStrategy``
collects it in memory and ``MTLFileSystemStrategy`` writes it to disk.

Beyond the core language, the package supports deferred `[collect]` and `[emit]` blocks,
`[merge]` regeneration merging, `[layout]` code style conversion, protected areas that are
preserved on regeneration, generator options and file post-processors, global variables and
named parameters, and services for editors and other hosts. See <doc:UnderstandingMTL> for
details.

## Related Documentation

- [swift-mtl command-line tool](https://mipalgu.github.io/swift-modelling/documentation/swift_mtl/index.html) - the `swift-mtl` tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/)

### Tutorials

- [Hello World Template](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/mtl-01-hello-world/index.html)
- [Expressions and Variables](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/mtl-02-expressions-variables/index.html)
- [Control Flow](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/mtl-03-control-flow/index.html)
- [File Blocks](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/mtl-04-file-blocks/index.html)
- [Queries and Macros](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/mtl-05-queries-macros/index.html)
- [Code Generation from Models](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/mtl-06-code-from-models/index.html)
- [Protected Areas](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/mtl-07-protected-areas/index.html)
- [Complete Code Generator](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/mtl-08-complete-generator/index.html)
- [UML to Swift Code Generation](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/mtl-advanced-01-uml2swift/index.html)
- [AQL in MTL Templates](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/aql-04-aql-in-mtl/index.html)
- [Reusing Modules with Model Typing](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/typing-01-check-compat/index.html)
- [Multi-Level Modelling with Potency](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/multilevel-01-deep-modelling/index.html)
- [All tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)

### Related Packages

- [swift-aql](https://mipalgu.github.io/swift-aql/) - the query language of template expressions ([AQL](https://mipalgu.github.io/swift-aql/documentation/aql/))
- [swift-ecore](https://mipalgu.github.io/swift-ecore/) - the models that templates read ([ECore](https://mipalgu.github.io/swift-ecore/documentation/ecore/))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/) - Epsilon languages, including EGL text generation ([EGL](https://mipalgu.github.io/swift-epsilon/documentation/egl/))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - command-line tools, code generators and tutorials

### Standards

- [OMG MOFM2T](https://www.omg.org/spec/MOFM2T/)
- [Acceleo](https://eclipse.dev/acceleo/)

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingMTL>
- <doc:Compatibility>

### Options

- ``MTLOptions``
- ``MTLBlockLineBreaks``
- ``MTLCollectionParameters``
- ``MTLLetTypeMismatches``
- ``MTLObjectText``

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

### Layout Conversion

- ``MTLLayoutConfiguration``
- ``MTLOpenerPlacement``
- ``MTLLayoutPostProcessor``
- ``MTLLayoutOptionKeys``

### Protected Areas

- ``MTLProtectedAreaManager``

### Parameters, Resources and Query Helpers

- ``MTLParameterServices``
- ``MTLParameterServiceName``
- ``MTLResourceServices``
- ``MTLResourceServiceName``
- ``MTLQueryHelpers``
- ``MTLQueryHelper``
- ``MTLQueryServices``

### Errors

- ``MTLParameterError``
- ``MTLResourceServicesError``
- ``MTLParseError``
- ``MTLExecutionError``
- ``MTLResourceError``
- ``MTLModuleResolutionError``
