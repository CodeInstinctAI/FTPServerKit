//
//  FTPServerTests.swift
//  FTPServerKitTests
//
//  Created by Marc Janga on 01/10/2026.
//

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
}
#endif
