//
//  MTPFileManager.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import Foundation
import Combine

private final class ProgressThrottler: @unchecked Sendable {
    private let minimumInterval: TimeInterval
    private let lock = NSLock()
    private var lastPublishTime = Date.distantPast
    
    init(minimumInterval: TimeInterval) {
        self.minimumInterval = minimumInterval
    }
    
    func shouldPublish(progress: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        let now = Date()
        let isTerminalProgress = progress >= 1.0
        guard now.timeIntervalSince(lastPublishTime) >= minimumInterval || isTerminalProgress else {
            return false
        }
        
        lastPublishTime = now
        return true
    }
}

@MainActor
final class MTPFileManager: ObservableObject {
    static let shared = MTPFileManager()
    
    // 操作超时时间（秒）
    private let operationTimeout: TimeInterval = 300 // 5分钟
    private let maxConcurrentOperations = 3
    
    // 操作队列
    @Published var operationQueue: [OperationQueueItem] = []
    
    private init() {}
    
    // MARK: - 文件列表
    
    func listFiles(deviceId: String, parentId: String? = nil) async throws -> [FileItem] {
        return try await withTimeout(seconds: 30) {
            try await self._listFiles(deviceId: deviceId, parentId: parentId)
        }
    }
    
    private func _listFiles(deviceId: String, parentId: String?) async throws -> [FileItem] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // listFiles returns non-nullable NSArray in Swift (empty array on error)
                    let fileInfos = try MTPBridge.listFiles(deviceId, parentId: parentId)
                    
                    // 转换数据
                    let files = fileInfos.map { info in
                        FileItem(
                            id: info.fileId,
                            name: info.fileName,
                            path: info.filePath ?? "/\(info.fileName)",
                            size: Int64(info.fileSize),
                            modifiedDate: info.modifiedDate ?? Date(),
                            isDirectory: info.isDirectory,
                            mimeType: info.mimeType
                        )
                    }
                    continuation.resume(returning: files)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 文件下载
    
    func downloadFile(
        deviceId: String,
        fileId: String,
        fileName: String,
        to destinationURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        // 验证参数
        guard !deviceId.isEmpty else {
            throw MTPError.invalidParameter("deviceId")
        }
        guard !fileId.isEmpty else {
            throw MTPError.invalidParameter("fileId")
        }
        
        // 检查目标路径
        let parentDir = destinationURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        
        // 添加超时控制
        try await withTimeout(seconds: operationTimeout) {
            try await self._downloadFile(
                deviceId: deviceId,
                fileId: fileId,
                fileName: fileName,
                to: destinationURL,
                progress: progress
            )
        }
    }
    
    private func _downloadFile(
        deviceId: String,
        fileId: String,
        fileName: String,
        to destinationURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        let progressThrottler = ProgressThrottler(minimumInterval: 0.15)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // 调用 Objective-C 的 downloadFile 方法
                    // Swift 会自动将 error 参数转换为 throws
                    try MTPBridge.downloadFile(
                        deviceId,
                        fileId: fileId,
                        toDestination: destinationURL.path,
                        progress: { progressValue, transferred, total in
                            guard progressThrottler.shouldPublish(progress: progressValue) else { return }
                            Task { @MainActor in
                                progress(progressValue)
                            }
                        }
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 文件上传
    
    func uploadFile(
        deviceId: String,
        sourceURL: URL,
        toParentId parentId: String?,
        fileName: String,
        progress: @escaping (Double) -> Void
    ) async throws -> String {
        // 验证参数
        guard !deviceId.isEmpty else {
            throw MTPError.invalidParameter("deviceId")
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MTPError.fileNotFound
        }
        
        // 验证文件名
        let sanitizedName = FileNameValidator.sanitize(fileName)
        guard !sanitizedName.isEmpty else {
            throw MTPError.invalidParameter("fileName")
        }
        
        // 检查文件大小
        let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        
        if fileSize == 0 {
            throw MTPError.invalidParameter("文件大小为0")
        }
        
        // 添加超时控制
        return try await withTimeout(seconds: operationTimeout) {
            try await self._uploadFile(
                deviceId: deviceId,
                sourceURL: sourceURL,
                toParentId: parentId,
                fileName: sanitizedName,
                progress: progress
            )
        }
    }
    
    private func _uploadFile(
        deviceId: String,
        sourceURL: URL,
        toParentId parentId: String?,
        fileName: String,
        progress: @escaping (Double) -> Void
    ) async throws -> String {
        let progressThrottler = ProgressThrottler(minimumInterval: 0.15)
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // uploadFile returns String (throws on error, not nullable in Swift)
                    let newFileId = try MTPBridge.uploadFile(
                        deviceId,
                        sourcePath: sourceURL.path,
                        toParentId: parentId,
                        fileName: fileName,
                        progress: { progressValue, transferred, total in
                            guard progressThrottler.shouldPublish(progress: progressValue) else { return }
                            Task { @MainActor in
                                progress(progressValue)
                            }
                        }
                    )
                    continuation.resume(returning: newFileId)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 文件删除
    
    func deleteFile(deviceId: String, fileId: String) async throws {
        guard !deviceId.isEmpty, !fileId.isEmpty else {
            throw MTPError.invalidParameter("deviceId or fileId")
        }
        
        try await withTimeout(seconds: 30) {
            try await self._deleteFile(deviceId: deviceId, fileId: fileId)
        }
    }
    
    private func _deleteFile(deviceId: String, fileId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // deleteFile returns Bool - throws on failure
                    try MTPBridge.deleteFile(deviceId, fileId: fileId)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 创建文件夹
    
    func createFolder(deviceId: String, name: String, parentId: String?) async throws -> String {
        // 验证并清理文件夹名称
        let result = FileNameValidator.validateAndSanitize(name)
        let sanitizedName: String
        
        switch result {
        case .success(let validName):
            sanitizedName = validName
        case .failure(let error):
            throw error
        }
        
        return try await withTimeout(seconds: 30) {
            try await self._createFolder(deviceId: deviceId, name: sanitizedName, parentId: parentId)
        }
    }
    
    private func _createFolder(deviceId: String, name: String, parentId: String?) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // createFolder returns String (throws on error, not nullable in Swift)
                    let newFolderId = try MTPBridge.createFolder(
                        deviceId,
                        name: name,
                        parentId: parentId
                    )
                    continuation.resume(returning: newFolderId)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 重命名文件
    
    func renameFile(deviceId: String, fileId: String, newName: String) async throws {
        // 验证并清理新文件名
        let result = FileNameValidator.validateAndSanitize(newName)
        let sanitizedName: String
        
        switch result {
        case .success(let validName):
            sanitizedName = validName
        case .failure(let error):
            throw error
        }
        
        try await withTimeout(seconds: 30) {
            try await self._renameFile(deviceId: deviceId, fileId: fileId, newName: sanitizedName)
        }
    }
    
    private func _renameFile(deviceId: String, fileId: String, newName: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // renameFile returns Bool - throws on failure
                    try MTPBridge.renameFile(deviceId, fileId: fileId, newName: newName)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - 超时控制扩展

extension MTPFileManager {
    /// 为异步操作添加超时控制
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // 添加实际操作任务
            group.addTask {
                try await operation()
            }
            
            // 添加超时任务
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw MTPError.timeout
            }
            
            // 等待第一个完成的任务
            guard let result = try await group.next() else {
                throw MTPError.operationCancelled
            }
            
            // 取消其他任务
            group.cancelAll()
            
            return result
        }
    }
}
