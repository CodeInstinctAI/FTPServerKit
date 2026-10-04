//
//  FTPSession.swift
//  FTPServerKit
//
//  Created by Marc Janga on 11/11/2025.
//

import Foundation
import Network

/// One client's control connection, plus the data connection it opens with PASV or EPSV.
final class FTPSession: @unchecked Sendable {
    // Unchecked: every property is only touched on the server's queue.

    let id = UUID()
    var onClose: ((FTPSession) -> Void)?

    private let connection: NWConnection
    private weak var server: FTPServer?
    private let configuration: FTPServerConfiguration
    private let queue: DispatchQueue

    private var receiveBuffer = Data()
    private var isClosed = false
    private var isAuthenticated = false
    private var pendingUsername: String?
    private var currentDirectory = "/"
    private var transferType = TransferType.ascii
    private var restartOffset: UInt64 = 0 // byte offset for REST

    private var dataListener: NWListener? // passive listener, one per session
    private var passiveReplySent = false
    private var dataConnection: NWConnection?
    private var dataConnectionWaiter: DataConnectionWaiter?
    private var activeTransfer: DataTransfer?

    private static let chunkSize = 64 * 1024
    private static let maximumCommandLength = 4096
    private static let commandsAllowedBeforeLogin: Set<String> = ["USER", "PASS", "QUIT", "SYST", "FEAT", "NOOP", "OPTS", "AUTH"]

    private enum TransferType {
        case ascii, binary
    }

    private struct DataConnectionWaiter {
        let id = UUID()
        let handler: (NWConnection?) -> Void
    }

    private final class DataTransfer: @unchecked Sendable {
        // Unchecked: only touched on the server's queue.
        let connection: NWConnection
        /// The passive listener the connection came from, so a newer PASV's listener isn't closed with it.
        let listener: NWListener?
        private(set) var file: (any FTPReadableFile)?
        var bytesSent: UInt64 = 0

        init(connection: NWConnection, listener: NWListener?, file: (any FTPReadableFile)?) {
            self.connection = connection
            self.listener = listener
            self.file = file
        }

        /// Closes the file once, however many of completion, failure, ABOR and session close happen.
        func closeFile() {
            try? file?.close()
            file = nil
        }
    }

