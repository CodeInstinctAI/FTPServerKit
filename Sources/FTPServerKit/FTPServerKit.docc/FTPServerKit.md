# ``FTPServerKit``

A lightweight, read-only FTP server for iOS and macOS apps, built on Network.framework with no dependencies.

## Overview

FTPServerKit lets your app share files with any FTP client on the local network: FileZilla, Cyberduck, Finder, curl, or embedded devices that download files over FTP.

```swift
let server = FTPServer(
    configuration: FTPServerConfiguration(authentication: .anonymous),
    fileProvider: FTPDirectoryProvider(rootURL: documents)
)
let port = try await server.start()
```

The server serves a whole directory, a single file, or your own source through ``FTPFileProvider``. It supports passive mode, resuming downloads and streaming large files in chunks. It reports what it does through an `AsyncStream`, a Combine publisher, a delegate and a log handler.

### Supported commands

USER, PASS, PWD, CWD, CDUP, TYPE, MODE, STRU, PASV, EPSV, LIST, NLST, RETR, SIZE, MDTM, REST, ABOR, SYST, FEAT, OPTS, NOOP and QUIT.

The server is read-only: uploads, deletes and renames get `550`. Active mode (PORT, EPRT) isn't supported, so clients have to use passive mode, which they do by default.

> Important: FTP has no encryption. Usernames, passwords and files travel over the network as plain text, so only use the server on networks you trust.

## Topics

### Essentials

- <doc:GettingStarted>
- ``FTPServer``
- ``FTPServerConfiguration``

### Serving Files

- ``FTPDirectoryProvider``
- ``FTPSingleFileProvider``
- <doc:CustomFileProviders>
- ``FTPFileProvider``
- ``FTPFileInfo``
- ``FTPReadableFile``
- ``FTPFileProviderError``

### Observing the Server

- <doc:ObservingTheServer>
- ``FTPServerEvent``
- ``FTPServerDelegate``
- ``FTPLogEntry``

### Older and Embedded Clients

- <doc:SupportingOlderClients>
- ``FTPLegacyClientOptions``

### Networking

- ``IPAddressHelper``

### Errors

- ``FTPServerError``
