//
//  FTPPath.swift
//  FTPServerKit
//
//  Created by Marc Janga on 01/10/2026.
//

import Foundation

/// Path handling for the paths clients send, so every command resolves them the same way.
enum FTPPath {

    /// Resolves a path argument against the current directory into an absolute,
    /// normalized path. `..` never goes above the root.
    static func resolve(_ path: String, from currentDirectory: String) -> String {
        var components = path.hasPrefix("/") ? [] : self.components(of: currentDirectory)
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                _ = components.popLast()
            default:
                components.append(String(component))
            }
        }
        return "/" + components.joined(separator: "/")
    }

    /// The components of a normalized path; empty for the root.
    static func components(of path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }
}

/// Formats file information the way FTP clients expect it.
enum FTPListFormatter {

    /// One `ls -l` style line, the format most clients parse for LIST.
    static func line(for item: FTPFileInfo, now: Date = Date()) -> String {
        let permissions = item.isDirectory ? "drwxr-xr-x" : "-rw-r--r--"
        return "\(permissions) 1 ftp ftp \(item.size) \(listDate(item.modificationDate, now: now)) \(item.name)"
    }

    /// `MMM dd HH:mm` for the last six months and `MMM dd  yyyy` otherwise, like `ls`.
    /// English month names in UTC, whatever the device's locale.
    static func listDate(_ date: Date, now: Date) -> String {
        let sixMonths: TimeInterval = 182 * 24 * 60 * 60
        let isRecent = date <= now && now.timeIntervalSince(date) < sixMonths
        return formatter(isRecent ? "MMM dd HH:mm" : "MMM dd  yyyy").string(from: date)
    }

    /// `YYYYMMDDHHMMSS` in UTC, the MDTM format from RFC 3659.
    static func timestamp(_ date: Date) -> String {
        formatter("yyyyMMddHHmmss").string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}
