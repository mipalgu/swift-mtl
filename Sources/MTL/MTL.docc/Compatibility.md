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
options. Likewise, ``MTLQueryHelper/init(name:parameterTypes:returnType:call:)`` is
deprecated in favour of
``MTLQueryHelper/init(name:parameterTypes:returnType:collectionParameters:call:)``.
``MTLQueryHelpers/helpers(for:generator:)`` and
``MTLQueryServices/init(module:generator:)`` without a generator also use the options of
version 0.6, while ``MTLQueryHelpers/helpers(for:options:)`` and
``MTLQueryServices/init(module:options:)`` take options.

``MTLOptions/init(semantics:)`` selects ``MTLOptions/standard`` or ``MTLOptions/legacy`` from
a `ModellingSemantics` value, and ``MTLOptions/fromEnvironment(_:)`` reads that choice from the
`SWIFT_MODELLING_SEMANTICS` environment variable (`standard` or `legacy`;
``MTLOptions/standard`` if it is unset, and an error for any other value). A generator keeps
the options it is created with for every template it runs:

```swift
let generator = MTLGenerator(
    module: module, generationStrategy: strategy, options: try MTLOptions.fromEnvironment())
```

### Changed behaviours

| Behaviour | New default | Option | 0.6 behaviour |
|--|--|--|--|
| Expression language: collection arguments added whole, collection kinds kept, `including` on a single value giving a set, containers found through the resources, dot calls on a collection applied to each element | As in this release of swift-aql | ``MTLOptions/aql`` | `AQLOptions/legacy` |
| Line break after a block written on one line | Dropped when the line is empty once the block has run, as in Acceleo 4 | ``MTLOptions/blockLineBreaks`` | ``MTLBlockLineBreaks/kept`` |
| Collections passed to collection-typed parameters | Any collection whose elements conform; references resolved to objects; a single object as the only element; overloads chosen by element types; parameters hold collections | ``MTLOptions/collectionParameters`` | ``MTLCollectionParameters/exact`` |
| Declared types of `let` variables | Checked, with mismatches handled as ``MTLOptions/letTypeMismatches`` says | ``MTLOptions/checksLetTypes`` | `false` |
| Container lookups during a generation run | Cached, so models may change only through services that declare `modifiesModels` | ``MTLOptions/cachesContainers`` | `false` |
| Model objects written by expression tags and collected by `[collect]` | The class name and attribute values, as in `Person (name: Alice, age: 42)`, following the text Acceleo writes without the Java class name and hash code | ``MTLOptions/objectText`` | ``MTLObjectText/swift`` |

### Changes without an option

Some changes only affect templates that version 0.6 rejected, so they need no option. A `let`
variable may now declare a qualified or collection type, such as `ecore::EClass` or
`Sequence(String)`, and a directive missing its `]` is reported where it opens, with the code
``MTLDiagnosticCode/unterminatedDirective``. Generation statistics also report warnings in
``MTLGenerationStatistics/warnings``.

### Further options

Two options are not part of the change from version 0.6 and keep the same default in both
presets. ``MTLOptions/letTypeMismatches`` makes a `let` value that does not conform to its
declared type a type error (``MTLLetTypeMismatches/error``) or skips the block with a warning
(``MTLLetTypeMismatches/skip``), and ``MTLOptions/unsetFeatureReads`` reads unset features as
their defaults or as `nil`. ``MTLOptions/aql`` accepts any combination of the swift-aql
options, and containers are found as its `containerLookup` option says. The raw values of the
option enumerations, such as `acceleo`, `kept`, `conforming`, `exact`, `swift`, `error` and
`skip`, double as command-line spellings.
