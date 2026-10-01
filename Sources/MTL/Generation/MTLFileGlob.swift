//
//  MTLFileGlob.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import Foundation

// MARK: - File Glob

/// Matches file URLs against simple glob patterns.
///
/// Supports `*` (any run of characters except `/`), `**` (any run of
/// characters) and `?` (one character except `/`). All other characters match
/// themselves.
enum MTLFileGlob {

    /// The path separator in URLs.
    private static let separator: Character = "/"

    /// Matches a URL against a pattern.
    ///
    /// A pattern without a path separator is matched against the last path
    /// component of the URL, any other pattern against the whole URL.
    ///
    /// - Parameters:
    ///   - pattern: The glob pattern.
    ///   - url: The file URL.
    /// - Returns: `true` if the pattern matches.
    static func matches(pattern: String, url: String) -> Bool {
        let subject: Substring
        if pattern.contains(separator) {
            subject = Substring(url)
        } else {
            subject = url.split(separator: separator, omittingEmptySubsequences: false).last ?? ""
        }
        return match(Array(pattern), 0, Array(subject), 0)
    }

    /// Matches the pattern characters from an index against the text from an index.
    private static func match(_ pattern: [Character], _ p: Int, _ text: [Character], _ t: Int) -> Bool {
        if p == pattern.count { return t == text.count }
        switch pattern[p] {
        case "*":
            let crossesSeparators = p + 1 < pattern.count && pattern[p + 1] == "*"
            let next = crossesSeparators ? p + 2 : p + 1
            var end = t
            while true {
                if match(pattern, next, text, end) { return true }
                guard end < text.count, crossesSeparators || text[end] != separator else { return false }
                end += 1
            }
        case "?":
            guard t < text.count, text[t] != separator else { return false }
            return match(pattern, p + 1, text, t + 1)
        default:
            guard t < text.count, text[t] == pattern[p] else { return false }
            return match(pattern, p + 1, text, t + 1)
        }
    }
}
