# swift-mtl

The [swift-mtl](https://github.com/mipalgu/swift-mtl) package provides a pure Swift
library (product `MTL`) for model-to-text transformation with the
[OMG MOFM2T](https://www.omg.org/spec/MOFM2T/) / [Acceleo](https://eclipse.dev/acceleo/)
template language. It contains no executable: the `swift-mtl` command-line tool is part of
[swift-modelling](https://mipalgu.github.io/swift-modelling/) and is described in
[swift-mtl](https://mipalgu.github.io/swift-modelling/documentation/swift_mtl/index.html).

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-mtl.git", branch: "main"),
]
```

## Requirements

- Swift 6.0 or later
- macOS 15.0+ or Linux

## References

- [OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/)
- [Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)

## Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/) - EMF/Ecore metamodelling, OCL, generator models and multi-level modelling ([GitHub](https://github.com/mipalgu/swift-ecore))
- [swift-aql](https://mipalgu.github.io/swift-aql/) - AQL model queries ([GitHub](https://github.com/mipalgu/swift-aql))
- [swift-atl](https://mipalgu.github.io/swift-atl/) - ATL model transformations ([GitHub](https://github.com/mipalgu/swift-atl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/) - Epsilon model management languages (EOL, EVL, ETL and EGL) ([GitHub](https://github.com/mipalgu/swift-epsilon))
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations ([GitHub](https://github.com/mipalgu/swift-xtend))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Documentation

The package generates text from models. For details, see
[Getting Started](documentation/mtl/gettingstarted),
[Understanding MTL](documentation/mtl/understandingmtl) and
[Compatibility](documentation/mtl/compatibility). The [MTL](documentation/mtl/) module page
lists the whole API. The template syntax is described in the
[syntax reference](https://github.com/mipalgu/swift-mtl/blob/main/SYNTAX.md), and the
[examples](https://github.com/mipalgu/swift-mtl/tree/main/Examples) show complete templates.

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
