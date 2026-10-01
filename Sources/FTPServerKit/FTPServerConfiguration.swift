//
//  FTPServerConfiguration.swift
//  FTPServerKit
//
//  Created by Marc Janga on 01/10/2026.
//

import Foundation

/// Options for an ``FTPServer``.
public struct FTPServerConfiguration: Sendable {

    /// How clients log in.
    public enum Authentication: Sendable, Equatable {
        /// Any username and password are accepted.
        case anonymous
        /// Only this username and password are accepted.
        case credentials(username: String, password: String)
    }

    /// Port for the control connection. `0` lets the system pick a free port;
    /// read it from ``FTPServer/port`` once the server has started.
    public var port: UInt16

    /// How clients log in.
    public var authentication: Authentication

    /// Text sent with the `220` greeting.
    public var welcomeMessage: String

    /// Maximum number of clients connected at once. Further clients get `421` and are disconnected.
    public var maximumConnections: Int

    /// How long LIST, NLST and RETR wait for the client to open the data connection, in seconds.
    public var dataConnectionTimeout: TimeInterval

    /// Accept connections over the loopback interface only (same device or simulator).
    public var bindsToLoopbackOnly: Bool

    /// Workarounds for older FTP clients. All are off by default.
    public var legacyClientOptions: FTPLegacyClientOptions

    /// Receives every log line, on the server's internal queue.
    /// Lines are also written to the unified log (subsystem `FTPServerKit`).
    public var logHandler: (@Sendable (FTPLogEntry) -> Void)?

    public init(
        port: UInt16 = 2121,
        authentication: Authentication,
        welcomeMessage: String = "FTP Server Ready",
        maximumConnections: Int = 10,
        dataConnectionTimeout: TimeInterval = 5,
        bindsToLoopbackOnly: Bool = false,
        legacyClientOptions: FTPLegacyClientOptions = .none,
        logHandler: (@Sendable (FTPLogEntry) -> Void)? = nil
    ) {
        self.port = port
        self.authentication = authentication
        self.welcomeMessage = welcomeMessage
        self.maximumConnections = maximumConnections
        self.dataConnectionTimeout = dataConnectionTimeout
        self.bindsToLoopbackOnly = bindsToLoopbackOnly
        self.legacyClientOptions = legacyClientOptions
        self.logHandler = logHandler
    }
}

/// Workarounds for older or embedded FTP clients that don't follow the FTP spec.
///
/// Clients that follow the spec (FileZilla, Cyberduck, curl, Finder) don't need these,
/// and ``transferCompletionDelay`` makes them slower or time out, so leave them off unless a client needs them.
public struct FTPLegacyClientOptions: Sendable, Equatable {

    /// Seconds to keep the data connection open after the last byte of a RETR has been sent,
    /// before closing it and replying `226`. Gives slow clients time to drain the connection.
    ///
    /// FileZilla times out after 20 seconds by default, so it fails with values above that.
    public var transferCompletionDelay: TimeInterval

    /// Keep the passive data listener open after a transfer, so a client can reconnect to the
    /// same port for REST + RETR without sending PASV again.
    public var keepsPassiveListenerOpen: Bool

    public init(transferCompletionDelay: TimeInterval = 0, keepsPassiveListenerOpen: Bool = false) {
        self.transferCompletionDelay = transferCompletionDelay
        self.keepsPassiveListenerOpen = keepsPassiveListenerOpen
    }

    /// No workarounds.
    public static let none = FTPLegacyClientOptions()
}
