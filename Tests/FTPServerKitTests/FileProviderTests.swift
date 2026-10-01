//
//  FileProviderTests.swift
//  FTPServerKitTests
//
//  Created by Marc Janga on 01/10/2026.
//

import Foundation
import Testing
@testable import FTPServerKit

/// A temporary directory with `a.txt`, `.hidden`, `sub/b.txt` and a symlink pointing outside it.
final class TemporaryFiles {
    let root: URL
    let outside: URL

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = base.appendingPathComponent("root")
        outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appendingPathComponent("a.txt"))
        try Data("secret".utf8).write(to: root.appendingPathComponent(".hidden"))
        try Data("nested".utf8).write(to: root.appendingPathComponent("sub/b.txt"))
        try Data("outside".utf8).write(to: outside.appendingPathComponent("c.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
    }

    deinit {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }
}

private func read(_ file: any FTPReadableFile) throws -> String {
    defer { try? file.close() }
    return String(decoding: try file.read(upToCount: 1024) ?? Data(), as: UTF8.self)
}

struct DirectoryProviderTests {

    @Test func listsRootWithoutHiddenFiles() throws {
        let files = try TemporaryFiles()
        let provider = FTPDirectoryProvider(rootURL: files.root)

        #expect(try provider.itemInfo(atPath: "/").isDirectory)
        let names = try provider.contentsOfDirectory(atPath: "/").map(\.name)
        #expect(names == ["a.txt", "escape", "sub"])
        #expect(throws: FTPFileProviderError.notFound) { try provider.itemInfo(atPath: "/.hidden") }
    }

    @Test func includesHiddenFilesWhenAsked() throws {
        let files = try TemporaryFiles()
        let provider = FTPDirectoryProvider(rootURL: files.root, includesHiddenFiles: true)

        #expect(try provider.contentsOfDirectory(atPath: "/").map(\.name).contains(".hidden"))
        #expect(try read(provider.openFile(atPath: "/.hidden", offset: 0)) == "secret")
    }

    @Test func readsFilesInSubdirectoriesFromAnOffset() throws {
        let files = try TemporaryFiles()
        let provider = FTPDirectoryProvider(rootURL: files.root)

        let info = try provider.itemInfo(atPath: "/sub/b.txt")
        #expect(info.name == "b.txt")
        #expect(info.size == 6)
        #expect(!info.isDirectory)
        #expect(try read(provider.openFile(atPath: "/a.txt", offset: 2)) == "llo")
    }

    @Test func rejectsWrongKinds() throws {
        let files = try TemporaryFiles()
        let provider = FTPDirectoryProvider(rootURL: files.root)

        #expect(throws: FTPFileProviderError.notADirectory) { try provider.contentsOfDirectory(atPath: "/a.txt") }
        #expect(throws: FTPFileProviderError.isADirectory) { try provider.openFile(atPath: "/sub", offset: 0) }
        #expect(throws: FTPFileProviderError.notFound) { try provider.itemInfo(atPath: "/missing") }
    }

    @Test func refusesSymlinksOutOfTheRoot() throws {
        let files = try TemporaryFiles()
        let provider = FTPDirectoryProvider(rootURL: files.root)

        #expect(throws: FTPFileProviderError.accessDenied) { try provider.itemInfo(atPath: "/escape") }
        #expect(throws: FTPFileProviderError.accessDenied) { try provider.openFile(atPath: "/escape/c.txt", offset: 0) }
    }
}

struct SingleFileProviderTests {

    @Test func servesOneFileInTheRoot() throws {
        let files = try TemporaryFiles()
        let provider = FTPSingleFileProvider(fileURL: files.root.appendingPathComponent("a.txt"))

        #expect(try provider.itemInfo(atPath: "/").isDirectory)
        #expect(try provider.contentsOfDirectory(atPath: "/").map(\.name) == ["a.txt"])
        #expect(try provider.itemInfo(atPath: "/a.txt").size == 5)
        #expect(try read(provider.openFile(atPath: "/a.txt", offset: 1)) == "ello")
        #expect(throws: FTPFileProviderError.notFound) { try provider.itemInfo(atPath: "/sub/b.txt") }
        #expect(throws: FTPFileProviderError.notADirectory) { try provider.contentsOfDirectory(atPath: "/a.txt") }
    }

    @Test func servesUnderAnotherName() throws {
        let files = try TemporaryFiles()
        let provider = FTPSingleFileProvider(fileURL: files.root.appendingPathComponent("a.txt"), fileName: "file.bin")

        #expect(try provider.contentsOfDirectory(atPath: "/").map(\.name) == ["file.bin"])
        #expect(throws: FTPFileProviderError.notFound) { try provider.itemInfo(atPath: "/a.txt") }
    }

    @Test func missingFileIsNotFound() {
        let provider = FTPSingleFileProvider(fileURL: URL(fileURLWithPath: "/nonexistent/file.bin"))
        #expect(throws: FTPFileProviderError.notFound) { try provider.contentsOfDirectory(atPath: "/") }
    }
}
