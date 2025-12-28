# MTL Tests

This directory contains comprehensive tests for the MTL (Model-to-Text Language) parser and CLI.

## Test Suites

- **MTL Parser Tests** - Lexer and parser functionality (73 tests)
- **MTL Generator Tests** - Text generation from templates
- **MTL Integration Tests** - End-to-end runtime execution
- **MTL Statement Tests** - Individual statement execution
- **MTL Macro Tests** - Macro expansion
- **MTL Protected Area Tests** - Protected region handling
- **MTL Indentation Tests** - Whitespace handling
- **MTL Module Tests** - Module structure
- **CLI Integration Tests** - End-to-end CLI command testing (30 tests)

**Total: 169 tests**

## Running Tests

### Basic Usage

```sh
cd swift-mtl
swift test --scratch-path /tmp/build-swift-mtl
```

### Using Custom Scratch Path

The scratch directory path can be overridden using the `SWIFT_MTL_SCRATCH_PATH` environment variable:

```sh
export SWIFT_MTL_SCRATCH_PATH=/custom/build/path
swift test --scratch-path /custom/build/path
```

Or inline:

```sh
env SWIFT_MTL_SCRATCH_PATH=/custom/build/path swift test --scratch-path /custom/build/path
```

**Note**: Both the `--scratch-path` argument to `swift test` and the `SWIFT_MTL_SCRATCH_PATH` environment variable should point to the same location. The environment variable is used by the test helpers to locate the built `swift-mtl` executable.

### Default Behavior

If `SWIFT_MTL_SCRATCH_PATH` is not set, tests will look for the executable at:
```
/tmp/build-swift-mtl/debug/swift-mtl
```

## Test Resources

Test templates are located in `Resources/templates/`:
- `simple-hello.mtl` - Basic template
- `with-expressions.mtl` - Arithmetic expressions and queries
- `with-control-flow.mtl` - If/let statements
- `with-file-blocks.mtl` - File generation
- `invalid-syntax.mtl` - Parse error testing
- `missing-module.mtl` - Missing module error
- `unclosed-block.mtl` - Unclosed block error

## CLI Integration Tests

The CLI integration tests use subprocess execution to test the actual `swift-mtl` executable:
- Generate command tests (8 tests)
- Parse command tests (6 tests)
- Validate command tests (6 tests)
- Help and version tests (3 tests)

These tests require the `swift-mtl` executable to be built before running tests.
