# swift-mtl

[![CI](https://github.com/mipalgu/swift-mtl/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-mtl/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-mtl/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-mtl/actions/workflows/documentation.yml)

A Swift library for model-to-text transformation with the OMG MOFM2T / Acceleo template language.

## Overview

swift-mtl parses MTL (Model-to-Text Language) modules and executes their templates to generate code, documentation, and other text from models. It provides a single library product, `MTL`. Expressions inside templates are [swift-aql](https://github.com/mipalgu/swift-aql) expressions, and models come from [swift-ecore](https://github.com/mipalgu/swift-ecore).

This package contains no executable. The `swift-mtl` command-line tool is provided by the separate [swift-modelling](https://github.com/mipalgu/swift-modelling) package.

## Features

- Parser for the Acceleo dialect of MTL: modules, `extends` and `import`, templates, queries, macros, `for`, `if`, `let`, `file` and `protected` blocks, and comments
- Template visibility, guards, post-expressions, `overrides`, and overloading by parameter types
- Module resolution through search paths or an in-memory module source
- Expressions evaluated by swift-aql with its standard library, plus services of your own through `AQLServiceProvider`
- Generation into memory or onto the file system, with protected areas preserved on regeneration
- Deferred `[collect]` and `[emit]` blocks, `[merge]` regeneration merging, `[layout]` code style conversion and file post-processors
- Behaviour options (`MTLOptions`) that select the behaviour of this release or that of version 0.6
- Error-tolerant parsing, diagnostics and highlighting tokens for editors

## Requirements

- Swift 6.0 or later
- macOS 15 or later, or iOS 18 or later
- Linux, Windows and WebAssembly, which are built and tested in CI

## Installation

Add swift-mtl to the dependencies of your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-mtl", from: "0.8.0"),
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

## Building

```sh
swift build
```

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
import Foundation
import MTL

let module = try await MTLParser().parse(URL(fileURLWithPath: "hello.mtl"))

let strategy = MTLInMemoryStrategy()
let generator = MTLGenerator(module: module, generationStrategy: strategy, options: .standard)
try await generator.generate(mainTemplate: "main", arguments: ["World"], models: [:])

let files = await strategy.getGeneratedFiles()
print(files["stdout"] ?? "")   // the main output is stored under "stdout"
```

Templates that write `[file (...)]` blocks add one entry per file to the dictionary. To write files to disk, use `MTLFileSystemStrategy(basePath:)` instead. Pass `options: .legacy` to keep the behaviour of version 0.6.

## Documentation

The documentation is published at <https://mipalgu.github.io/swift-mtl/>.

- The DocC catalogue in [Sources/MTL/MTL.docc](Sources/MTL/MTL.docc) covers getting started, the language and its options, generation features such as deferred blocks, regeneration merging and layout conversion, services for hosts and editors, the remaining limits, and compatibility with version 0.6. The [MTL](https://mipalgu.github.io/swift-mtl/documentation/mtl/) module page lists the whole API.
- [SYNTAX.md](SYNTAX.md) is the syntax reference.
- [Examples](Examples/README.md) holds example templates.

The `swift-mtl` command-line tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/)
is described in [swift-mtl](https://mipalgu.github.io/swift-modelling/documentation/swift_mtl/index.html),
and the MTL tutorials introduce it step by step:

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

See all [tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html).

## Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/) - EMF/Ecore metamodelling, OCL, generator models and multi-level modelling ([GitHub](https://github.com/mipalgu/swift-ecore))
- [swift-aql](https://mipalgu.github.io/swift-aql/) - AQL model queries ([GitHub](https://github.com/mipalgu/swift-aql))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations ([GitHub](https://github.com/mipalgu/swift-atl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/) - Epsilon model management languages (EOL, EVL, ETL and EGL) ([GitHub](https://github.com/mipalgu/swift-epsilon))
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations ([GitHub](https://github.com/mipalgu/swift-xtend))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Licence

Copyright (c) 2025, 2026 Rene Hexel. Distributed under a BSD-style licence with an advertising clause, or alternatively under the GNU General Public License version 2 or later, at your option. See [LICENCE](LICENCE) for the full wording.

## References

- [OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/)
- [Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
