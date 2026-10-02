//
//  FTPServerEvent.swift
//  FTPServerKit
//
//  Created by Marc Janga on 02/10/2026.
//

import Foundation

/// Something an ``FTPServer`` did, delivered through ``FTPServer/events``.
/// Each case matches an ``FTPServerDelegate`` method.
///
/// Client events carry the `connectionID` of the client they belong to, the same ID as in ``FTPLogEntry``.
/// Group by it to follow one client when several are connected.
public enum FTPServerEvent: Sendable {
    /// The server is listening and accepting clients.
    case started(port: UInt16)
    /// The server stopped: `error` is `nil` after ``FTPServer/stop()``, or the reason the listener failed.
    case stopped(error: (any Error)?)
    /// A client sent a command. The PASS argument is masked.
    case receivedCommand(String, argument: String, connectionID: UUID)
    /// The server replied to a client, without the trailing CRLF.
    case sentResponse(String, connectionID: UUID)
    /// Sending a reply or a file to a client failed.
    case failed(any Error, connectionID: UUID)
}

extension FTPServerEvent {
    /// Calls the delegate method that matches the event.
    @MainActor
    func deliver(to delegate: any FTPServerDelegate, from server: FTPServer) {
        switch self {
        case .started(let port):
            delegate.ftpServer(server, didStartOnPort: port)
        case .stopped(let error):
            delegate.ftpServerDidStop(server, error: error)
        case .receivedCommand(let command, let argument, _):
            delegate.ftpServer(server, didReceiveCommand: command, argument: argument)
        case .sentResponse(let response, _):
            delegate.ftpServer(server, didSendResponse: response)
        case .failed(let error, _):
            delegate.ftpServer(server, didFailWithError: error)
        }
    }
}
