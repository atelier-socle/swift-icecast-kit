// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Atelier Socle SAS

import Foundation

/// Abstraction over file I/O operations for testability.
protocol FileHandling: Sendable {
    /// Writes data to the file.
    func write(contentsOf data: Data) throws
    /// Flushes in-memory data to disk.
    func synchronize() throws
    /// Closes the file handle.
    func close() throws
}

/// Factory for creating file handles and files.
protocol FileHandlingFactory: Sendable {
    /// Opens a file for writing at the given path.
    func open(forWritingAtPath path: String) -> (any FileHandling)?
    /// Creates an empty file at the given path.
    func createFile(atPath path: String) -> Bool
}

// MARK: - Default Implementations

extension FileHandle: FileHandling {}

/// Default factory using `FileManager` and `FileHandle`.
struct DefaultFileHandlingFactory: FileHandlingFactory {
    func open(forWritingAtPath path: String) -> (any FileHandling)? {
        FileHandle(forWritingAtPath: path)
    }

    func createFile(atPath path: String) -> Bool {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
}
