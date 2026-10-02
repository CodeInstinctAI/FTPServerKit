//
//  FTPServerDelegate.swift
//  FTPServerKit
//
//  Created by Marc Janga on 11/11/2025.
//

import Foundation

/// Receives ``FTPServer`` events on the main actor. Every method has an empty default implementation.
@MainActor
public protocol FTPServerDelegate: AnyObject, Sendable {
    /// The server is listening and accepting clients.
    func ftpServer(_ server: FTPServer, didStartOnPort port: UInt16)
    /// The server stopped: `error` is `nil` after ``FTPServer/stop()``, or the reason the listener failed.
    func ftpServerDidStop(_ server: FTPServer, error: (any Error)?)
    /// A client sent a command. The PASS argument is masked.
    func ftpServer(_ server: FTPServer, didReceiveCommand command: String, argument: String)
    /// The server replied to a client, without the trailing CRLF.
    func ftpServer(_ server: FTPServer, didSendResponse response: String)
    /// Sending a reply or a file to a client failed.
    func ftpServer(_ server: FTPServer, didFailWithError error: any Error)
}

public extension FTPServerDelegate {
    func ftpServer(_ server: FTPServer, didStartOnPort port: UInt16) {}
    func ftpServerDidStop(_ server: FTPServer, error: (any Error)?) {}
    func ftpServer(_ server: FTPServer, didReceiveCommand command: String, argument: String) {}
    func ftpServer(_ server: FTPServer, didSendResponse response: String) {}
    func ftpServer(_ server: FTPServer, didFailWithError error: any Error) {}
}

/// One log line from an ``FTPServer``, passed to ``FTPServerConfiguration/logHandler``.
public struct FTPLogEntry: Sendable, CustomStringConvertible {

    /// How important a log line is. Levels compare, so you can filter with `entry.level >= .info`.
    public enum Level: Int, Sendable, Comparable, CustomStringConvertible {
        /// Every command and reply, and data connection details, for tracing one client's session.
        case debug
        /// Connections, transfers, and the server starting and stopping.
        case info
        /// Something the server recovered from, such as a refused connection, a timeout or a missing file.
        case warning
        /// The server or a transfer failed.
        case error

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var description: String {
            switch self {
            case .debug: "debug"
            case .info: "info"
            case .warning: "warning"
            case .error: "error"
            }
        }
    }

    /// When the line was logged.
    public let date: Date
    /// How important the line is.
    public let level: Level
    /// The client connection the line belongs to, or `nil` for server-wide lines.
    /// Group by it to rebuild one client's session, for example to attach to a crash report.
    public let connectionID: UUID?
    /// The text of the line.
    public let message: String

    /// The line as `[date] [level] [connection] message`, with the first 8 characters of the connection ID.
    public var description: String {
        let connection = connectionID.map { " [\($0.uuidString.prefix(8))]" } ?? ""
        return "[\(date.formatted(.iso8601))] [\(level)]\(connection) \(message)"
    }
}
