// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// ANSI color codes.
public enum ANSIColor: Sendable {

    /// Red text.
    case red

    /// Green text.
    case green

    /// Yellow text.
    case yellow

    /// Blue text.
    case blue

    /// Cyan text.
    case cyan

    /// Magenta text.
    case magenta

    /// Bold text.
    case bold

    /// Dim/muted text.
    case dim

    /// Reset all formatting.
    case reset

    /// The ANSI escape sequence for this color.
    var code: String {
        switch self {
        case .red: return "\u{1B}[31m"
        case .green: return "\u{1B}[32m"
        case .yellow: return "\u{1B}[33m"
        case .blue: return "\u{1B}[34m"
        case .cyan: return "\u{1B}[36m"
        case .magenta: return "\u{1B}[35m"
        case .bold: return "\u{1B}[1m"
        case .dim: return "\u{1B}[2m"
        case .reset: return "\u{1B}[0m"
        }
    }
}

/// ANSI color output for terminal display.
///
/// Respects the `--no-color` flag and the `NO_COLOR` environment variable.
public struct ColorOutput: Sendable {

    /// Whether color output is enabled.
    public let isEnabled: Bool

    /// Create a ColorOutput instance.
    ///
    /// Color is enabled by default unless:
    /// - `noColor` parameter is true
    /// - `NO_COLOR` environment variable is set (any value)
    ///
    /// - Parameter noColor: Force disable color output.
    public init(noColor: Bool = false) {
        if noColor || ProcessInfo.processInfo.environment["NO_COLOR"] != nil {
            self.isEnabled = false
        } else {
            self.isEnabled = true
        }
    }

    /// Create a ColorOutput instance with explicit enabled state.
    ///
    /// Bypasses environment checks. Useful for testing.
    ///
    /// - Parameter isEnabled: Whether color output is enabled.
    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// Wrap text in the given ANSI color code.
    ///
    /// - Parameters:
    ///   - text: The text to colorize.
    ///   - color: The ANSI color to apply.
    /// - Returns: The colored text, or plain text if colors are disabled.
    public func colored(_ text: String, _ color: ANSIColor) -> String {
        guard isEnabled else { return text }
        return "\(color.code)\(text)\(ANSIColor.reset.code)"
    }

    /// Green text (success).
    ///
    /// - Parameter text: The text to display.
    /// - Returns: Green-colored text.
    public func success(_ text: String) -> String {
        colored(text, .green)
    }

    /// Red text (error).
    ///
    /// - Parameter text: The text to display.
    /// - Returns: Red-colored text.
    public func error(_ text: String) -> String {
        colored(text, .red)
    }

    /// Yellow text (warning).
    ///
    /// - Parameter text: The text to display.
    /// - Returns: Yellow-colored text.
    public func warning(_ text: String) -> String {
        colored(text, .yellow)
    }

    /// Cyan text (info).
    ///
    /// - Parameter text: The text to display.
    /// - Returns: Cyan-colored text.
    public func info(_ text: String) -> String {
        colored(text, .cyan)
    }

    /// Bold text.
    ///
    /// - Parameter text: The text to display.
    /// - Returns: Bold text.
    public func bold(_ text: String) -> String {
        colored(text, .bold)
    }

    /// Dim/muted text.
    ///
    /// - Parameter text: The text to display.
    /// - Returns: Dim text.
    public func dim(_ text: String) -> String {
        colored(text, .dim)
    }
}
