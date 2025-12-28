//
// SwiftMTL.swift
// swift-mtl
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import ArgumentParser

/// The main entry point for the swift-mtl command-line tool.
///
/// Swift MTL provides a command-line interface for Model-to-Text Language
/// operations, including text generation from models, template parsing,
/// and validation of MTL modules.
///
/// ## Available Commands
///
/// - **generate**: Generate text from models using MTL templates
/// - **parse**: Parse and display MTL template structure
/// - **validate**: Validate MTL template syntax and semantics
///
/// ## Example Usage
///
/// ```bash
/// # Generate code from a model
/// swift-mtl generate template.mtl --model input.xmi --output generated/
///
/// # Parse an MTL template
/// swift-mtl parse template.mtl --detailed
///
/// # Validate multiple MTL files
/// swift-mtl validate *.mtl --verbose
/// ```
@main
struct SwiftMTLCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-mtl",
        abstract: "Model-to-Text Language command-line tool",
        discussion: """
            Swift MTL provides comprehensive support for model-to-text transformation using the
            Model-to-Text Language (MTL). It enables parsing, validation, and execution of MTL
            templates to generate code, documentation, and other textual artifacts from models.

            The tool supports standard MTL/Acceleo syntax for compatibility with existing templates
            while providing enhanced performance through Swift's concurrent execution model and
            type safety.
            """,
        version: "1.0.0",
        subcommands: [
            GenerateCommand.self,
            ParseCommand.self,
            ValidateCommand.self,
        ],
        defaultSubcommand: GenerateCommand.self
    )
}
