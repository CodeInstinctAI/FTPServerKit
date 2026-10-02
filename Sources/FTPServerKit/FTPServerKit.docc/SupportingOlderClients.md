# Supporting Older Clients

Turn on workarounds for older and embedded FTP clients that don't follow the FTP spec.

## Overview

Desktop clients such as FileZilla, Cyberduck, curl and Finder work with the default configuration. Some clients, often in embedded devices, behave in ways the FTP spec doesn't allow. ``FTPLegacyClientOptions`` has workarounds for two known cases. Both are off by default:

```swift
var configuration = FTPServerConfiguration(authentication: .anonymous)
configuration.legacyClientOptions = FTPLegacyClientOptions(
    transferCompletionDelay: 30,     // keep the data connection open 30 s after the last byte
    keepsPassiveListenerOpen: true   // allow REST + RETR on the same passive port without a new PASV
)
```

Only turn these on for clients that need them, because they make the server slower or incompatible with clients that follow the spec.

### Clients that lose the end of a file

Some slow clients haven't read everything yet when the server closes the data connection right after the last byte, so the end of the file gets lost. ``FTPLegacyClientOptions/transferCompletionDelay`` keeps the data connection open for that many seconds after the last byte, before the server closes it and replies `226`.

> Warning: FileZilla times out after 20 seconds by default, so it fails with a delay above that. Other clients wait for the delay on every download.

### Clients that resume without a new PASV

Clients normally send PASV before each transfer to get a new data port. Some clients resume an interrupted download with REST and RETR on the port from the previous PASV. ``FTPLegacyClientOptions/keepsPassiveListenerOpen`` keeps the passive listener open after a transfer, so those clients can reconnect to the same port.

### Find out what a client does

When a client fails and you don't know why, set a log handler and keep the ``FTPLogEntry/Level-swift.enum/debug`` lines. They show every command the client sends and every reply, so you can see where the session goes wrong. See <doc:ObservingTheServer>.
