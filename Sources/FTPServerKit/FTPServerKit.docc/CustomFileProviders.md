# Writing a Custom File Provider

Serve files from memory, a database or anywhere else by conforming to `FTPFileProvider`.

## Overview

``FTPDirectoryProvider`` and ``FTPSingleFileProvider`` serve files from disk. To serve anything else, conform a type to ``FTPFileProvider`` and pass it to the server like the built-in ones.

A provider answers three questions about paths:

- ``FTPFileProvider/itemInfo(atPath:)``: what is at a path, for CWD, SIZE and MDTM.
- ``FTPFileProvider/contentsOfDirectory(atPath:)``: what a directory contains, for LIST and NLST.
- ``FTPFileProvider/openFile(atPath:offset:)``: the bytes of a file, for RETR.

Paths are always absolute and normalized, like `/` or `/folder/file.txt`. The server resolves `.`, `..` and relative paths before it calls the provider, and `..` never goes above `/`.

### Serve files from memory

This provider serves a flat set of in-memory files in the root directory:

```swift
import FTPServerKit
import Foundation

struct InMemoryProvider: FTPFileProvider {
    let files: [String: Data]
    let modificationDate = Date()

    func itemInfo(atPath path: String) throws -> FTPFileInfo {
        if path == "/" {
            return FTPFileInfo(name: "/", isDirectory: true, size: 0, modificationDate: modificationDate)
        }
        let name = String(path.dropFirst())
        guard let data = files[name] else { throw FTPFileProviderError.notFound }
        return FTPFileInfo(name: name, isDirectory: false, size: UInt64(data.count), modificationDate: modificationDate)
    }

    func contentsOfDirectory(atPath path: String) throws -> [FTPFileInfo] {
        guard path == "/" else {
            _ = try itemInfo(atPath: path) // throws notFound for unknown paths
            throw FTPFileProviderError.notADirectory
        }
        return try files.keys.sorted().map { try itemInfo(atPath: "/" + $0) }
    }

    func openFile(atPath path: String, offset: UInt64) throws -> any FTPReadableFile {
        guard path != "/" else { throw FTPFileProviderError.isADirectory }
        guard let data = files[String(path.dropFirst())] else { throw FTPFileProviderError.notFound }
        return DataFile(data: data, offset: Int(offset))
    }
}

final class DataFile: FTPReadableFile {
    private let data: Data
    private var position: Int

    init(data: Data, offset: Int) {
        self.data = data
        self.position = min(offset, data.count)
    }

    func read(upToCount count: Int) throws -> Data? {
        let end = min(position + count, data.count)
        defer { position = end }
        return data.subdata(in: position..<end)
    }

    func close() throws {}
}
```

The server reads files in chunks through ``FTPReadableFile/read(upToCount:)`` until it gets empty or `nil` data, and then calls ``FTPReadableFile/close()``. `FileHandle` already conforms to ``FTPReadableFile``, so a provider that reads from disk can return one directly.

### Report errors

Throw ``FTPFileProviderError`` for paths that don't exist or have the wrong type. The server answers clients with a `550` reply that matches the error. Any other error you throw also gets a `550` reply, with the error's `localizedDescription`, and is logged as a warning.

### Threading

The server calls the provider on its internal queue, never concurrently for one server. While a provider method runs, the server can't answer its other clients, so keep the methods fast: load slow data ahead of time, or stream it through your ``FTPReadableFile``.

Providers have to be `Sendable`, because you can replace ``FTPServer/fileProvider`` from any thread while the server runs.
