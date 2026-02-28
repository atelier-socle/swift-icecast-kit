// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

/// Standard exit codes for the CLI.
public enum ExitCodes {

    /// Successful execution.
    public static let success: Int32 = 0

    /// General error.
    public static let generalError: Int32 = 1

    /// Connection failed.
    public static let connectionError: Int32 = 2

    /// Authentication failed.
    public static let authenticationError: Int32 = 3

    /// File not found or unreadable.
    public static let fileError: Int32 = 4

    /// Invalid arguments.
    public static let argumentError: Int32 = 5

    /// Server error.
    public static let serverError: Int32 = 6

    /// Timeout.
    public static let timeout: Int32 = 7
}
