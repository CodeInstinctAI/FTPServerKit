# Observing the Server

Follow what the server and its clients do, through events, a delegate or log lines.

## Overview

The server sends the same ``FTPServerEvent`` values through three channels, so it fits any codebase:

- ``FTPServer/events``, an `AsyncStream`, for Swift concurrency and SwiftUI.
- ``FTPServer/eventPublisher``, for code built on Combine.
- ``FTPServer/delegate``, an ``FTPServerDelegate`` called on the main actor.

You can use them together. Separately, a log handler receives every log line the server writes.

The events are:

| Event | Sent when |
| --- | --- |
| ``FTPServerEvent/started(port:)`` | The server is listening and accepting clients |
| ``FTPServerEvent/stopped(error:)`` | The server stopped; `error` is `nil` after ``FTPServer/stop()`` |
| ``FTPServerEvent/receivedCommand(_:argument:connectionID:)`` | A client sent a command; PASS arguments are masked |
| ``FTPServerEvent/sentResponse(_:connectionID:)`` | The server replied to a client |
| ``FTPServerEvent/failed(_:connectionID:)`` | Sending a reply or a file to a client failed |

Client events carry a `connectionID`, the same as in ``FTPLogEntry``, so you can tell clients apart when several are connected.

### Iterate the event stream

Each read of ``FTPServer/events`` returns a new stream, so several parts of your app can listen at once. A stream only gets events from the moment you create it, lasts across restarts, and finishes when the server is released. Cancel the iterating task to stop listening earlier:

```swift
struct ActivityView: View {
    let server: FTPServer
    @State private var lastCommand = ""

    var body: some View {
        Text(lastCommand)
            .task { // cancelled when the view disappears
                for await event in server.events {
                    switch event {
                    case .receivedCommand(let command, let argument, _):
                        lastCommand = "\(command) \(argument)"
                    case .stopped(let error?):
                        print("Server stopped: \(error)")
                    default:
                        break
                    }
                }
            }
    }
}
```

### Subscribe with Combine

``FTPServer/eventPublisher`` sends the same events. Subscribers only get events sent after they subscribe. Events arrive on the server's internal queue, so receive them on the main queue before updating UI:

```swift
server.eventPublisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] event in
        if case .receivedCommand(let command, let argument, _) = event {
            self?.lastCommand = "\(command) \(argument)"
        }
    }
    .store(in: &cancellables)
```

### Set a delegate

An ``FTPServerDelegate`` gets the same events, without the connection ID. All methods are optional and called on the main actor. The server holds its delegate weakly:

```swift
@MainActor
final class ServerModel: ObservableObject, FTPServerDelegate {
    @Published var lastCommand = ""

    func ftpServer(_ server: FTPServer, didReceiveCommand command: String, argument: String) {
        lastCommand = "\(command) \(argument)"
    }

    func ftpServerDidStop(_ server: FTPServer, error: (any Error)?) {
        if let error { print("Server stopped: \(error)") }
    }
}

server.delegate = model
```

### Collect log lines

The server writes to the unified log with subsystem `FTPServerKit`, so you can follow it in Console. To collect the lines yourself, for example to attach a client's session to a crash report, set ``FTPServerConfiguration/logHandler``. It's called on the server's internal queue:

```swift
var configuration = FTPServerConfiguration(authentication: .anonymous)
configuration.logHandler = { entry in
    guard entry.level >= .info else { return }
    print(entry) // [2026-10-01T12:00:00Z] [info] [1A2B3C4D] Sent 1048576 bytes
}
```

Each ``FTPLogEntry`` carries a ``FTPLogEntry/connectionID``, so you can group the lines per client. Lines at ``FTPLogEntry/Level-swift.enum/debug`` include every command and reply.
