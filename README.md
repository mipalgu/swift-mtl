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
    .package(url: "https://github.com/mipalgu/swift-mtl", from: "0.7.0"),
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

- The DocC catalogue in [Sources/MTL/MTL.docc](Sources/MTL/MTL.docc) covers getting started, the language and its options, generation features such as deferred blocks, regeneration merging and layout conversion, services for hosts and editors, the remaining limits, and compatibility with version 0.6.
- [SYNTAX.md](SYNTAX.md) is the syntax reference.
- [Examples](Examples/README.md) holds example templates.

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
