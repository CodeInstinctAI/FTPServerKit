//
//  FTPServerTests.swift
//  FTPServerKitTests
//
//  Created by Marc Janga on 01/10/2026.
//

import Combine
import Foundation
import Testing
@testable import FTPServerKit

private func makeServer(
    provider: any FTPFileProvider,
    port: UInt16 = 0,
    legacyClientOptions: FTPLegacyClientOptions = .none
) -> FTPServer {
    FTPServer(
        configuration: FTPServerConfiguration(
            port: port,
            authentication: .credentials(username: "user", password: "pass"),
            bindsToLoopbackOnly: true,
            legacyClientOptions: legacyClientOptions
        ),
        fileProvider: provider
    )
}

@Suite(.serialized)
struct FTPServerTests {

    @Test func startsAndStops() async throws {
        let files = try TemporaryFiles()
        let server = makeServer(provider: FTPDirectoryProvider(rootURL: files.root))

        let port = try await server.start()
        #expect(port != 0)
        #expect(server.isRunning)
        #expect(server.port == port)

        await #expect(throws: FTPServerError.self) { try await server.start() }

        server.stop()
        #expect(!server.isRunning)
        #expect(server.port == nil)
    }

    @Test func startFailsWhenThePortIsInUse() async throws {
        let files = try TemporaryFiles()
        let first = makeServer(provider: FTPDirectoryProvider(rootURL: files.root))
        let port = try await first.start()
        defer { first.stop() }

        let second = makeServer(provider: FTPDirectoryProvider(rootURL: files.root), port: port)
        await #expect(throws: FTPServerError.self) { try await second.start() }
        #expect(!second.isRunning)
    }

    @Test func eventStreamsAndTheDelegateReceiveStartAndStop() async throws {
        let files = try TemporaryFiles()
        let server = makeServer(provider: FTPDirectoryProvider(rootURL: files.root))
        let first = server.events
        let second = server.events
        let delegate = RecordingDelegate()
        server.delegate = delegate

        let port = try await server.start()
        server.stop()

        for stream in [first, second] {
            var iterator = stream.makeAsyncIterator()
            guard case .started(let startedPort) = await iterator.next() else {
                Issue.record("Expected .started")
                return
            }
            #expect(startedPort == port)
            guard case .stopped(let error) = await iterator.next() else {
                Issue.record("Expected .stopped")
                return
            }
            #expect(error == nil)
        }

        // Delegate calls are queued on the main actor; this hop runs after them.
        await MainActor.run {}
        #expect(await delegate.events == ["started \(port)", "stopped"])
    }

    @Test func eventPublisherReceivesStartAndStop() async throws {
        let files = try TemporaryFiles()
        let server = makeServer(provider: FTPDirectoryProvider(rootURL: files.root))
        let received = LockedEvents()
        let subscription = server.eventPublisher.sink { received.append($0) }
        defer { subscription.cancel() }

        let port = try await server.start()
        // Both events are sent on the server's queue, which `stop()` waits for.
        server.stop()

        let events = received.events
        #expect(events.count == 2)
        guard case .started(let startedPort) = events.first, case .stopped(nil) = events.last else {
            Issue.record("Expected .started then .stopped, got \(events)")
            return
        }
        #expect(startedPort == port)
    }

    @Test func eventPublisherFinishesWhenTheServerIsReleased() async throws {
        let files = try TemporaryFiles()
        var server: FTPServer? = makeServer(provider: FTPDirectoryProvider(rootURL: files.root))
        let finished = LockedEvents()
        let subscription = try #require(server?.eventPublisher).sink(
            receiveCompletion: { _ in finished.append(.stopped(error: nil)) },
            receiveValue: { _ in }
        )
        defer { subscription.cancel() }
        server = nil

        #expect(finished.events.count == 1)
    }

    @Test func eventStreamFinishesWhenTheServerIsReleased() async throws {
        let files = try TemporaryFiles()
        var server: FTPServer? = makeServer(provider: FTPDirectoryProvider(rootURL: files.root))
        let events = try #require(server?.events)
        server = nil

        var iterator = events.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FTPServerEvent] = []

    var events: [FTPServerEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ event: FTPServerEvent) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(event)
    }
}

@MainActor
private final class RecordingDelegate: FTPServerDelegate {
    var events: [String] = []

    func ftpServer(_ server: FTPServer, didStartOnPort port: UInt16) {
        events.append("started \(port)")
    }

    func ftpServerDidStop(_ server: FTPServer, error: (any Error)?) {
        events.append(error == nil ? "stopped" : "failed")
    }
}

#if os(macOS)
/// Runs real transfers through the system `curl`, which uses EPSV, SIZE, REST and LIST.
@Suite(.serialized)
struct FTPTransferTests {

