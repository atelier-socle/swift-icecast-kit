// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Utility for formatting CLI output.
enum OutputFormatter {

    /// Formats a key-value pair for display.
    ///
    /// - Parameters:
    ///   - key: The label.
    ///   - value: The value to display.
    /// - Returns: A formatted string like `"  Key: Value"`.
    static func formatField(key: String, value: String) -> String {
        "  \(key): \(value)"
    }
}
