# swift-mtl

[![CI](https://github.com/mipalgu/swift-mtl/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-mtl/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-mtl/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-mtl/actions/workflows/documentation.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-mtl%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mipalgu/swift-mtl)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-mtl%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mipalgu/swift-mtl)

A Swift implementation of MTL (Model-to-Text Language) with a complete parser, runtime, and command-line tool.

## Overview

swift-mtl provides comprehensive support for model-to-text transformation using the MTL/Acceleo syntax. It enables parsing, validation, and execution of MTL templates to generate code, documentation, and other textual artifacts from models.

## Features

- **Complete MTL Parser** - Parse MTL templates from text files with full syntax support
- **MTL Runtime** - Execute templates with high performance using Swift's concurrent execution model
- **CLI Tool** - Generate, parse, and validate MTL templates from the command line
- **Model Support** - Load models from XMI and JSON formats
- **Expression Language** - Full AQL (Acceleo Query Language) integration for expressions
- **Advanced Features** - File blocks, protected areas, queries, macros, and more

## Installation

### Building from Source

```sh
git clone <repository-url>
cd swift-mtl
swift build --scratch-path /tmp/build-swift-mtl -c release
```

The executable will be built at `/tmp/build-swift-mtl/release/swift-mtl`.

### Adding to PATH (Optional)

```sh
# Add to your shell profile (~/.zshrc, ~/.bashrc, etc.)
export PATH="/tmp/build-swift-mtl/release:$PATH"
```

## Quick Start

### 1. Create an MTL Template

Create a file `hello.mtl`:

```mtl
[module HelloWorld('http://example.com')]

[template main()]
Hello, World!
This is a simple MTL template.
[/template]
```

### 2. Generate Output

```sh
swift-mtl generate hello.mtl --output generated/
```

This will create `generated/stdout` containing the generated text.

### 3. Validate Templates

```sh
swift-mtl validate hello.mtl
# Output: ✓ hello.mtl: Valid
```

## Usage

### Generate Command

Generate text from models using MTL templates.

```sh
swift-mtl generate TEMPLATE [options]
```

**Arguments:**
- `TEMPLATE` - Path to MTL template file (.mtl)

**Options:**
- `--model PATH` - Input model file (XMI or JSON, can be specified multiple times)
- `--output, -o PATH` - Output directory for generated files (default: ".")
- `--template, -t NAME` - Main template name to execute (auto-detect if not specified)
- `--verbose, -v` - Enable verbose output

**Examples:**

```sh
# Basic generation
swift-mtl generate template.mtl --output generated/

# With input models
swift-mtl generate template.mtl \
  --model input.xmi \
  --output generated/

# Multiple models
swift-mtl generate template.mtl \
  --model families.xmi \
  --model departments.xmi \
  --output generated/

# Specify main template
swift-mtl generate template.mtl \
  --model input.xmi \
  --template generateAll \
  --output generated/

# Verbose output
swift-mtl generate template.mtl \
  --model input.xmi \
  --output generated/ \
  --verbose
```

### Parse Command

Parse and display MTL template structure.

```sh
swift-mtl parse TEMPLATE... [options]
```

**Arguments:**
- `TEMPLATE...` - One or more MTL template files to parse

**Options:**
- `--detailed, -d` - Show detailed template information
- `--json, -j` - Output in JSON format
- `--verbose, -v` - Enable verbose output

**Examples:**

```sh
# Parse single template
swift-mtl parse template.mtl

# Parse multiple templates
swift-mtl parse template1.mtl template2.mtl

# Detailed output
swift-mtl parse template.mtl --detailed

# JSON output
swift-mtl parse template.mtl --json
```

### Validate Command

Validate MTL template syntax.

```sh
swift-mtl validate TEMPLATE... [options]
```

**Arguments:**
- `TEMPLATE...` - One or more MTL template files to validate

**Options:**
- `--verbose, -v` - Show detailed validation information

**Examples:**

```sh
# Validate single template
swift-mtl validate template.mtl

# Validate multiple templates
swift-mtl validate template1.mtl template2.mtl template3.mtl

# Verbose validation
swift-mtl validate template.mtl --verbose
```

## MTL Template Syntax

### Module Declaration

Every MTL file must start with a module declaration:

```mtl
[module ModuleName('http://metamodel/uri')]
```

### Templates

Templates define text generation logic:

```mtl
[template templateName(param : Type)]
Text content and [param/] expressions
[/template]
```

**Template Modifiers:**
- Visibility: `public` (default), `protected`, `private`
- Main template: `[template main() ? main()]`

### Expressions

```mtl
[variableName/]                    // Variable reference
[object.property/]                 // Navigation
[1 + 2 + 3/]                       // Arithmetic
[firstName + ' ' + lastName/]      // String concatenation
['literal string'/]                // String literal
```

### Control Flow

**If Statement:**
```mtl
[if (condition)]
  Text when true
[elseif (otherCondition)]
  Text when elseif true
[else]
  Text when false
[/if]
```

**For Loop:**
```mtl
[for (item in collection) separator(', ')]
  [item/]
[/for]
```

**Let Binding:**
```mtl
[let temp = expression]
  Use [temp/] here
[/let]
```

### File Blocks

Generate to specific files:

```mtl
[file ('filename.txt', 'overwrite', 'UTF-8')]
File content here
[/file]
```

**File Modes:**
- `overwrite` - Replace existing file
- `append` - Append to existing file
- `create` - Create only if doesn't exist

### Protected Areas

Preserve manually edited sections:

```mtl
[protected ('id', 'start-tag', 'end-tag')]
Default content
[/protected]
```

### Queries

Define reusable query functions:

```mtl
[query getName(obj : Type) : String = obj.name/]

[query fullName(first : String, last : String) : String =
  first + ' ' + last/]
```

### Macros

Define reusable text blocks with parameters:

```mtl
[macro wrapper(content : Body)]
<div>
  [content/]
</div>
[/macro]

// Usage:
[wrapper()]
  Inner content
[/wrapper]
```

## Library Usage

### Swift Package

Add swift-mtl as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/swift-mtl", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "MTL", package: "swift-mtl")
        ]
    )
]
```

### Programmatic Usage

```swift
import MTL
import Foundation

