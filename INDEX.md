# Swift MTL

A pure Swift implementation of the [OMG MOFM2T](https://www.omg.org/spec/MOFM2T/) standard for template-based code generation.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-mtl.git", branch: "main"),
]
```

## Requirements

- Swift 6.0 or later
- macOS 15.0+

## References

- [OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/)
- [Eclipse Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)

## Related Packages

- [swift-ecore](https://github.com/mipalgu/swift-ecore) - EMF/Ecore metamodelling
- [swift-atl](https://github.com/mipalgu/swift-atl) - ATL model transformations
- [swift-aql](https://github.com/mipalgu/swift-aql) - AQL model queries
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit

## Documentation

The package provides template-based model-to-text transformation capabilities.
For details, see [Getting Started](https://mipalgu.github.io/swift-mtl/documentation/mtl/gettingstarted) and [Understanding MTL](https://mipalgu.github.io/swift-mtl/documentation/mtl/understandingmtl).
