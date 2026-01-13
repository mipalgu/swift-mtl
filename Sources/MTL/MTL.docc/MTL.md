# ``MTL``

@Metadata {
    @DisplayName("MTL")
}

A pure Swift implementation of the [OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/) standard for template-based code generation.

## Overview

MTL provides a template-based approach to code generation from models. Define templates
with embedded queries that navigate your model, and MTL generates output files with
the evaluated content.

This implementation follows the [OMG MOFM2T specification](https://www.omg.org/spec/MOFM2T/)
and is compatible with [Eclipse Acceleo](https://eclipse.dev/acceleo/), whilst providing
a modern Swift API for integration with the ECore metamodelling framework.

### Key Features

- **Template-based generation**: Define output structure with text and queries
- **AQL integration**: Use Acceleo Query Language for model navigation
- **File blocks**: Control which files are generated and where
- **Protected regions**: Preserve user modifications across regeneration
- **Iteration**: Loop over collections with for blocks
- **Conditionals**: Include content based on conditions

### Quick Example

```swift
import MTL
import ECore

// Parse the template module
let parser = MTLParser()
let module = try await parser.parse(URL(fileURLWithPath: "SwiftGenerator.mtl"))

// Configure output
let strategy = MTLFileGenerationStrategy(
    outputDirectory: URL(fileURLWithPath: "./Sources/Generated")
)

// Create context and register model
let context = MTLExecutionContext(module: module, generationStrategy: strategy)
try await context.registerModel(modelResource, as: "model")

// Execute
let executor = MTLExecutor(context: context)
try await executor.execute()
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingMTL>

### Execution

- ``MTLExecutor``
- ``MTLExecutionContext``
- ``MTLGenerationStrategy``
- ``MTLFileGenerationStrategy``
- ``MTLStringGenerationStrategy``

### Module Structure

- ``MTLModule``
- ``MTLTemplate``
- ``MTLQuery``

### Template Elements

- ``MTLBlock``
- ``MTLFileBlock``
- ``MTLForBlock``
- ``MTLIfBlock``
- ``MTLLetBlock``
- ``MTLProtectedAreaBlock``
- ``MTLTextBlock``
- ``MTLExpressionBlock``

### Protected Regions

- ``MTLProtectedAreaManager``

### Parsing

- ``MTLParser``
- ``MTLLexer``
- ``MTLSyntaxParser``

### Errors

- ``MTLExecutionError``
- ``MTLParseError``

## See Also

- [OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/)
- [Eclipse Acceleo](https://eclipse.dev/acceleo/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
