//
//  FileItem.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import Foundation

struct FileItem: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let modifiedDate: Date
    let isDirectory: Bool
    let mimeType: String?
    
    // Equatable 实现：基于 id 比较
    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        return lhs.id == rhs.id
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var fileExtension: String {
        (name as NSString).pathExtension.lowercased()
    }
    
    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        
        switch fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return "photo.fill"
        case "mp4", "mov", "avi", "mkv":
            return "video.fill"
        case "mp3", "m4a", "wav", "flac":
            return "music.note"
        case "pdf":
            return "doc.fill"
        case "zip", "rar", "7z":
            return "doc.zipper"
        case "txt", "md":
            return "doc.text.fill"
        default:
            return "doc.fill"
        }
    }
}

// 模拟数据
extension FileItem {
    static let samples = [
        FileItem(
            id: "1",
            name: "DCIM",
            path: "/DCIM",
            size: 0,
            modifiedDate: Date(),
            isDirectory: true,
            mimeType: nil
        ),
        FileItem(
            id: "2",
            name: "Download",
            path: "/Download",
            size: 0,
            modifiedDate: Date(),
            isDirectory: true,
            mimeType: nil
        ),
        FileItem(
            id: "3",
            name: "IMG_20260418_001.jpg",
            path: "/DCIM/Camera/IMG_20260418_001.jpg",
            size: 4_567_890,
            modifiedDate: Date().addingTimeInterval(-3600),
            isDirectory: false,
            mimeType: "image/jpeg"
        ),
        FileItem(
            id: "4",
            name: "VID_20260418_001.mp4",
            path: "/DCIM/Camera/VID_20260418_001.mp4",
            size: 125_678_901,
            modifiedDate: Date().addingTimeInterval(-7200),
            isDirectory: false,
            mimeType: "video/mp4"
        ),
        FileItem(
            id: "5",
            name: "document.pdf",
            path: "/Download/document.pdf",
            size: 2_345_678,
            modifiedDate: Date().addingTimeInterval(-86400),
            isDirectory: false,
            mimeType: "application/pdf"
        )
    ]
}
