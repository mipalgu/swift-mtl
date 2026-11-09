//
//  MTLCharset.swift
//  MTL
//
//  Copyright (c) 2026 Rene Hexel. All rights reserved.
//

import EMFBase
import Foundation

// MARK: - Charset

/// A character set in which generated files are written.
///
/// The `file` block names its charset by string, for example `'UTF-8'` or
/// `'ISO-8859-1'`. This type resolves such names, encodes generated text and
/// decodes existing files.
public enum MTLCharset: Sendable, Equatable, Hashable {

    /// UTF-8 without a byte order mark.
    case utf8

    /// UTF-16 with a byte order mark, big-endian.
    case utf16

    /// UTF-16, big-endian, without a byte order mark.
    case utf16BigEndian

    /// UTF-16, little-endian, without a byte order mark.
    case utf16LittleEndian

    /// ISO-8859-1 (Latin-1).
    case latin1

    /// US-ASCII.
    case ascii

    /// The Windows code page 1252, a superset of the printable characters of ISO-8859-1.
    case windows1252

    /// Resolves a charset name.
    ///
    /// Names are matched ignoring case, hyphens, underscores and spaces.
    ///
    /// - Parameter name: The name as written in the `file` block.
    /// - Returns: The charset, or `nil` if the name is not supported.
    public init?(name: String) {
        let normalised = String(name.lowercased().filter { !MTLCharsetNames.ignoredCharacters.contains($0) })
        guard let match = MTLCharsetNames.spellings.first(where: { $0.names.contains(normalised) }) else {
            return nil
        }
        self = match.charset
    }

    /// Resolves a charset name or fails with a descriptive error.
    ///
    /// - Parameter name: The name as written in the `file` block.
    /// - Returns: The charset.
    /// - Throws: `MTLExecutionError.fileError` if the name is not supported.
    public static func resolve(_ name: String) throws -> MTLCharset {
        guard let charset = MTLCharset(name: name) else {
            throw MTLExecutionError.fileError("Unsupported charset '\(name)'")
        }
        return charset
    }

    /// The byte order mark written in front of the content, if the charset has one.
    private var byteOrderMark: [UInt8] {
        self == .utf16 ? [0xFE, 0xFF] : []
    }

