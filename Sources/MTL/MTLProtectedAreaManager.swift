//
//  MTLProtectedAreaManager.swift
//  MTL
//
//  Created by Rene Hexel on 28/12/2025.
//  Copyright (c) 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - MTL Protected Area Manager

/// Thread-safe manager for preserving protected area content across regenerations.
///
/// Protected areas allow user code to be preserved when templates are regenerated,
/// enabling a generate-modify-regenerate workflow where custom code survives
/// regeneration cycles.
///
/// ## Overview
///
/// Protected areas work by:
/// 1. **Marking sections**: Templates define protected areas with unique IDs
/// 2. **Scanning existing files**: Before regeneration, existing files are scanned
/// 3. **Extracting content**: Content between protection markers is extracted
/// 4. **Preserving during regeneration**: Extracted content replaces default content
/// 5. **Maintaining markers**: Protection markers are preserved in output
///
/// ## Protection Markers
///
/// Protected areas are delimited by start/end markers:
/// ```
/// // START PROTECTED REGION user-imports
/// import MyCustomLibrary
/// // END PROTECTED REGION user-imports
/// ```
///
/// The markers can have custom prefixes (e.g., `//`, `<!--`, `#`) to match
/// the comment syntax of the target language.
///
/// ## Example Usage
///
/// ```swift
/// let manager = MTLProtectedAreaManager()
///
/// // Scan existing file before regeneration
/// try await manager.scanFile("/output/Person.swift")
///
/// // During regeneration, retrieve preserved content
/// if let content = await manager.getContent("user-imports") {
///     // Use preserved content instead of default
/// }
///
/// // After regeneration, check what was preserved
/// let preserved = await manager.getAllContent()
/// print("Preserved \(preserved.count) protected areas")
/// ```
///
/// - Note: This actor ensures thread-safe concurrent access to protected area content.
public actor MTLProtectedAreaManager {

    // MARK: - Types

    /// Represents a protected area with its content and markers.
    public struct ProtectedAreaContent: Sendable, Equatable, Hashable {
        /// The unique identifier for this protected area.
        public let id: String

        /// The preserved content (without markers).
        public let content: String

        /// The start marker that was found.
        public let startMarker: String

        /// The end marker that was found.
        public let endMarker: String

        /// Creates a new protected area content record.
        ///
        /// - Parameters:
        ///   - id: The unique identifier
        ///   - content: The preserved content
        ///   - startMarker: The start marker
        ///   - endMarker: The end marker
        public init(id: String, content: String, startMarker: String, endMarker: String) {
            self.id = id
            self.content = content
            self.startMarker = startMarker
            self.endMarker = endMarker
        }
    }

    // MARK: - Properties

    /// Storage for protected area content, keyed by ID.
    private var areas: [String: ProtectedAreaContent] = [:]

    /// Debug mode flag for logging.
    private var debug: Bool = false

    // MARK: - Initialisation

    /// Creates a new protected area manager.
    public init() {}

    // MARK: - Debug Configuration

    /// Enables or disables debug logging.
    ///
    /// - Parameter enabled: Whether to enable debug mode (default: true)
    public func enableDebugging(_ enabled: Bool = true) {
        debug = enabled
    }

    // MARK: - File Scanning

    /// Scans a file for protected areas and extracts their content.
    ///
    /// This method reads the specified file and searches for protected area
    /// markers. For each protected area found, it extracts the content between
    /// the markers and stores it for later retrieval.
    ///
    /// Protected area markers have the format:
    /// ```
    /// {prefix}START PROTECTED REGION {id}
    /// {content}
    /// {prefix}END PROTECTED REGION {id}
    /// ```
    ///
    /// - Parameter path: The file path to scan
    ///
    /// - Throws: `MTLExecutionError.fileError` if the file cannot be read
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Scan existing file
    /// try await manager.scanFile("/output/Person.swift")
    ///
    /// // Now can retrieve preserved content
    /// let imports = await manager.getContent("user-imports")
    /// ```
    public func scanFile(_ path: String) throws {
        if debug {
            print("[Protected Areas] Scanning file: \(path)")
        }

        // Check if file exists
        guard FileManager.default.fileExists(atPath: path) else {
            if debug {
                print("[Protected Areas] File does not exist, skipping: \(path)")
            }
            return
        }

        // Read file content
        guard let fileContent = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw MTLExecutionError.fileError(
                "Failed to read file for protected area scanning: \(path)")
        }

        // Scan for protected areas
        scanContent(fileContent)

        if debug {
            print("[Protected Areas] Found \(areas.count) protected areas in \(path)")
        }
    }

    /// Scans text content for protected areas and extracts them.
    ///
    /// This method is useful for scanning content from sources other than files
    /// (e.g., in-memory strings, network responses).
    ///
    /// - Parameter content: The text content to scan
    public func scanContent(_ content: String) {
        let lines = content.components(separatedBy: .newlines)
        var currentArea: (id: String, startMarker: String, contentLines: [String])? = nil

        for line in lines {
            // Check for start marker
            if let startMatchId = matchStartMarker(line) {
                // Save any previous area that wasn't closed
                if let unclosedArea = currentArea, debug {
                    print("[Protected Areas] Warning: Unclosed protected area '\(unclosedArea.id)'")
                }

                // Start new area
                currentArea = (id: startMatchId, startMarker: line, contentLines: [])

                if debug {
                    print("[Protected Areas] Found start: \(startMatchId)")
                }
                continue
            }

            // Check for end marker
            if let endMatchId = matchEndMarker(line) {
                if let area = currentArea, area.id == endMatchId {
                    // Complete the area
                    let content = area.contentLines.joined(separator: "\n")
                    let protectedArea = ProtectedAreaContent(
                        id: area.id,
                        content: content,
                        startMarker: area.startMarker,
                        endMarker: line
                    )
                    areas[area.id] = protectedArea

                    if debug {
                        print(
                            "[Protected Areas] Preserved '\(area.id)': \(content.count) characters")
                    }

                    currentArea = nil
                } else if debug {
                    print(
                        "[Protected Areas] Warning: End marker '\(endMatchId)' without matching start"
                    )
                }
                continue
            }

            // Accumulate content if inside a protected area
            if currentArea != nil {
                currentArea?.contentLines.append(line)
            }
        }

        // Warn about unclosed areas
        if let unclosedArea = currentArea, debug {
            print("[Protected Areas] Warning: Unclosed protected area '\(unclosedArea.id)'")
        }
    }

    // MARK: - Content Access

    /// Retrieves the preserved content for a protected area.
    ///
    /// - Parameter id: The protected area identifier
    /// - Returns: The preserved content, or nil if no content exists
    ///
    /// ## Example
    ///
    /// ```swift
    /// if let imports = await manager.getContent("user-imports") {
    ///     writer.write(imports)
    /// } else {
    ///     // Use default content
    ///     writer.write("// Default imports")
    /// }
    /// ```
    public func getContent(_ id: String) -> String? {
        return areas[id]?.content
    }

    /// Retrieves the complete protected area record.
    ///
    /// This includes the content plus the original markers, which can be
    /// useful for preserving exact formatting.
    ///
    /// - Parameter id: The protected area identifier
    /// - Returns: The protected area record, or nil if not found
    public func getArea(_ id: String) -> ProtectedAreaContent? {
        return areas[id]
    }

    /// Returns all protected area content.
    ///
    /// - Returns: Dictionary mapping IDs to protected area records
    public func getAllContent() -> [String: ProtectedAreaContent] {
        return areas
    }

    /// Checks if content exists for a protected area.
    ///
    /// - Parameter id: The protected area identifier
    /// - Returns: True if preserved content exists, false otherwise
    public func hasContent(_ id: String) -> Bool {
        return areas[id] != nil
    }

    // MARK: - Content Modification

    /// Stores protected area content manually.
    ///
    /// This is useful for programmatically adding protected areas without
    /// scanning files.
    ///
    /// - Parameters:
    ///   - id: The protected area identifier
    ///   - content: The content to preserve
    ///   - markers: Optional tuple of (startMarker, endMarker)
    ///
    /// ## Example
    ///
    /// ```swift
    /// await manager.setContent(
    ///     "custom-section",
    ///     content: "My custom code",
    ///     markers: ("// START PROTECTED REGION custom-section",
    ///               "// END PROTECTED REGION custom-section")
    /// )
    /// ```
    public func setContent(
        _ id: String,
        content: String,
        markers: (String, String)? = nil
    ) {
        let (startMarker, endMarker) =
            markers ?? (
                "START PROTECTED REGION \(id)",
                "END PROTECTED REGION \(id)"
            )

        let area = ProtectedAreaContent(
            id: id,
            content: content,
            startMarker: startMarker,
            endMarker: endMarker
        )

        areas[id] = area

        if debug {
            print("[Protected Areas] Manually set '\(id)': \(content.count) characters")
        }
    }

    /// Removes a protected area from the manager.
    ///
    /// - Parameter id: The protected area identifier to remove
    public func removeContent(_ id: String) {
        areas.removeValue(forKey: id)

        if debug {
            print("[Protected Areas] Removed '\(id)'")
        }
    }

    /// Clears all protected area content.
    public func clear() {
        areas.removeAll()

        if debug {
            print("[Protected Areas] Cleared all content")
        }
    }

    // MARK: - Marker Generation

    /// Generates standard protection markers for a given ID and prefix.
    ///
    /// - Parameters:
    ///   - id: The protected area identifier
    ///   - prefix: The comment prefix (e.g., "//", "<!--", "#")
    ///
    /// - Returns: A tuple of (startMarker, endMarker)
    ///
    /// ## Example
    ///
    /// ```swift
    /// let (start, end) = await manager.generateMarkers(
    ///     id: "user-code",
    ///     prefix: "//"
    /// )
    /// // start = "// START PROTECTED REGION user-code"
    /// // end = "// END PROTECTED REGION user-code"
    /// ```
    public func generateMarkers(id: String, prefix: String?) -> (String, String) {
        let effectivePrefix = prefix ?? ""
        let separator = effectivePrefix.isEmpty ? "" : " "

        let startMarker = "\(effectivePrefix)\(separator)START PROTECTED REGION \(id)"
        let endMarker = "\(effectivePrefix)\(separator)END PROTECTED REGION \(id)"

        return (startMarker, endMarker)
    }

    // MARK: - Private Helpers

    /// Matches a start marker line and extracts the ID.
    private func matchStartMarker(_ line: String) -> String? {
        // Pattern: {anything}START PROTECTED REGION {id}
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard let range = trimmed.range(of: "START PROTECTED REGION ") else {
            return nil
        }

        let id = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }

        return id
    }

    /// Matches an end marker line and extracts the ID.
    private func matchEndMarker(_ line: String) -> String? {
        // Pattern: {anything}END PROTECTED REGION {id}
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard let range = trimmed.range(of: "END PROTECTED REGION ") else {
            return nil
        }

        let id = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }

        return id
    }

    // MARK: - Statistics

    /// Returns a summary of protected area statistics.
    ///
    /// - Returns: A formatted string describing the current state
    public func summary() -> String {
        var lines: [String] = []
        lines.append("Protected Area Manager Summary:")
        lines.append("  Total areas: \(areas.count)")

        if !areas.isEmpty {
            let totalChars = areas.values.reduce(0) { $0 + $1.content.count }
            lines.append("  Total content: \(totalChars) characters")
            lines.append("  Areas:")
            for (id, area) in areas.sorted(by: { $0.key < $1.key }) {
                lines.append("    - \(id): \(area.content.count) chars")
            }
        }

        return lines.joined(separator: "\n")
    }
}
