# Getting Started

Add FTPServerKit to your app and share a directory or a file with FTP clients on the network.

## Overview

You create an ``FTPServer`` with a configuration and a file provider, start it, and show the user the address to connect to. Clients log in, browse and download until you stop the server.

### Add the package

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

### Serve a directory

``FTPDirectoryProvider`` serves a directory and its subdirectories:

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
```

``FTPServer/start()`` returns once clients can connect. It throws ``FTPServerError`` when the server can't listen, for example because the port is in use. Pass port `0` to let the system pick a free port. Use ``FTPServer/start(completion:)`` in code that doesn't use `async`.

Files added to or removed from the directory while the server runs are picked up right away. Clients can't reach anything outside the directory, also not through symbolic links. Hidden files are left out unless you pass `includesHiddenFiles: true`.

### Serve a single file

``FTPSingleFileProvider`` lists one file alone in the root directory:

```swift
let file = Bundle.main.url(forResource: "file", withExtension: "bin")!

let server = FTPServer(
    configuration: FTPServerConfiguration(authentication: .anonymous),
    fileProvider: FTPSingleFileProvider(fileURL: file)
)
```

Pass `fileName:` to serve the file under another name. You can replace ``FTPServer/fileProvider`` at any time, also while the server runs. The next command a client sends uses the new provider.

### Configure the server

``FTPServerConfiguration`` holds the server's options. Only `authentication` is required:

| Option | Default | Description |
| --- | --- | --- |
| ``FTPServerConfiguration/port`` | `2121` | Port for the control connection; `0` picks a free port |
| ``FTPServerConfiguration/authentication`` | required | `.anonymous` or `.credentials(username:password:)` |
| ``FTPServerConfiguration/welcomeMessage`` | `"FTP Server Ready"` | Text sent with the `220` greeting |
| ``FTPServerConfiguration/maximumConnections`` | `10` | Further clients get `421` and are disconnected |
| ``FTPServerConfiguration/dataConnectionTimeout`` | `5` | Seconds LIST, NLST and RETR wait for the client to open the data connection |
| ``FTPServerConfiguration/bindsToLoopbackOnly`` | `false` | Accept connections from the same device only |
| ``FTPServerConfiguration/legacyClientOptions`` | `.none` | Workarounds for older clients, see <doc:SupportingOlderClients> |
| ``FTPServerConfiguration/logHandler`` | `nil` | Receives every log line, see <doc:ObservingTheServer> |

### Stop the server

Call ``FTPServer/stop()`` to disconnect every client and stop listening. You can start the server again afterwards.

iOS suspends an app's network listeners soon after it goes to the background. Stop the server when your app does, and start it again when the app becomes active:

```swift
.onChange(of: scenePhase) { _, phase in
    switch phase {
    case .active:
        Task { try? await server.start() }
    case .background:
        server.stop()
    default:
        break
    }
}
```

### Connect from a client

PASV replies with the address the client connected to, so transfers work over Wi-Fi, Personal Hotspot, USB and VPN alike. ``IPAddressHelper/getLocalIPAddress()`` returns the Wi-Fi or Personal Hotspot address to show to the user.

The package includes an example app, `Example/FTPServerKitExample.xcodeproj`, a SwiftUI app that shares the files you pick with any FTP client on the network.
