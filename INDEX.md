# Swift MTL - Model-to-Text Language

The [swift-mtl](https://github.com/mipalgu/swift-mtl) package provides a pure Swift
implementation of the [OMG MOF Model-to-Text (MOFM2T)](https://www.omg.org/spec/MOFM2T/)
standard, also known as [Acceleo](https://eclipse.dev/acceleo/), for code generation from models.

## Overview

Swift MTL enables template-based code generation from ECore models, providing:

- **MTL language support**: Parse and execute MTL template modules
- **Templates**: Define output structure with embedded model queries
- **Queries**: Navigate and filter model elements using AQL
- **File blocks**: Control output file generation
- **Protected regions**: Preserve user code across regeneration
- **For loops**: Iterate over model collections

## Installation

Add swift-mtl as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-mtl.git", branch: "main"),
]
```

Then add the product dependency to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "MTL", package: "swift-mtl"),
    ]
)
```

## Quick Start

```swift
import MTL
import ECore

// Parse the MTL template
let parser = MTLParser()
let module = try await parser.parse(URL(fileURLWithPath: "Generator.mtl"))

// Load the model
let xmiParser = XMIParser()
let modelResource = try await xmiParser.parse(URL(fileURLWithPath: "model.xmi"))

// Create execution context
let strategy = MTLFileGenerationStrategy(outputDirectory: URL(fileURLWithPath: "./generated"))
let context = MTLExecutionContext(module: module, generationStrategy: strategy)

// Register the model
try await context.registerModel(modelResource, as: "model")

// Execute the template
let executor = MTLExecutor(context: context)
try await executor.execute()
```

## MTL Syntax Example

```mtl
[module generate('http://example.com/mymetamodel')]

[template public generateClass(c : Class)]
[file (c.name + '.swift', false, 'UTF-8')]
// Generated from [c.name/]
class [c.name/] {
    [for (attr : Attribute | c.attributes)]
    var [attr.name/]: [attr.type.name/]
    [/for]

    [protected ('init')]
    // Add custom initialisation here
    [/protected]
}
[/file]
[/template]
```

## Documentation

Detailed documentation is available in the generated DocC documentation:

- **Getting Started**: Installation and first template
- **Understanding MTL**: Templates, queries, and file blocks
- **API Reference**: Complete API documentation

## Requirements

- macOS 15.0+
- Swift 6.0+
- swift-ecore
- swift-aql

## References

This implementation is based on the following standards and technologies:

- [OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/) - The model-to-text standard
- [Eclipse Acceleo](https://eclipse.dev/acceleo/) - The reference MTL implementation
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - Expression language for queries
- [Eclipse EMF (Modeling Framework)](https://eclipse.dev/emf/) - The metamodelling foundation

## Related Packages

- [swift-ecore](https://github.com/mipalgu/swift-ecore) - EMF/Ecore metamodelling
- [swift-atl](https://github.com/mipalgu/swift-atl) - ATL model transformations
- [swift-aql](https://github.com/mipalgu/swift-aql) - AQL model queries
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit
