//
//  FTPFileProvider.swift
//  FTPServerKit
//
//  Created by Marc Janga on 01/10/2026.
//

import Foundation

/// Supplies the files an ``FTPServer`` serves.
///
/// Paths are always absolute and normalized: they start with `/`, use `/` as separator and
/// never contain `.` or `..` components. `/` is the root the clients see.
///
/// Methods are called on the server's internal queue, never concurrently for one server.
public protocol FTPFileProvider: Sendable {
    /// Information about the file or directory at `path`.
    func itemInfo(atPath path: String) throws -> FTPFileInfo

    /// The entries of the directory at `path`.
    func contentsOfDirectory(atPath path: String) throws -> [FTPFileInfo]

    /// Opens the file at `path` for reading, positioned at `offset` bytes from the start.
    func openFile(atPath path: String, offset: UInt64) throws -> any FTPReadableFile
}

/// A file or directory as listed to FTP clients.
public struct FTPFileInfo: Sendable, Equatable {
    public var name: String
    public var isDirectory: Bool
    /// Size in bytes; `0` for directories.
    public var size: UInt64
    public var modificationDate: Date

    public init(name: String, isDirectory: Bool, size: UInt64, modificationDate: Date) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
    }
}

/// A file opened by an ``FTPFileProvider``. The server reads it in chunks and closes it when the transfer ends.
public protocol FTPReadableFile: AnyObject {
    /// Returns up to `count` bytes, or empty or `nil` data at the end of the file.
    func read(upToCount count: Int) throws -> Data?
    func close() throws
}

extension FileHandle: FTPReadableFile {}

/// Errors a file provider throws; the server answers each with `550`.
public enum FTPFileProviderError: Error, Sendable, Equatable {
    case notFound
    case notADirectory
    case isADirectory
    case accessDenied
}

/// Helpers shared by the providers that serve files from disk.
enum LocalFile {

    static func info(at url: URL, name: String) throws -> FTPFileInfo {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FTPFileProviderError.notFound
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return FTPFileInfo(
            name: name,
            isDirectory: isDirectory.boolValue,
            size: isDirectory.boolValue ? 0 : UInt64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? Date()
        )
    }

    static func open(_ url: URL, offset: UInt64) throws -> any FTPReadableFile {
        let handle = try FileHandle(forReadingFrom: url)
        if offset > 0 {
            try handle.seek(toOffset: offset)
        }
        return handle
    }
}