    init(connection: NWConnection, server: FTPServer, configuration: FTPServerConfiguration, queue: DispatchQueue) {
        self.connection = connection
        self.server = server
        self.configuration = configuration
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.log(.warning, "Control connection failed: \(error)")
                self?.close()
            }
        }
        connection.start(queue: queue)
        reply(220, configuration.welcomeMessage)
        receiveNext()
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true

        if let transfer = activeTransfer {
            activeTransfer = nil
            transfer.closeFile()
            transfer.connection.cancel()
        }
        dataConnectionWaiter = nil
        dataConnection?.cancel()
        dataConnection = nil
        dataListener?.cancel()
        dataListener = nil
        connection.cancel()

        log(.info, "Connection closed")
        onClose?(self)
        onClose = nil
    }

    // MARK: - Command Receiving

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                self.consume(data)
            }
            if isComplete || error != nil {
                self.close()
            } else if !self.isClosed {
                self.receiveNext()
            }
        }
    }

    /// Buffers incoming bytes and handles each complete line, so a command split across TCP segments is read whole.
    private func consume(_ data: Data) {
        receiveBuffer.append(data)
        while !isClosed, let newline = receiveBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: receiveBuffer[receiveBuffer.startIndex..<newline], as: UTF8.self)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...newline)
            handle(line: line)
        }
        if receiveBuffer.count > Self.maximumCommandLength {
            receiveBuffer.removeAll()
            reply(500, "Command line too long")
        }
    }

    // MARK: - Command Handling

    private func handle(line rawLine: String) {
        // Drops the line ending, and Telnet control bytes some clients send before ABOR.
        let line = rawLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { !($0.isASCII && $0.isLetter) }
        guard !line.isEmpty else { return }

        let command: String
        let argument: String
        if let space = line.firstIndex(of: " ") {
            command = line[..<space].uppercased()
            argument = String(line[line.index(after: space)...])
        } else {
            command = line.uppercased()
            argument = ""
        }

        let loggedArgument = command == "PASS" ? "****" : argument
        log(.debug, "> \(command) \(loggedArgument)")
        server?.emit(.receivedCommand(command, argument: loggedArgument, connectionID: id))

        guard isAuthenticated || Self.commandsAllowedBeforeLogin.contains(command) else {
            reply(530, "Not logged in")
            return
        }

        switch command {
        case "USER":
            handleUSER(argument)
        case "PASS":
            handlePASS(argument)
        case "PWD", "XPWD":
            reply(257, "\(quoted(currentDirectory)) is current directory")
        case "CWD", "XCWD":
            handleCWD(argument)
        case "CDUP", "XCUP":
            handleCWD("..")
        case "TYPE":
            handleTYPE(argument)
        case "MODE":
            argument.uppercased() == "S" ? reply(200, "Mode set to S") : reply(504, "Only stream mode is supported")
        case "STRU":
            argument.uppercased() == "F" ? reply(200, "Structure set to F") : reply(504, "Only file structure is supported")
        case "PASV":
            openPassiveListener(extended: false)
        case "EPSV":
            argument.uppercased() == "ALL" ? reply(200, "EPSV ALL ok") : openPassiveListener(extended: true)
        case "LIST":
            handleLIST(argument, namesOnly: false)
        case "NLST":
            handleLIST(argument, namesOnly: true)
        case "RETR":
            handleRETR(argument)
        case "SIZE":
            handleSIZE(argument)
        case "MDTM":
            handleMDTM(argument)
        case "REST":
            handleREST(argument)
        case "ABOR":
            handleABOR()
        case "SYST":
            reply(215, "UNIX Type: L8")
        case "FEAT":
            replyMultiline(211, header: "Features:", lines: ["EPSV", "MDTM", "PASV", "REST STREAM", "SIZE", "UTF8"], footer: "End")
        case "OPTS":
            argument.uppercased().hasPrefix("UTF8") ? reply(200, "UTF8 mode always enabled") : reply(501, "Option not understood")
        case "NOOP":
            reply(200, "OK")
        case "QUIT":
            handleQUIT()
        case "PORT", "EPRT":
            reply(502, "Active mode not supported, use PASV or EPSV")
        case "STOR", "STOU", "APPE", "DELE", "MKD", "XMKD", "RMD", "XRMD", "RNFR", "RNTO":
            reply(550, "Permission denied: server is read-only")
        default:
            reply(502, "Command not implemented")
        }
    }

    // MARK: - FTP Command Implementations

    private func handleUSER(_ username: String) {
        pendingUsername = username
        isAuthenticated = false
        if configuration.authentication == .anonymous {
            reply(331, "Anonymous login ok, send any password")
        } else {
            reply(331, "Password required for \(username)")
        }
    }

    private func handlePASS(_ password: String) {
        guard let username = pendingUsername else {
            reply(503, "Login with USER first")
            return
        }

        switch configuration.authentication {
        case .anonymous:
            isAuthenticated = true
        case .credentials(let expectedUsername, let expectedPassword):
            isAuthenticated = username == expectedUsername && password == expectedPassword
        }

        if isAuthenticated {
            reply(230, "User logged in")
        } else {
            reply(530, "Login incorrect")
        }
    }

    private func handleCWD(_ argument: String) {
        guard !argument.isEmpty else {
            reply(501, "Syntax error: directory name required")
            return
        }

        let path = FTPPath.resolve(argument, from: currentDirectory)
        do {
            guard try fileProvider.itemInfo(atPath: path).isDirectory else {
                throw FTPFileProviderError.notADirectory
            }
            currentDirectory = path
            reply(250, "Directory changed to \(path)")
        } catch {
            replyFailure(error, path: path)
        }
    }

    private func handleTYPE(_ argument: String) {
        switch argument.uppercased().first {
        case "A":
            transferType = .ascii
            reply(200, "Type set to A")
        case "I", "L":
            transferType = .binary
            reply(200, "Type set to I")
        default:
            reply(504, "Type not supported")
        }
    }

    private func handleLIST(_ argument: String, namesOnly: Bool) {
        // Clients often send ls flags such as "-la"; they aren't part of the path.
        var pathArgument = Substring(argument)
        while pathArgument.hasPrefix("-") {
            pathArgument = pathArgument.drop { $0 != " " }.drop { $0 == " " }
        }

        let path = FTPPath.resolve(String(pathArgument), from: currentDirectory)
        let entries: [FTPFileInfo]
        do {
            let provider = try fileProvider
            let item = try provider.itemInfo(atPath: path)
            entries = item.isDirectory ? try provider.contentsOfDirectory(atPath: path) : [item]
        } catch {
            replyFailure(error, path: path)
            return
        }

        guard hasDataChannel else {
            reply(425, "Use PASV or EPSV first")
            return
        }

        let listing = entries
            .map { (namesOnly ? $0.name : FTPListFormatter.line(for: $0)) + "\r\n" }
            .joined()
        reply(150, namesOnly ? "Opening data connection for name list" : "Opening data connection for file listing")

        withDataConnection { [weak self] connection in
            guard let self else { return }
            guard let connection else {
                self.reply(425, "Can't open data connection")
                return
            }
            self.sendListing(Data(listing.utf8), over: connection)
        }
    }

    private func handleRETR(_ argument: String) {
        guard !argument.isEmpty else {
            reply(501, "Syntax error: file name required")
            return
        }

        let path = FTPPath.resolve(argument, from: currentDirectory)
        // A REST marker only applies to the next RETR.
        let offset = restartOffset
        restartOffset = 0

        let item: FTPFileInfo
        let file: any FTPReadableFile
        do {
            let provider = try fileProvider
            item = try provider.itemInfo(atPath: path)
            guard !item.isDirectory else {
                throw FTPFileProviderError.isADirectory
            }
            guard offset <= item.size else {
                reply(554, "Restart offset \(offset) is beyond the end of the file")
                return
            }
            guard hasDataChannel else {
                reply(425, "Use PASV or EPSV first")
                return
            }
            file = try provider.openFile(atPath: path, offset: offset)
        } catch {
            replyFailure(error, path: path)
            return
        }

        let mode = transferType == .binary ? "BINARY" : "ASCII"
        reply(150, "Opening \(mode) mode data connection for \(item.name) (\(item.size - offset) bytes)")
        log(.info, "Sending \(path) from offset \(offset)")

        // With keepsPassiveListenerOpen the client may only now reconnect to the earlier passive port.
        withDataConnection { [weak self] connection in
            guard let self else { return }
            guard let connection else {
                try? file.close()
                self.log(.warning, "Data connection not established for \(path)")
                self.reply(425, "Can't open data connection")
                return
            }
            let transfer = DataTransfer(connection: connection, listener: self.dataListener, file: file)
            self.activeTransfer = transfer
            self.sendNextChunk(of: transfer)
        }
    }

    private func handleSIZE(_ argument: String) {
        // SIZE command only works in binary mode (RFC 3659)
        guard transferType == .binary else {
            reply(550, "SIZE not allowed in ASCII mode")
            return
        }
        guard !argument.isEmpty else {
            reply(501, "Syntax error: file name required")
            return
        }

        let path = FTPPath.resolve(argument, from: currentDirectory)
        do {
            let item = try fileProvider.itemInfo(atPath: path)
            guard !item.isDirectory else {
                throw FTPFileProviderError.isADirectory
            }
            reply(213, "\(item.size)")
        } catch {
            replyFailure(error, path: path)
        }
    }

    private func handleMDTM(_ argument: String) {
        guard !argument.isEmpty else {
            reply(501, "Syntax error: file name required")
            return
        }

        let path = FTPPath.resolve(argument, from: currentDirectory)
        do {
            let item = try fileProvider.itemInfo(atPath: path)
            reply(213, FTPListFormatter.timestamp(item.modificationDate))
        } catch {
            replyFailure(error, path: path)
        }
    }

    private func handleREST(_ argument: String) {
        // Only decimal byte offsets are accepted
        guard let offset = UInt64(argument.trimmingCharacters(in: .whitespaces)) else {
            restartOffset = 0
            reply(501, "Invalid restart marker")
            return
        }
        restartOffset = offset
        reply(350, "Restarting at \(offset). Send RETR to initiate transfer.")
    }

    private func handleABOR() {
        restartOffset = 0
        if let transfer = activeTransfer {
            activeTransfer = nil
            transfer.closeFile()
            release(transfer)
            reply(426, "Transfer aborted")
            reply(226, "ABOR command successful")
        } else {
            dataConnectionWaiter = nil
            reply(225, "No transfer to abort")
        }
    }

    private func handleQUIT() {
        restartOffset = 0
        reply(221, "Goodbye") { [weak self] in
            self?.close()
        }
    }

    // MARK: - Passive Mode

    private var hasDataChannel: Bool {
        dataListener != nil || dataConnection != nil
    }

    private func openPassiveListener(extended: Bool) {
        closeDataChannel()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            log(.error, "Couldn't create passive listener: \(error)")
            reply(425, "Can't open passive connection: \(error.localizedDescription)")
            return
        }

        listener.newConnectionHandler = { [weak self, weak listener] connection in
            guard let self, let listener else {
                connection.cancel()
                return
            }
            self.acceptDataConnection(connection, from: listener)
        }
        // Waits for the listener to be ready before reading its port.
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener else { return }
            self.passiveListener(listener, didChangeState: state, extended: extended)
        }

        dataListener = listener
        passiveReplySent = false
        listener.start(queue: queue)
    }

    private func passiveListener(_ listener: NWListener, didChangeState state: NWListener.State, extended: Bool) {
        guard listener === dataListener else { return }

        switch state {
        case .ready:
            guard !passiveReplySent, let port = listener.port?.rawValue else { return }
            passiveReplySent = true
            log(.debug, "Passive listener on port \(port)")

            if extended {
                reply(229, "Entering Extended Passive Mode (|||\(port)|)")
            } else if let address = passiveIPv4Address() {
                let octets = address.rawValue.map(String.init).joined(separator: ",")
                reply(227, "Entering Passive Mode (\(octets),\(port / 256),\(port % 256))")
            } else {
                closeDataChannel()
                reply(425, "Can't determine an IPv4 address, use EPSV")
            }

        case .failed(let error):
            log(.error, "Passive listener failed: \(error)")
            closeDataChannel()
            if !passiveReplySent {
                reply(425, "Can't open passive connection: \(error.localizedDescription)")
            }

        default:
            break
        }
    }

    /// The address the client reached this device on, so PASV works over Wi-Fi, hotspot, USB or VPN alike.
    private func passiveIPv4Address() -> IPv4Address? {
        if case .hostPort(let host, _) = connection.currentPath?.localEndpoint {
            switch host {
            case .ipv4(let address):
                return address
            case .ipv6(let address):
                if let address = address.asIPv4 {
                    return address
                }
            default:
                break
            }
        }
        return IPAddressHelper.getLocalIPAddress().flatMap { IPv4Address($0) }
    }

    private func acceptDataConnection(_ connection: NWConnection, from listener: NWListener) {
        guard listener === dataListener, !isClosed else {
            connection.cancel()
            return
        }

        log(.debug, "Data connection from \(connection.endpoint)")
        // Cancel any existing data connection before accepting the new one
        dataConnection?.cancel()
        dataConnection = connection
        connection.start(queue: queue)

        if let waiter = dataConnectionWaiter {
            dataConnectionWaiter = nil
            waiter.handler(connection)
        }
    }

    /// Calls `handler` with the data connection once the client has opened it,
    /// or with `nil` after ``FTPServerConfiguration/dataConnectionTimeout``.
    private func withDataConnection(_ handler: @escaping (NWConnection?) -> Void) {
        if let dataConnection {
            handler(dataConnection)
            return
        }

        let waiter = DataConnectionWaiter(handler: handler)
        let waiterID = waiter.id
        dataConnectionWaiter = waiter
        queue.asyncAfter(deadline: .now() + configuration.dataConnectionTimeout) { [weak self] in
            guard let self, let waiter = self.dataConnectionWaiter, waiter.id == waiterID else { return }
            self.dataConnectionWaiter = nil
            waiter.handler(nil)
        }
    }

    /// Drops the passive listener and data connection, failing a command still waiting for them.
    private func closeDataChannel() {
        dataConnection?.cancel()
        dataConnection = nil
        dataListener?.cancel()
        dataListener = nil
        if let waiter = dataConnectionWaiter {
            dataConnectionWaiter = nil
            waiter.handler(nil)
        }
    }

    // MARK: - Data Transfer

    private func sendListing(_ data: Data, over connection: NWConnection) {
        let transfer = DataTransfer(connection: connection, listener: dataListener, file: nil)
        activeTransfer = transfer
        connection.send(content: data.isEmpty ? nil : data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                self.failTransfer(transfer, error: error)
            } else {
                self.finishTransfer(transfer)
            }
        })
    }

    /// Streams the file in chunks, so large files aren't loaded into memory.
    private func sendNextChunk(of transfer: DataTransfer) {
        guard activeTransfer === transfer, let file = transfer.file else { return }

        let chunk: Data
        do {
            chunk = try file.read(upToCount: Self.chunkSize) ?? Data()
        } catch {
            failTransfer(transfer, error: error)
            return
        }

        guard !chunk.isEmpty else {
            completeFileTransfer(transfer)
            return
        }

        transfer.connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                self.failTransfer(transfer, error: error)
                return
            }
            transfer.bytesSent += UInt64(chunk.count)
            self.sendNextChunk(of: transfer)
        })
    }

    private func completeFileTransfer(_ transfer: DataTransfer) {
        transfer.closeFile()
        log(.info, "Sent \(transfer.bytesSent) bytes")

        let delay = configuration.legacyClientOptions.transferCompletionDelay
        guard delay > 0 else {
            finishTransfer(transfer)
            return
        }

        // Gracefully allow the peer to drain any remaining bytes before closing
        log(.debug, "Waiting \(delay) s before closing the data connection")
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.finishTransfer(transfer)
        }
    }

    private func finishTransfer(_ transfer: DataTransfer) {
        // Skipped when the transfer was aborted or the session closed meanwhile.
        guard activeTransfer === transfer else { return }
        activeTransfer = nil
        release(transfer)
        reply(226, "Transfer complete")
    }

    private func failTransfer(_ transfer: DataTransfer, error: any Error) {
        guard activeTransfer === transfer else { return }
        activeTransfer = nil
        transfer.closeFile()
        release(transfer)
        log(.error, "Transfer failed: \(error)")
        server?.emit(.failed(error, connectionID: id))
        reply(426, "Connection closed; transfer aborted")
    }

    /// Closes a transfer's data connection, and its passive listener unless `keepsPassiveListenerOpen` is set.
    /// Leaves a newer PASV's connection and listener alone.
    private func release(_ transfer: DataTransfer) {
        transfer.connection.cancel()
        if dataConnection === transfer.connection {
            dataConnection = nil
        }
        if !configuration.legacyClientOptions.keepsPassiveListenerOpen, let listener = transfer.listener, listener === dataListener {
            listener.cancel()
            dataListener = nil
        } else if dataListener != nil {
            log(.debug, "Passive listener stays open on port \(dataListener?.port?.rawValue ?? 0)")
        }
    }

    // MARK: - Response Sending

    private func reply(_ code: Int, _ message: String, then completion: (@Sendable () -> Void)? = nil) {
        send("\(code) \(message)\r\n", then: completion)
    }

    /// Sends `code-header`, the indented lines, then `code footer` (RFC 959, section 4.2).
    private func replyMultiline(_ code: Int, header: String, lines: [String], footer: String) {
        var response = "\(code)-\(header)\r\n"
        for line in lines {
            response += " \(line)\r\n"
        }
        response += "\(code) \(footer)\r\n"
        send(response, then: nil)
    }

    private func send(_ response: String, then completion: (@Sendable () -> Void)?) {
        guard !isClosed else { return }
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                self.log(.error, "Failed to send response: \(error)")
                self.server?.emit(.failed(error, connectionID: self.id))
            } else {
                self.log(.debug, "< \(trimmed)")
                self.server?.emit(.sentResponse(trimmed, connectionID: self.id))
            }
            completion?()
        })
    }

    private func replyFailure(_ error: any Error, path: String) {
        switch error as? FTPFileProviderError {
        case .notFound:
            reply(550, "\(path): No such file or directory")
        case .notADirectory:
            reply(550, "\(path): Not a directory")
        case .isADirectory:
            reply(550, "\(path): Is a directory")
        case .accessDenied:
            reply(550, "\(path): Permission denied")
        case nil:
            log(.warning, "File provider error for \(path): \(error)")
            reply(550, "\(path): \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private var fileProvider: any FTPFileProvider {
        get throws {
            guard let server else { throw FTPFileProviderError.accessDenied }
            return server.currentFileProvider
        }
    }

    private func quoted(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func log(_ level: FTPLogEntry.Level, _ message: String) {
        server?.log(level, message, connectionID: id)
    }
}
