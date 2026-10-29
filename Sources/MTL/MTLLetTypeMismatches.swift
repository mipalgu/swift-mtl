//
//  MTLLetTypeMismatches.swift
//  MTL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

/// How a `let` block treats a value that does not conform to the declared type of its variable.
///
/// A `let` variable may declare a type, as in `[let names : Sequence(String) = e]`. By default a
/// value that does not conform to that type is a type error that stops the generation, as for a
/// template parameter. The OMG MOFM2T specification and Acceleo 3 instead treat a typed `let` as
/// a type test, whose body is generated only if the value conforms; ``skip`` follows them and
/// also reports a warning, so that the mismatch does not go unnoticed. `null` conforms to every
/// type in either mode.
///
/// The raw value of each case is a lower-case word that can double as a command-line spelling,
/// so that a tool can parse an option with ``init(rawValue:)`` and list the accepted spellings
/// through ``allCases``.
public enum MTLLetTypeMismatches: String, Sendable, CaseIterable, Hashable {
    /// A mismatch is a type error that stops the generation.
    ///
    /// The generation throws ``MTLExecutionError/typeError(_:)``, naming the variable, its
    /// declared type and the type of the value. This is the default.
    case error

    /// A mismatch skips the body of the `let` block and reports a warning.
    ///
    /// The remaining bindings of the block are not evaluated, nothing from the body is
    /// generated, and the generation continues after the block. The warning is a
    /// `SourceDiagnostic` with the code ``MTLDiagnosticCode/letTypeMismatch`` that names the
    /// variable, its declared type and the type of the value; it is recorded in
    /// ``MTLGenerationStatistics/warnings`` and ``MTLExecutionContext/warnings``.
    case skip
}
