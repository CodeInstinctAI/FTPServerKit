//
//  FTPSingleFileProvider.swift
//  FTPServerKit
//
//  Created by Marc Janga on 01/10/2026.
//

import Foundation

/// Serves one file, listed alone in the root directory. Read-only.
public struct FTPSingleFileProvider: FTPFileProvider {

    /// The file on disk.
    public let fileURL: URL
    /// The name clients see, `fileURL.lastPathComponent` unless set.
    public let fileName: String

    /// Creates a provider that serves `fileURL`, under `fileName` if you pass one.
    public init(fileURL: URL, fileName: String? = nil) {
        self.fileURL = fileURL
        self.fileName = fileName ?? fileURL.lastPathComponent
    }

    public func itemInfo(atPath path: String) throws -> FTPFileInfo {
        if path == "/" {
            let file = try fileInfo()
            return FTPFileInfo(name: "/", isDirectory: true, size: 0, modificationDate: file.modificationDate)
        }
        guard path == filePath else { throw FTPFileProviderError.notFound }
        return try fileInfo()
    }

    public func contentsOfDirectory(atPath path: String) throws -> [FTPFileInfo] {
        switch path {
        case "/": return [try fileInfo()]
        case filePath: throw FTPFileProviderError.notADirectory
        default: throw FTPFileProviderError.notFound
        }
    }

    public func openFile(atPath path: String, offset: UInt64) throws -> any FTPReadableFile {
        switch path {
        case "/": throw FTPFileProviderError.isADirectory
        case filePath: return try LocalFile.open(fileURL, offset: offset)
        default: throw FTPFileProviderError.notFound
        }
    }

    private var filePath: String { "/" + fileName }

    private func fileInfo() throws -> FTPFileInfo {
        let info = try LocalFile.info(at: fileURL, name: fileName)
        guard !info.isDirectory else { throw FTPFileProviderError.isADirectory }
        return info
    }
}
