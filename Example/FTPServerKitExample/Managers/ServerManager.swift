//
//  ServerManager.swift
//  FTPServerKitExample
//
//  Created by Marc Janga on 13/10/2025.
//

import Foundation
import Combine
import FTPServerKit

/// Manages the FTP server and the files it shares from Documents/SharedFiles
final class ServerManager: ObservableObject {
    @Published private(set) var sharedFiles: [SharedFile] = []
    @Published var errorMessage: String?
    @Published private(set) var activeServers: [ActiveServer] = []
    @Published private(set) var isStarting = false
    /// Latest commands and responses, newest first
    @Published private(set) var recentActivity: [String] = []

    static let username = "user"
    static let password = "pass"
    private static let maximumActivityLines = 50

    private let fileManager = FileManager.default
    private let sharedDirectory: URL
    private let server: FTPServer

    /// Check if any server is running
    var isRunning: Bool {
        !activeServers.isEmpty
    }

    init() {
        // Create shared directory in app's Documents folder
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        sharedDirectory = documentsPath.appendingPathComponent("SharedFiles", isDirectory: true)
        try? fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)

        // Serve the shared directory; files added or removed later are picked up right away
        server = FTPServer(
            configuration: FTPServerConfiguration(
                port: ServerType.ftp.defaultPort,
                authentication: .credentials(username: Self.username, password: Self.password)
            ),
            fileProvider: FTPDirectoryProvider(rootURL: sharedDirectory)
        )
        server.delegate = self

        loadSharedFiles()
    }

    /// Start the FTP server
    func startServer() {
        guard !isRunning, !isStarting else { return }
        isStarting = true

        Task {
            defer { isStarting = false }
            do {
                let port = try await server.start()
                let connectionInfo = ServerConnectionInfo.ftp(
                    ipAddress: IPAddressHelper.getLocalIPAddress(),
                    port: port,
                    username: Self.username,
                    password: Self.password
                )
                activeServers = [ActiveServer(connectionInfo: connectionInfo)]
                errorMessage = nil
            } catch {
                errorMessage = "Failed to start FTP server: \(error.localizedDescription)"
            }
        }
    }

    /// Stop the FTP server
    func stopServer() {
        server.stop()
        activeServers.removeAll()
    }

    /// Get connection info for the FTP server
    func getConnectionInfo() -> ServerConnectionInfo? {
        return activeServers.first?.connectionInfo
    }

    /// Add a file to the shared directory
    func addFile(from sourceURL: URL) {
        let fileName = sourceURL.lastPathComponent
        let destinationURL = sharedDirectory.appendingPathComponent(fileName)

        do {
            // If file already exists, remove it first
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // Copy file to shared directory
            if sourceURL.startAccessingSecurityScopedResource() {
                defer { sourceURL.stopAccessingSecurityScopedResource() }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } else {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }

            loadSharedFiles()
        } catch {
            errorMessage = "Failed to add file: \(error.localizedDescription)"
        }
    }

    /// Remove a file from the shared directory
    func removeFile(_ file: SharedFile) {
        do {
            try fileManager.removeItem(at: file.url)
            loadSharedFiles()
        } catch {
            errorMessage = "Failed to remove file: \(error.localizedDescription)"
        }
    }

    /// Load all files from the shared directory
    private func loadSharedFiles() {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: sharedDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )

            sharedFiles = fileURLs.map { SharedFile(url: $0) }
                .sorted { $0.dateAdded > $1.dateAdded }
        } catch {
            sharedFiles = []
        }
    }

    private func appendActivity(_ line: String) {
        recentActivity.insert(line, at: 0)
        if recentActivity.count > Self.maximumActivityLines {
            recentActivity.removeLast()
        }
    }
}

// MARK: - FTPServerDelegate

extension ServerManager: FTPServerDelegate {
    func ftpServerDidStop(_ server: FTPServer, error: (any Error)?) {
        activeServers.removeAll()
        if let error {
            errorMessage = "FTP server stopped: \(error.localizedDescription)"
        }
    }

    func ftpServer(_ server: FTPServer, didReceiveCommand command: String, argument: String) {
        appendActivity("→ \(command) \(argument)")
    }

    func ftpServer(_ server: FTPServer, didSendResponse response: String) {
        appendActivity("← \(response)")
    }
}
