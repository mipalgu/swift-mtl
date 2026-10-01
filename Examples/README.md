# MTL Examples

This directory contains example MTL templates demonstrating various features.

## Running Examples

From the swift-mtl root directory:

```sh
# Example 1: Hello World
swift-mtl generate Examples/01-hello-world.mtl --output /tmp/mtl-examples/

# Example 2: Expressions
swift-mtl generate Examples/02-expressions.mtl --output /tmp/mtl-examples/

# Example 3: Control Flow
swift-mtl generate Examples/03-control-flow.mtl --output /tmp/mtl-examples/

# Example 4: File Blocks (generates multiple files)
swift-mtl generate Examples/04-file-blocks.mtl --output /tmp/mtl-examples/

# Example 5: Queries
swift-mtl generate Examples/05-queries.mtl --output /tmp/mtl-examples/

# Example 6: Macros
swift-mtl generate Examples/06-macros.mtl --output /tmp/mtl-examples/

# Example 7: Protected Areas
swift-mtl generate Examples/07-protected-areas.mtl --output /tmp/mtl-examples/
```

## Example Overview

### 01-hello-world.mtl
The simplest possible MTL template demonstrating basic text generation.

**Demonstrates:**
- Module declaration
- Basic template
- Plain text output

### 02-expressions.mtl
Various MTL expression types and operations.

**Demonstrates:**
- Arithmetic operations (addition, subtraction, multiplication)
- String concatenation
- Query definitions
- Query invocation

### 03-control-flow.mtl
Control flow statements for conditional and variable logic.

**Demonstrates:**
- If statements (true/false conditions)
- If/elseif/else chains
- Let bindings for variables
- Variable usage in expressions

### 04-file-blocks.mtl
Generating multiple output files from a single template.

**Demonstrates:**
- File blocks with custom names
- File modes (overwrite, append, create)
- Character encoding specification
- Multiple file generation

### 05-queries.mtl
Reusable query functions for common operations.

**Demonstrates:**
- Query definitions with parameters
- Mathematical queries
- Boolean queries
- String manipulation queries
- Query composition

### 06-macros.mtl
Reusable text blocks with parameters.

**Demonstrates:**
- Macro definitions
- Macro parameters
- Body parameters for content blocks
- Nested macro invocations
- Formatting patterns

### 07-protected-areas.mtl
Protected sections that preserve manual edits across regenerations.

**Demonstrates:**
- Protected area declarations
- Custom marker tags
- Manual edit preservation
- Code generation patterns

## Output Location

All examples default to outputting in `/tmp/mtl-examples/`. You can specify a different location:

```sh
swift-mtl generate Examples/01-hello-world.mtl --output my-output-dir/
```

## Viewing Results

For examples that generate to `stdout` (Examples 1-3, 5-7):

```sh
cat /tmp/mtl-examples/stdout
```

For Example 4 (file blocks):

```sh
ls /tmp/mtl-examples/
cat /tmp/mtl-examples/greeting.txt
cat /tmp/mtl-examples/data.txt
cat /tmp/mtl-examples/info.txt
```

## Next Steps

After trying these examples:
1. Modify the templates to experiment with different features
2. Combine multiple features in your own templates
3. Try generating from actual model files (XMI/JSON)
4. Explore the full MTL syntax in the main README.md
