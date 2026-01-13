# Getting Started with MTL

Learn how to add MTL to your project and create your first code generator.

## Overview

This guide walks you through adding MTL to your Swift project and demonstrates
how to write templates that generate code from models.

## Adding MTL to Your Project

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

## Writing an MTL Template

MTL templates are written in `.mtl` files. Here's a simple example that generates
Swift classes from a model:

```mtl
[comment encoding = UTF-8 /]
[module generateSwift('http://example.com/mymetamodel')]

[template public generateClass(c : Class)]
[file (c.name.concat('.swift'), false, 'UTF-8')]
//
// [c.name/].swift
// Generated - do not edit
//

import Foundation

class [c.name/] {
    [for (attr : Attribute | c.attributes)]
    var [attr.name/]: [attr.type.swiftType()/]
    [/for]

    init() {
        [for (attr : Attribute | c.attributes)]
        self.[attr.name/] = [attr.defaultValue()/]
        [/for]
    }
}
[/file]
[/template]

[query public swiftType(t : Type) : String =
    if t.name = 'String' then 'String'
    else if t.name = 'Integer' then 'Int'
    else if t.name = 'Boolean' then 'Bool'
    else 'Any'
    endif endif endif
/]

[query public defaultValue(a : Attribute) : String =
    if a.type.name = 'String' then '""'
    else if a.type.name = 'Integer' then '0'
    else if a.type.name = 'Boolean' then 'false'
    else 'nil'
    endif endif endif
/]
```

### Module Declaration

The `[module]` tag declares the template module and its required metamodel:

```mtl
[module generateSwift('http://example.com/mymetamodel')]
```

### Templates

Templates are the entry points for generation. They take model elements as parameters:

```mtl
[template public generateClass(c : Class)]
...
[/template]
```

### File Blocks

File blocks create output files:

```mtl
[file (filename, appendMode, encoding)]
... content ...
[/file]
```

## Loading and Executing Templates

### Parse the Template

```swift
import MTL

let parser = MTLParser()
let module = try await parser.parse(URL(fileURLWithPath: "SwiftGenerator.mtl"))

print("Loaded module: \(module.name)")
print("Templates: \(module.templates.count)")
```

### Load Your Model

```swift
import ECore

let xmiParser = XMIParser()
let modelResource = try await xmiParser.parse(URL(fileURLWithPath: "my-model.xmi"))
```

### Configure the Generation Strategy

MTL supports different output strategies:

```swift
// Generate to files
let fileStrategy = MTLFileGenerationStrategy(
    outputDirectory: URL(fileURLWithPath: "./generated")
)

// Or capture to strings (useful for testing)
let stringStrategy = MTLStringGenerationStrategy()
```

### Create the Execution Context

```swift
let context = MTLExecutionContext(
    module: module,
    generationStrategy: fileStrategy
)

// Register your model
try await context.registerModel(modelResource, as: "model")
```

### Execute the Template

```swift
let executor = MTLExecutor(context: context)
try await executor.execute()

// Check what was generated
print("Files generated: \(fileStrategy.generatedFiles.count)")
```

## Using Protected Regions

Protected regions preserve user code across regeneration:

```mtl
[template public generateClass(c : Class)]
[file (c.name.concat('.swift'), false, 'UTF-8')]
class [c.name/] {
    // Generated properties
    [for (attr : Attribute | c.attributes)]
    var [attr.name/]: [attr.type.swiftType()/]
    [/for]

    [protected ('custom-properties')]
    // Add your custom properties here
    [/protected]

    init() {
        [protected ('custom-init')]
        // Add custom initialisation here
        [/protected]
    }
}
[/file]
[/template]
```

When the template runs again, content within `[protected]...[/protected]` blocks
is preserved from the existing file.

### Scanning for Protected Regions

Before regenerating, scan existing files:

```swift
// Scan existing file for protected regions
try await context.scanFileForProtectedAreas("./generated/MyClass.swift")

// Now execute - protected content will be preserved
try await executor.execute()
```

## Using Queries

Queries are reusable expressions:

```mtl
[query public fullName(c : Class) : String =
    c.package.name.concat('.').concat(c.name)
/]

[query public abstractClasses(p : Package) : Sequence(Class) =
    p.classes->select(c | c.isAbstract)
/]
```

Use queries in templates:

```mtl
[template public generate(p : Package)]
Package: [p.fullName()/]
Abstract classes: [p.abstractClasses()->size()/]
[/template]
```

## Conditional Generation

Use `[if]` blocks for conditional content:

```mtl
[template public generateClass(c : Class)]
[if (c.isAbstract)]
abstract class [c.name/] {
[else]
class [c.name/] {
[/if]
    ...
}
[/template]
```

## Iteration

Use `[for]` blocks to iterate over collections:

```mtl
[for (attr : Attribute | c.attributes)]
var [attr.name/]: [attr.type.name/]
[/for]

[for (attr : Attribute | c.attributes) separator(', ')]
[attr.name/]
[/for]
```

The `separator` option adds text between iterations (but not after the last one).

## Next Steps

- <doc:UnderstandingMTL> - Deep dive into MTL concepts
- ``MTLTemplate`` - Template API reference
- ``MTLProtectedAreaManager`` - Protected region management
- ``MTLExecutionContext`` - Advanced execution control
