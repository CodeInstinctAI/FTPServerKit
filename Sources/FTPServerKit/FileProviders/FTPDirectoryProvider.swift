//
//  FTPDirectoryProvider.swift
//  FTPServerKit
//
//  Created by Marc Janga on 01/10/2026.
//

import Foundation

/// Serves a directory on disk, including its subdirectories. Read-only.
///
/// Clients can't reach anything outside `rootURL`, also not through symbolic links.
public struct FTPDirectoryProvider: FTPFileProvider {

    public let rootURL: URL
    /// Whether files and directories whose name starts with `.` are listed and served.
    public var includesHiddenFiles: Bool

    public init(rootURL: URL, includesHiddenFiles: Bool = false) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.includesHiddenFiles = includesHiddenFiles
    }

    public func itemInfo(atPath path: String) throws -> FTPFileInfo {
        let url = try fileURL(forPath: path)
        return try LocalFile.info(at: url, name: FTPPath.components(of: path).last ?? "/")
    }

    public func contentsOfDirectory(atPath path: String) throws -> [FTPFileInfo] {
        let url = try fileURL(forPath: path)
        guard try LocalFile.info(at: url, name: "").isDirectory else {
            throw FTPFileProviderError.notADirectory
        }
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: includesHiddenFiles ? [] : [.skipsHiddenFiles]
        )
        return try contents
            .map { try LocalFile.info(at: $0, name: $0.lastPathComponent) }
            .sorted { $0.name < $1.name }
    }

    public func openFile(atPath path: String, offset: UInt64) throws -> any FTPReadableFile {
        let url = try fileURL(forPath: path)
        guard try !LocalFile.info(at: url, name: "").isDirectory else {
            throw FTPFileProviderError.isADirectory
        }
        return try LocalFile.open(url, offset: offset)
    }

    /// Maps an FTP path to a file URL inside `rootURL`.
    private func fileURL(forPath path: String) throws -> URL {
        let components = FTPPath.components(of: path)
        if !includesHiddenFiles, components.contains(where: { $0.hasPrefix(".") }) {
            throw FTPFileProviderError.notFound
        }
        let url = components
            .reduce(rootURL) { $0.appendingPathComponent($1) }
            .resolvingSymlinksInPath()
        guard url.path == rootURL.path || url.path.hasPrefix(rootURL.path + "/") else {
            throw FTPFileProviderError.accessDenied
        }
        return url
    }
}