    /// The Foundation encoding used for the content bytes.
    private var encoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16, .utf16BigEndian: return .utf16BigEndian
        case .utf16LittleEndian: return .utf16LittleEndian
        case .latin1: return .isoLatin1
        case .ascii: return .ascii
        case .windows1252: return .windowsCP1252
        }
    }

    /// The text encoding of the shared modelling libraries that writes the same bytes.
    public var textEncoding: TextEncoding {
        switch self {
        case .utf8: return .utf8
        case .utf16: return .utf16
        case .utf16BigEndian: return .utf16BigEndian
        case .utf16LittleEndian: return .utf16LittleEndian
        case .latin1: return .isoLatin1
        case .ascii: return .usASCII
        case .windows1252: return .windows1252
        }
    }

    /// Encodes text without loss.
    ///
    /// - Parameters:
    ///   - text: The text to encode.
    ///   - path: The path of the file, used in the error message.
    /// In the single-byte charsets, the text is first precomposed (Unicode normalisation form C),
    /// so that a letter followed by a combining mark is written as the single character that the
    /// charset holds. UTF-8 and UTF-16 are written as the text is.
    ///
    /// - Returns: The encoded bytes, including a byte order mark where the charset has one.
    /// - Throws: `MTLExecutionError.fileError` naming the first character that the charset cannot
    ///   represent, with its line and column.
    public func encode(_ text: String, path: String) throws -> Data {
        if self == .latin1 || self == .ascii || self == .windows1252 {
            do {
                return try textEncoding.encode(text)
            } catch {
                throw Self.unrepresentable(error, path: path)
            }
        }
        guard let data = text.data(using: encoding, allowLossyConversion: false) else {
            do {
                _ = try textEncoding.encode(text)
            } catch {
                throw Self.unrepresentable(error, path: path)
            }
            throw MTLExecutionError.fileError(
                "Cannot write a character to \(path): it is not representable in the file's charset")
        }
        return Data(byteOrderMark) + data
    }

    /// The error for a character that the charset cannot represent.
    ///
    /// - Parameters:
    ///   - error: The error of encoding the text.
    ///   - path: The path of the file.
    /// - Returns: An error that names the character, the file, and the line and column of the character.
    private static func unrepresentable(_ error: TextEncodingError, path: String) -> MTLExecutionError {
        switch error {
        case .unrepresentable(let character, _, let position):
            return MTLExecutionError.fileError(
                "Cannot write '\(character)' (U+\(hexadecimal(Character(character)))) at line \(position.line), "
                    + "column \(position.column) to \(path): it is not representable in the file's charset")
        }
    }

    /// Decodes the bytes of an existing file.
    ///
    /// A leading byte order mark of the charset is removed.
    ///
    /// - Parameter data: The file content.
    /// - Returns: The text, or `nil` if the bytes are not valid in this charset.
    public func decode(_ data: Data) -> String? {
        var bytes = data
        if bytes.starts(with: byteOrderMark) { bytes = bytes.dropFirst(byteOrderMark.count) }
        if self == .windows1252 { return textEncoding.decode(bytes) }
        guard self == .utf8 else { return String(data: bytes, encoding: encoding) }
        let text = String(decoding: bytes, as: UTF8.self)
        return text.utf8.elementsEqual(bytes) ? text : nil
    }

    /// Reads a file in this charset.
    ///
    /// - Parameter path: The file path.
    /// - Returns: The text, or `nil` if the file cannot be read or decoded.
    public func read(atPath path: String) -> String? {
        guard let data = MTLFileSystemStrategy.contents(atPath: path) else { return nil }
        return decode(data)
    }

    /// Reads the existing content of a generation strategy's target in this charset.
    ///
    /// - Parameters:
    ///   - url: The target file path or identifier.
    ///   - strategy: The strategy that holds the target.
    /// - Returns: The text, or `nil` if the target does not exist or cannot be decoded.
    @MainActor
    public func read(url: String, from strategy: any MTLGenerationStrategy) async -> String? {
        guard let data = await strategy.existingData(url: url) else { return nil }
        return decode(data)
    }

    /// Reads a file whose charset is not known.
    ///
    /// A UTF-16 byte order mark selects UTF-16; otherwise UTF-8 is tried, then ISO-8859-1.
    ///
    /// - Parameter path: The file path.
    /// - Returns: The text, or `nil` if the file cannot be read.
    public static func readDetecting(atPath path: String) -> String? {
        MTLFileSystemStrategy.contents(atPath: path).flatMap(detectingDecode)
    }

    /// Reads the existing content of a generation strategy's target whose charset is not known.
    ///
    /// - Parameters:
    ///   - url: The target file path or identifier.
    ///   - strategy: The strategy that holds the target.
    /// - Returns: The text, or `nil` if the target does not exist.
    @MainActor
    public static func readDetecting(url: String, from strategy: any MTLGenerationStrategy) async -> String? {
        await strategy.existingData(url: url).flatMap(detectingDecode)
    }

    /// Decodes bytes whose charset is not known.
    ///
    /// A UTF-16 byte order mark selects UTF-16; otherwise UTF-8 is tried, then ISO-8859-1.
    ///
    /// - Parameter data: The bytes.
    /// - Returns: The text, or `nil` if the bytes cannot be decoded.
    public static func detectingDecode(_ data: Data) -> String? {
        if data.starts(with: [0xFE, 0xFF]) { return MTLCharset.utf16.decode(data) }
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        return MTLCharset.utf8.decode(data) ?? MTLCharset.latin1.decode(data)
    }

    /// Formats the first scalar of a character as upper-case hexadecimal.
    private static func hexadecimal(_ character: Character) -> String {
        let value = character.unicodeScalars.first?.value ?? 0
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }
}