// Parse MTL template
let parser = MTLParser()
let templateURL = URL(fileURLWithPath: "template.mtl")
let module = try await parser.parse(templateURL)

// Create generator with output strategy
let outputDir = URL(fileURLWithPath: "generated")
let strategy = MTLFileSystemStrategy(basePath: outputDir.path)
let generator = MTLGenerator(module: module, generationStrategy: strategy)

// Execute generation
try await generator.generate(
    mainTemplate: "main",
    arguments: [],
    models: [:]
)

// Access statistics
print("Templates executed: \(generator.statistics.templatesExecuted)")
print("Execution time: \(generator.statistics.executionTime)s")
```

## Testing

Run the comprehensive test suite (169 tests):

```sh
cd swift-mtl
swift test --scratch-path /tmp/build-swift-mtl
```

### Custom Scratch Path

Override the scratch directory using the `SWIFT_MTL_SCRATCH_PATH` environment variable:

```sh
export SWIFT_MTL_SCRATCH_PATH=/custom/build/path
swift test --scratch-path /custom/build/path
```

See `Tests/MTLTests/README.md` for detailed test documentation.

## Project Structure

```
swift-mtl/
├── Sources/
│   ├── MTL/                    # MTL library
│   │   ├── MTLParser.swift     # Parser (lexer + syntax parser)
│   │   ├── MTLModule.swift     # AST: Module, Template, Query, Macro
│   │   ├── MTLStatement.swift  # AST: Statements
│   │   ├── MTLGenerator.swift  # Template execution engine
│   │   └── MTLGenerationStrategy.swift  # Output strategies
│   └── swift-mtl/              # CLI executable
│       ├── SwiftMTL.swift      # Main entry point
│       └── Commands/           # Command implementations
│           ├── GenerateCommand.swift
│           ├── ParseCommand.swift
│           └── ValidateCommand.swift
├── Tests/
│   └── MTLTests/               # Test suite (169 tests)
│       ├── MTLParserTests.swift
│       ├── CLIIntegrationTests.swift
│       ├── TestHelpers.swift
│       └── Resources/templates/  # Test templates
└── Package.swift
```

## Performance

The swift-mtl runtime provides excellent performance:
- Fast parsing with hand-written recursive descent parser
- Efficient template execution using Swift's concurrency model
- Minimal overhead for expression evaluation
- Typical generation time: 1-5ms for simple templates

## Compatibility

- **Swift Version**: 6.0+
- **Platform**: macOS 15.0+
- **MTL Syntax**: Compatible with Acceleo MTL/OCL standard

## Dependencies

- [swift-ecore](https://github.com/mipalgu/swift-ecore) - EMF/Ecore implementation for model loading
- [swift-aql](https://github.com/your-org/swift-aql) - AQL expression evaluation
- [swift-collections](https://github.com/apple/swift-collections) - OrderedDictionary
- [swift-argument-parser](https://github.com/apple/swift-argument-parser) - CLI argument parsing

## License

Copyright © 2025 Rene Hexel. All rights reserved.

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## Support

For issues, questions, or feature requests, please open an issue on GitHub.

## References

This implementation is based on the following standards and technologies:

- [OMG MOFM2T (MOF Model-to-Text Transformation)](https://www.omg.org/spec/MOFM2T/) - The model-to-text standard
- [Eclipse Acceleo](https://eclipse.dev/acceleo/) - The reference MTL implementation
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - Expression language for queries
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The metamodelling foundation
