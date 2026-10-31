# Compatibility with 0.6

Choose between the behaviour of this release and that of version 0.6.

## Overview

This release changes how some templates generate text. Each change has an option in
``MTLOptions``. The default value of every option, also available as ``MTLOptions/standard``,
gives the new behaviour, and ``MTLOptions/legacy`` gives the behaviour of version 0.6 for every
template that version could run.

Pass the options to ``MTLGenerator/init(module:generationStrategy:options:serviceProviders:globals:)``
or ``MTLExecutionContext/init(module:generationStrategy:options:aqlContext:protectedAreaManager:serviceProviders:)``:

```swift
let generator = MTLGenerator(module: module, generationStrategy: strategy, options: .legacy)
```

The initialisers of version 0.6, without an `options` argument, keep their signatures and
their behaviour: they use ``MTLOptions/legacy`` with the given
``MTLOptions/unsetFeatureReads``. They are deprecated in favour of the initialisers that take
options. ``MTLQueryHelpers/helpers(for:generator:)`` and
``MTLQueryServices/init(module:generator:)`` without a generator also use the options of
version 0.6, while ``MTLQueryHelpers/helpers(for:options:)`` and
``MTLQueryServices/init(module:options:)`` take options.

``MTLOptions/init(semantics:)`` selects ``MTLOptions/standard`` or ``MTLOptions/legacy`` from
a `ModellingSemantics` value, and ``MTLOptions/fromEnvironment(_:)`` reads that choice from the
`SWIFT_MODELLING_SEMANTICS` environment variable (`standard` or `legacy`;
``MTLOptions/standard`` if it is unset). A generator keeps the options it is created with for
every template it runs:

```swift
let generator = MTLGenerator(
    module: module, generationStrategy: strategy, options: try MTLOptions.fromEnvironment())
```

### Changed behaviours

| Behaviour | New default | Option | 0.6 behaviour |
|--|--|--|--|
| Expression language: collection arguments added whole, collection kinds kept, `including` on a single value giving a set, containers found through the resources | As in this release of swift-aql | ``MTLOptions/aql`` | `AQLOptions/legacy` |
| Line break after a block written on one line | Dropped when the line is empty once the block has run, as in Acceleo 4 | ``MTLOptions/blockLineBreaks`` | ``MTLBlockLineBreaks/kept`` |
| Collections passed to collection-typed parameters | Any collection whose elements conform; references resolved to objects; a single object as the only element; overloads chosen by element types; parameters hold collections | ``MTLOptions/collectionParameters`` | ``MTLCollectionParameters/exact`` |
| Declared types of `let` variables | Checked, with mismatches handled as ``MTLOptions/letTypeMismatches`` says | ``MTLOptions/checksLetTypes`` | `false` |
| Container lookups during a generation run | Cached, so models may change only through services that declare `modifiesModels` | ``MTLOptions/cachesContainers`` | `false` |

### Changes without an option

Some changes only affect templates that version 0.6 rejected, so they need no option. A `let`
variable may now declare a qualified or collection type, such as `ecore::EClass` or
`Sequence(String)`, and a directive missing its `]` is reported where it opens, with the code
``MTLDiagnosticCode/unterminatedDirective``. Generation statistics also report warnings in
``MTLGenerationStatistics/warnings``.
