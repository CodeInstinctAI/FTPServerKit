//
//  FTPPathTests.swift
//  FTPServerKitTests
//
//  Created by Marc Janga on 01/10/2026.
//

import Foundation
import Testing
@testable import FTPServerKit

struct FTPPathTests {

    @Test func resolvesRelativeAndAbsolutePaths() {
        #expect(FTPPath.resolve("file.bin", from: "/") == "/file.bin")
        #expect(FTPPath.resolve("/file.bin", from: "/docs") == "/file.bin")
        #expect(FTPPath.resolve("b/c.txt", from: "/a") == "/a/b/c.txt")
        #expect(FTPPath.resolve("", from: "/a") == "/a")
        #expect(FTPPath.resolve("./b//c/", from: "/a") == "/a/b/c")
    }

    @Test func parentDirectoryNeverLeavesRoot() {
        #expect(FTPPath.resolve("..", from: "/") == "/")
        #expect(FTPPath.resolve("../../..", from: "/a/b") == "/")
        #expect(FTPPath.resolve("sub/../file.bin", from: "/") == "/file.bin")
        #expect(FTPPath.resolve("/../etc/passwd", from: "/") == "/etc/passwd")
    }

    @Test func listDatesIgnoreLocaleAndUseUTC() {
        let now = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21
        let recent = Date(timeIntervalSince1970: 1_789_000_000) // 2026-09-10 00:26:40 UTC
        let old = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14
        #expect(FTPListFormatter.listDate(recent, now: now) == "Sep 10 00:26")
        #expect(FTPListFormatter.listDate(old, now: now) == "Nov 14  2023")
        #expect(FTPListFormatter.timestamp(recent) == "20260910002640")
    }
}
