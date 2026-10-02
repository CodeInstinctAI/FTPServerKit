//
//  ServerConnectionInfo.swift
//  FTPServerKitExample
//
//  Created by Marc Janga on 13/10/2025.
//

import Foundation

/// Enum representing different server types
enum ServerType: String, CaseIterable, Identifiable {
    case ftp = "FTP"

    var id: String { rawValue }

    /// Default port for this server type
    var defaultPort: UInt16 {
        return 2121
    }

    /// Icon name for this server type
    var iconName: String {
        return "folder.badge.gearshape"
    }

    /// Description for UI display
    var description: String {
        return "FTP client access"
    }
}

/// Connection information for a specific server
struct ServerConnectionInfo: Identifiable {
    let id = UUID()
    let serverType: ServerType
    let url: String
    let port: UInt16
    let ipAddress: String?
    let credentials: ServerCredentials?
    let instructions: String

    /// Credentials for server access (if required)
    struct ServerCredentials {
        let username: String
        let password: String
    }

    /// Create connection info for FTP server
    static func ftp(ipAddress: String?, port: UInt16, username: String, password: String) -> ServerConnectionInfo {
        let url = ipAddress.map { "ftp://\($0):\(port)" } ?? "Not available"
        let instructions = """
        Use an FTP client (like FileZilla, Cyberduck, or Finder) to connect:

        Host: \(ipAddress ?? "N/A")
        Port: \(port)
        Username: \(username)
        Password: \(password)

        For macOS Finder:
        1. Press Cmd+K
        2. Enter: \(url)
        3. Click Connect
        4. Enter username and password
        """

        return ServerConnectionInfo(
            serverType: .ftp,
            url: url,
            port: port,
            ipAddress: ipAddress,
            credentials: ServerCredentials(username: username, password: password),
            instructions: instructions
        )
    }
}

/// Active server instance information
struct ActiveServer: Identifiable {
    let id = UUID()
    let connectionInfo: ServerConnectionInfo

    var serverType: ServerType {
        connectionInfo.serverType
    }
}
