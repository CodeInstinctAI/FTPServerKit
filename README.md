# FTPServerKit

A lightweight, read-only FTP server for iOS and macOS apps, built on Network.framework with no dependencies.

Use it to share files from your app with any FTP client on the local network: FileZilla, Cyberduck, Finder, curl, or embedded devices that download files over FTP.

## Features

- Serves a whole directory (including subdirectories) or a single file, or your own source through the `FTPFileProvider` protocol
- Passive mode (PASV and EPSV), resume (REST), SIZE and MDTM
- Files are streamed in chunks, so large files aren't loaded into memory
- Username and password or anonymous login
- `async` start that reports errors such as a port already in use
- Server events as an `AsyncStream`, a Combine publisher or a delegate, so it fits any codebase, plus a log handler
- Opt-in workarounds for older and embedded FTP clients
- Swift 6 language mode, safe to use from any thread

## Requirements

- iOS 15 or macOS 12
- Swift 6 (Xcode 16 or later)

## Installation

Add the package in Xcode with **File → Add Package Dependencies…**, or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/FTPServerKit.git", branch: "main"),
],
targets: [
    .target(name: "MyApp", dependencies: ["FTPServerKit"]),
]
```

On iOS, add `NSLocalNetworkUsageDescription` to your app's Info.plist. iOS shows its text when it asks the user for local network access.

## Quick start

```swift
import FTPServerKit

let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

let server = FTPServer(
    configuration: FTPServerConfiguration(
        port: 2121,
        authentication: .credentials(username: "user", password: "pass")
    ),
    fileProvider: FTPDirectoryProvider(rootURL: documents)
)

let port = try await server.start()
let address = IPAddressHelper.getLocalIPAddress() ?? "localhost"
print("Connect to ftp://\(address):\(port)")

// Later
server.stop()
```

Use `FTPSingleFileProvider(fileURL:)` to serve a single file instead.

## Documentation

The full documentation is on the [Swift Package Index](https://swiftpackageindex.com/<owner>/FTPServerKit/documentation/ftpserverkit). You can also build it in Xcode with **Product → Build Documentation**.

- [Getting Started](https://swiftpackageindex.com/<owner>/FTPServerKit/documentation/ftpserverkit/gettingstarted): serving a directory or a file, configuration, and running in the background
- [Observing the Server](https://swiftpackageindex.com/<owner>/FTPServerKit/documentation/ftpserverkit/observingtheserver): events as an `AsyncStream`, a Combine publisher or a delegate, and log lines
- [Writing a Custom File Provider](https://swiftpackageindex.com/<owner>/FTPServerKit/documentation/ftpserverkit/customfileproviders): serving files from memory or anywhere else
- [Supporting Older Clients](https://swiftpackageindex.com/<owner>/FTPServerKit/documentation/ftpserverkit/supportingolderclients): workarounds for embedded clients that don't follow the FTP spec

## Good to know

- **Read-only.** Uploads, deletes and renames get `550`. Clients have to use passive mode, which they do by default.
- **Plain FTP only.** There's no TLS, so usernames, passwords and files travel unencrypted. Use it on networks you trust.
- **Background.** iOS suspends an app's network listeners soon after it goes to the background. Stop the server when your app does, and start it again when the app becomes active.

## Example app

`Example/FTPServerKitExample.xcodeproj` is a SwiftUI app that shares files you pick with any FTP client on the network. It uses the package from this folder and isn't part of the package product, so it's never built into apps that depend on FTPServerKit.

## Running the tests

```bash
swift test
```

The transfer tests run real downloads through `/usr/bin/curl` and only run on macOS.

## License

FTPServerKit is available under the MIT license. See [LICENSE](LICENSE) for details.
