//
//  SharedFile.swift
//  FTPServerKitExample
//
//  Created by Marc Janga on 13/10/2025.
//

import Foundation

/// Represents a file that is being shared via the local server
struct SharedFile: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let name: String
    let size: Int64
    let type: String
    let dateAdded: Date
    
    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent

        // Get file size and the date it was added to the shared folder
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.size = attributes?[.size] as? Int64 ?? 0
        self.dateAdded = attributes?[.creationDate] as? Date ?? Date()
        
        // Determine file type from extension
        let fileExtension = url.pathExtension.lowercased()
        self.type = SharedFile.mimeType(for: fileExtension)
    }
    
    /// Format file size for display
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    /// Get icon name based on file type
    var iconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic":
            return "photo.fill"
        case "mp4", "mov", "avi":
            return "video.fill"
        case "mp3", "m4a", "wav":
            return "music.note"
        case "zip", "rar", "7z":
            return "archivebox.fill"
        case "txt", "rtf":
            return "doc.text.fill"
        default:
            return "doc.fill"
        }
    }
    
    /// Get MIME type for file extension
    static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "html", "htm":
            return "text/html"
        case "txt":
            return "text/plain"
        case "pdf":
            return "application/pdf"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "mp4":
            return "video/mp4"
        case "mp3":
            return "audio/mpeg"
        case "zip":
            return "application/zip"
        case "json":
            return "application/json"
        default:
            return "application/octet-stream"
        }
    }
}

