# FTPServerKit

A lightweight, read-only FTP server for iOS and macOS apps, built on Network.framework with no dependencies.

Use it to share files from your app with any FTP client on the local network: FileZilla, Cyberduck, Finder, curl, or embedded devices that download files over FTP.

## Features

- Serves a whole directory (including subdirectories) or a single file, or your own source through the `FTPFileProvider` protocol
- Passive mode (PASV and EPSV), resume (REST), SIZE and MDTM
- Files are streamed in chunks, so large files aren't loaded into memory
- Username and password or anonymous login
- `async` start that reports errors such as a port already in use
- Server events on the main actor through a delegate, plus a log handler
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

## Usage

### Serve a directory

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

`start()` returns once clients can connect and throws `FTPServerError` when the server can't listen, for example because the port is in use. Pass port `0` to let the system pick a free port. There's also `start(completion:)` for code that doesn't use `async`.

Files added to or removed from the directory while the server runs are picked up right away. Clients can't reach anything outside the directory, also not through symbolic links. Hidden files are left out unless you pass `includesHiddenFiles: true`.

### Serve a single file

```swift
let file = Bundle.main.url(forResource: "file", withExtension: "bin")!

let server = FTPServer(
    configuration: FTPServerConfiguration(authentication: .anonymous),
    fileProvider: FTPSingleFileProvider(fileURL: file)
)
```

The file is listed alone in the root directory. Pass `fileName:` to serve it under another name. You can replace `server.fileProvider` at any time, also while the server runs.

### Configuration

| Option | Default | Description |
| --- | --- | --- |
| `port` | `2121` | Port for the control connection; `0` picks a free port |
| `authentication` | required | `.anonymous` or `.credentials(username:password:)` |
| `welcomeMessage` | `"FTP Server Ready"` | Text sent with the `220` greeting |
| `maximumConnections` | `10` | Further clients get `421` and are disconnected |
| `dataConnectionTimeout` | `5` | Seconds LIST, NLST and RETR wait for the client to open the data connection |
| `bindsToLoopbackOnly` | `false` | Accept connections from the same device only |
| `legacyClientOptions` | `.none` | Workarounds for older clients, see below |
| `logHandler` | `nil` | Receives every log line |

### Older and embedded clients

Some FTP clients, often in embedded devices, don't follow the FTP spec. `FTPLegacyClientOptions` has workarounds for two known cases; both are off by default:

```swift
var configuration = FTPServerConfiguration(authentication: .anonymous)
configuration.legacyClientOptions = FTPLegacyClientOptions(
    transferCompletionDelay: 30,     // keep the data connection open 30 s after the last byte
    keepsPassiveListenerOpen: true   // allow REST + RETR on the same passive port without a new PASV
)
```

Only turn these on for clients that need them. With `transferCompletionDelay` above 20 seconds, clients such as FileZilla time out before the transfer completes.

### Events

Set a delegate to follow what the server does. All methods are optional and called on the main actor:

```swift
@MainActor
final class ServerModel: ObservableObject, FTPServerDelegate {
    @Published var lastCommand = ""

    func ftpServer(_ server: FTPServer, didStartOnPort port: UInt16) {}
    func ftpServerDidStop(_ server: FTPServer, error: (any Error)?) {}

    func ftpServer(_ server: FTPServer, didReceiveCommand command: String, argument: String) {
        lastCommand = "\(command) \(argument)" // PASS arguments are masked
    }
}

server.delegate = model // held weakly
```

### Logging

The server writes to the unified log with subsystem `FTPServerKit`. To collect the lines yourself, for example to attach a client's session to a crash report, set a log handler. It's called on the server's internal queue:

```swift
var configuration = FTPServerConfiguration(authentication: .anonymous)
configuration.logHandler = { entry in
    guard entry.level >= .info else { return }
    print(entry) // [2026-10-01T12:00:00Z] [info] [1A2B3C4D] Sent 1048576 bytes
}
```

Each `FTPLogEntry` carries a `connectionID`, so you can group the lines per client.

### Custom file providers

Conform to `FTPFileProvider` to serve files from anywhere. Paths are always absolute and normalized, like `/` or `/folder/file.txt`:

```swift
struct MyProvider: FTPFileProvider {
    func itemInfo(atPath path: String) throws -> FTPFileInfo { … }
    func contentsOfDirectory(atPath path: String) throws -> [FTPFileInfo] { … }
    func openFile(atPath path: String, offset: UInt64) throws -> any FTPReadableFile { … }
}
```

`FileHandle` already conforms to `FTPReadableFile`. Throw `FTPFileProviderError` to answer clients with the matching `550` reply.

## Supported commands

USER, PASS, PWD, CWD, CDUP, TYPE, MODE, STRU, PASV, EPSV, LIST, NLST, RETR, SIZE, MDTM, REST, ABOR, SYST, FEAT, OPTS, NOOP and QUIT.

The server is read-only: uploads, deletes and renames get `550`. Active mode (PORT, EPRT) isn't supported, so clients have to use passive mode, which they do by default.

## Good to know

- **Plain FTP only.** There's no TLS, so usernames, passwords and files travel unencrypted. Use it on networks you trust.
- **Background.** iOS suspends an app's network listeners soon after it goes to the background. Stop the server when your app does, and start it again when the app becomes active.
- **Passive address.** PASV replies with the address the client connected to, so transfers work over Wi-Fi, Personal Hotspot, USB and VPN alike.

## Example app

`Example/FTPServerKitExample.xcodeproj` is a SwiftUI app that shares files you pick with any FTP client on the network. It uses the package from this folder and isn't part of the package product, so it's never built into apps that depend on FTPServerKit.

## Running the tests

```bash
swift test
```

The transfer tests run real downloads through `/usr/bin/curl` and only run on macOS.