    private func curl(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["--silent", "--show-error", "--max-time", "10"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    @Test func downloadsListsAndResumes() async throws {
        let files = try TemporaryFiles()
        let server = makeServer(provider: FTPDirectoryProvider(rootURL: files.root))
        let port = try await server.start()
        defer { server.stop() }
        let base = "ftp://user:pass@127.0.0.1:\(port)"

        #expect(try curl(["\(base)/a.txt"]).output == "hello")
        #expect(try curl(["\(base)/sub/b.txt"]).output == "nested")
        #expect(try curl(["--ftp-pasv", "--disable-epsv", "\(base)/a.txt"]).output == "hello")
        #expect(try curl(["--continue-at", "2", "\(base)/a.txt"]).output == "llo")

        // curl turns the CRLF line endings of listings into LF.
        let listing = try curl(["\(base)/"]).output
        #expect(listing.contains("-rw-r--r-- 1 ftp ftp 5 "))
        #expect(listing.contains(" a.txt\n"))
        #expect(listing.contains("drwxr-xr-x"))
        #expect(!listing.contains(".hidden"))
        #expect(try curl(["--list-only", "\(base)/sub/"]).output == "b.txt\n")
    }

    @Test func eventStreamReportsCommandsAndResponses() async throws {
        let files = try TemporaryFiles()
        let server = makeServer(provider: FTPDirectoryProvider(rootURL: files.root))
        let events = server.events
        let port = try await server.start()
        #expect(try curl(["ftp://user:pass@127.0.0.1:\(port)/a.txt"]).output == "hello")
        server.stop()

        var commands: [String] = []
        var responses: [String] = []
        var connectionIDs: Set<UUID> = []
        events: for await event in events {
            switch event {
            case .receivedCommand(let command, let argument, let connectionID):
                commands.append("\(command) \(argument)")
                connectionIDs.insert(connectionID)
            case .sentResponse(let response, let connectionID):
                responses.append(response)
                connectionIDs.insert(connectionID)
            case .stopped:
                break events
            default:
                break
            }
        }

        #expect(commands.contains("USER user"))
        #expect(commands.contains("PASS ****"))
        #expect(commands.contains("RETR a.txt"))
        #expect(responses.contains { $0.hasPrefix("226 ") })
        #expect(connectionIDs.count == 1) // curl used one control connection
    }

    @Test func rejectsBadLoginsAndMissingFiles() async throws {
        let files = try TemporaryFiles()
        let server = makeServer(provider: FTPSingleFileProvider(fileURL: files.root.appendingPathComponent("a.txt")))
        let port = try await server.start()
        defer { server.stop() }

        #expect(try curl(["ftp://user:wrong@127.0.0.1:\(port)/a.txt"]).status == 67) // login denied
        #expect(try curl(["ftp://user:pass@127.0.0.1:\(port)/missing.txt"]).status == 78) // remote file not found
        #expect(try curl(["ftp://user:pass@127.0.0.1:\(port)/a.txt"]).output == "hello")
    }

    @Test func streamsLargeFiles() async throws {
        let files = try TemporaryFiles()
        let large = files.root.appendingPathComponent("large.bin")
        let data = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try data.write(to: large)
        let server = makeServer(provider: FTPSingleFileProvider(fileURL: large))
        let port = try await server.start()
        defer { server.stop() }

        let output = files.root.appendingPathComponent("downloaded.bin")
        #expect(try curl(["--output", output.path, "ftp://user:pass@127.0.0.1:\(port)/large.bin"]).status == 0)
        #expect(try Data(contentsOf: output) == data)
    }

    @Test func legacyOptionsDelayCompletionAndKeepTheListenerOpen() async throws {
        let files = try TemporaryFiles()
        let server = makeServer(
            provider: FTPDirectoryProvider(rootURL: files.root),
            legacyClientOptions: FTPLegacyClientOptions(transferCompletionDelay: 1, keepsPassiveListenerOpen: true)
        )
        let port = try await server.start()
        defer { server.stop() }

        let started = Date()
        #expect(try curl(["ftp://user:pass@127.0.0.1:\(port)/a.txt"]).output == "hello")
        #expect(Date().timeIntervalSince(started) >= 1)
    }

    @Test func closesTheFileOnceWhenStoppedDuringTheCompletionDelay() async throws {
        let files = try TemporaryFiles()
        let provider = CloseCountingProvider(base: FTPDirectoryProvider(rootURL: files.root))
        let server = makeServer(
            provider: provider,
            legacyClientOptions: FTPLegacyClientOptions(transferCompletionDelay: 5)
        )
        let port = try await server.start()

        let download = Task.detached { try curl(["ftp://user:pass@127.0.0.1:\(port)/a.txt"]) }

        // The file is closed after its last byte, then the server waits 5 s before replying 226.
        let deadline = Date().addingTimeInterval(4)
        while provider.closeCount == 0, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(provider.closeCount == 1)

        // Closes the session while the transfer is still waiting for its delay.
        server.stop()
        #expect(try await download.value.status != 0) // curl never got the 226
        #expect(provider.closeCount == 1)
    }
}
#endif

/// Wraps a provider and counts how often the files it opened are closed.
private final class CloseCountingProvider: FTPFileProvider, @unchecked Sendable {
    // Unchecked: `closes` is guarded by `lock`.
    private let base: any FTPFileProvider
    private let lock = NSLock()
    private var closes = 0

    init(base: any FTPFileProvider) {
        self.base = base
    }

    var closeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return closes
    }

    func itemInfo(atPath path: String) throws -> FTPFileInfo {
        try base.itemInfo(atPath: path)
    }

    func contentsOfDirectory(atPath path: String) throws -> [FTPFileInfo] {
        try base.contentsOfDirectory(atPath: path)
    }

    func openFile(atPath path: String, offset: UInt64) throws -> any FTPReadableFile {
        CountedFile(base: try base.openFile(atPath: path, offset: offset)) { [self] in
            lock.lock()
            defer { lock.unlock() }
            closes += 1
        }
    }

    private final class CountedFile: FTPReadableFile {
        private let base: any FTPReadableFile
        private let onClose: () -> Void

        init(base: any FTPReadableFile, onClose: @escaping () -> Void) {
            self.base = base
            self.onClose = onClose
        }

        func read(upToCount count: Int) throws -> Data? {
            try base.read(upToCount: count)
        }

        func close() throws {
            onClose()
            try base.close()
        }
    }
}
