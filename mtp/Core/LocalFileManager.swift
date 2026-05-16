//
//  LocalFileManager.swift
//  mtp
//
//  Created by Li on 2026/4/19.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
class LocalFileManager: ObservableObject {
    @Published var files: [LocalFileItem] = []
    @Published var selectedFiles: Set<String> = []
    @Published var currentURL: URL?
    @Published var pathComponents: [LocalPathComponent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let fileManager = FileManager.default
    
    init() {
        // 默认导航到用户的下载文件夹
        let downloadsURL = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let url = downloadsURL {
            navigateToURL(url)
        }
    }
    
    func navigateToURL(_ url: URL) {
        currentURL = url
        updatePathComponents()
        Task {
            await loadFiles()
        }
    }
    
    func navigateToParent() {
        guard let currentURL = currentURL else { return }
        let parentURL = currentURL.deletingLastPathComponent()
        navigateToURL(parentURL)
    }
    
    func navigateToPathComponent(_ component: LocalPathComponent) {
        navigateToURL(component.url)
    }
    
    func navigateToFolder(_ folder: LocalFileItem) {
        guard folder.isDirectory else { return }
        navigateToURL(folder.url)
    }
    
    func refresh() async {
        await loadFiles()
    }
    
    private func updatePathComponents() {
        guard let currentURL = currentURL else {
            pathComponents = []
            return
        }
        
        var components: [LocalPathComponent] = []
        var url = currentURL
        
        // 构建路径组件
        while url.path != "/" {
            let component = LocalPathComponent(
                id: url.path,
                name: url.lastPathComponent,
                url: url
            )
            components.insert(component, at: 0)
            url = url.deletingLastPathComponent()
        }
        
        // 添加根目录
        components.insert(LocalPathComponent(
            id: "/",
            name: "根目录",
            url: URL(fileURLWithPath: "/")
        ), at: 0)
        
        pathComponents = components
    }
    
    private func loadFiles() async {
        guard let currentURL = currentURL else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let resourceKeys: [URLResourceKey] = [
                .nameKey,
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .typeIdentifierKey
            ]
            
            let urls = try fileManager.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            )
            
            var newFiles: [LocalFileItem] = []
            
            for url in urls {
                let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
                
                let file = LocalFileItem(
                    id: url.path,
                    name: resourceValues.name ?? url.lastPathComponent,
                    url: url,
                    isDirectory: resourceValues.isDirectory ?? false,
                    size: Int64(resourceValues.fileSize ?? 0),
                    modifiedDate: resourceValues.contentModificationDate ?? Date(),
                    typeIdentifier: resourceValues.typeIdentifier
                )
                
                newFiles.append(file)
            }
            
            // 排序：文件夹在前，然后按名称排序
            newFiles.sort { file1, file2 in
                if file1.isDirectory != file2.isDirectory {
                    return file1.isDirectory && !file2.isDirectory
                }
                return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
            }
            
            files = newFiles
            
        } catch {
            errorMessage = "无法读取文件夹: \(error.localizedDescription)"
            files = []
        }
        
        isLoading = false
    }
    
    // MARK: - Selection Management
    
    func selectFile(_ fileId: String, multiSelect: Bool = false) {
        if multiSelect {
            selectedFiles.insert(fileId)
        } else {
            selectedFiles = [fileId]
        }
    }
    
    func toggleFileSelection(_ fileId: String) {
        if selectedFiles.contains(fileId) {
            selectedFiles.remove(fileId)
        } else {
            selectedFiles.insert(fileId)
        }
    }
    
    func selectAllFiles() {
        selectedFiles = Set(files.map { $0.id })
    }
    
    func deselectAllFiles() {
        selectedFiles.removeAll()
    }
    
    func selectRange(from startId: String, to endId: String) {
        guard let startIndex = files.firstIndex(where: { $0.id == startId }),
              let endIndex = files.firstIndex(where: { $0.id == endId }) else { return }
        
        let range = min(startIndex, endIndex)...max(startIndex, endIndex)
        let rangeIds = files[range].map { $0.id }
        selectedFiles.formUnion(rangeIds)
    }
    
    // MARK: - File Operations
    
    func openFile(_ file: LocalFileItem) {
        NSWorkspace.shared.open(file.url)
    }
    
    func revealInFinder(_ file: LocalFileItem) {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }
    
    func deleteFiles(_ filesToDelete: [LocalFileItem]) async -> OperationResult<LocalFileItem> {
        var succeeded: [LocalFileItem] = []
        var failed: [(LocalFileItem, Error)] = []
        
        for file in filesToDelete {
            do {
                try fileManager.trashItem(at: file.url, resultingItemURL: nil)
                succeeded.append(file)
            } catch {
                failed.append((file, error))
            }
        }
        
        await refresh()
        
        return OperationResult(succeeded: succeeded, failed: failed)
    }
    
    /// 删除选中的文件（UI调用）
    func deleteSelectedFiles() {
        let filesToDelete = files.filter { selectedFiles.contains($0.id) }
        guard !filesToDelete.isEmpty else { return }
        
        Task {
            let result = await deleteFiles(filesToDelete)
            
            if !result.isFullSuccess {
                errorMessage = result.summary
            }
        }
    }
    
    func createFolder(name: String) {
        guard let currentURL = currentURL else { return }
        
        // 验证文件夹名称
        let result = FileNameValidator.validateAndSanitize(name)
        let sanitizedName: String
        
        switch result {
        case .success(let validName):
            sanitizedName = validName
        case .failure(let error):
            errorMessage = error.localizedDescription
            return
        }
        
        let folderURL = currentURL.appendingPathComponent(sanitizedName)
        
        // 检查是否已存在
        if fileManager.fileExists(atPath: folderURL.path) {
            errorMessage = "文件夹已存在"
            return
        }
        
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: false)
            Task {
                await refresh()
            }
        } catch {
            errorMessage = "创建文件夹失败: \(error.localizedDescription)"
        }
    }
}

// MARK: - Local File Models

struct LocalFileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let modifiedDate: Date
    let typeIdentifier: String?
    
    var fileExtension: String {
        url.pathExtension.lowercased()
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        
        // 根据文件类型返回图标
        switch fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "video"
        case "mp3", "m4a", "wav", "flac":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "doc", "docx":
            return "doc.text"
        case "txt", "md":
            return "doc.plaintext"
        case "zip", "rar", "7z":
            return "archivebox"
        default:
            return "doc"
        }
    }
}

struct LocalPathComponent: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
}