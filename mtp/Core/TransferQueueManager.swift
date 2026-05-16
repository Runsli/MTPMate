//
//  TransferQueueManager.swift
//  mtp
//
//  传输队列管理器
//

import Foundation
import SwiftUI
import Combine

@MainActor
class TransferQueueManager: ObservableObject {
    static let shared = TransferQueueManager()
    
    @Published var tasks: [TransferTask] = []
    @Published var isProcessing: Bool = false
    
    // 统计信息
    @Published var totalProgress: Double = 0.0
    @Published var completedCount: Int = 0
    @Published var failedCount: Int = 0
    
    // libmtp access to a single device is effectively serialized; keeping the
    // app-level queue serial avoids hidden lock contention and unstable device state.
    private let maxConcurrentTasks = 1
    private var activeTasks: Set<UUID> = []
    
    private let fileManager = MTPFileManager.shared
    private var deviceId: String?
    private var uploadConflictNameCache: [UploadDestinationKey: Set<String>] = [:]
    private var loadedUploadConflictKeys: Set<UploadDestinationKey> = []
    
    private struct UploadDestinationKey: Hashable {
        let deviceId: String
        let parentId: String?
    }
    
    private init() {}
    
    // MARK: - 添加任务
    
    /// 添加上传任务
    func addUploadTask(
        deviceId: String,
        sourceURL: URL,
        destinationParentId: String?,
        conflictResolution: ConflictResolution = .ask
    ) {
        let filePath = sourceURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let fileSize = attributes[.size] as? Int64 else {
            Logger.error("无法获取文件大小: \(filePath)")
            return
        }
        
        let fileName = sourceURL.lastPathComponent
        
        let task = TransferTask(
            fileName: fileName,
            fileSize: fileSize,
            direction: .upload,
            sourceURL: sourceURL,
            sourceFileId: nil,
            destinationURL: nil,
            destinationParentId: destinationParentId
        )
        task.conflictResolution = conflictResolution
        
        tasks.append(task)
        self.deviceId = deviceId
        
        Logger.debug("添加上传任务: \(task.fileName)")
        
        // 自动开始处理
        if !isProcessing {
            processQueue()
        }
    }
    
    /// 添加下载任务
    func addDownloadTask(
        deviceId: String,
        file: FileItem,
        destinationURL: URL,
        conflictResolution: ConflictResolution = .ask
    ) {
        let fileName = file.name
        let fileSize = file.size
        let fileId = file.id
        
        let task = TransferTask(
            fileName: fileName,
            fileSize: fileSize,
            direction: .download,
            sourceURL: nil,
            sourceFileId: fileId,
            destinationURL: destinationURL,
            destinationParentId: nil
        )
        task.conflictResolution = conflictResolution
        
        tasks.append(task)
        self.deviceId = deviceId
        
        Logger.debug("添加下载任务: \(task.fileName)")
        
        // 自动开始处理
        if !isProcessing {
            processQueue()
        }
    }
    
    /// 批量添加上传任务
    func addUploadTasks(
        deviceId: String,
        sourceURLs: [URL],
        destinationParentId: String?,
        conflictResolution: ConflictResolution = .ask
    ) {
        self.deviceId = deviceId
        
        Task { @MainActor in
            await primeUploadConflictCache(deviceId: deviceId, parentId: destinationParentId)
            
            for url in sourceURLs {
                enqueueUploadTask(
                    deviceId: deviceId,
                    sourceURL: url,
                    destinationParentId: destinationParentId,
                    conflictResolution: conflictResolution
                )
            }
            
            if !isProcessing {
                processQueue()
            }
        }
    }
    
    /// 批量添加下载任务
    func addDownloadTasks(
        deviceId: String,
        files: [FileItem],
        destinationURL: URL,
        conflictResolution: ConflictResolution = .ask
    ) {
        for file in files {
            let fileDestination = destinationURL.appendingPathComponent(file.name)
            addDownloadTask(
                deviceId: deviceId,
                file: file,
                destinationURL: fileDestination,
                conflictResolution: conflictResolution
            )
        }
    }
    
    // MARK: - 队列处理
    
    private func processQueue() {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task { @MainActor in
            while hasPendingTasks() {
                // 启动新任务直到达到并发限制
                while activeTasks.count < maxConcurrentTasks, let nextTask = getNextPendingTask() {
                    await startTask(nextTask)
                }
                
                // 等待一段时间再检查
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1秒
                
                // 更新总体进度
                updateTotalProgress()
            }
            
            isProcessing = false
            Logger.info("队列处理完成")
        }
    }
    
    private func hasPendingTasks() -> Bool {
        return tasks.contains { task in
            switch task.status {
            case .pending, .transferring:
                return true
            default:
                return false
            }
        }
    }
    
    private func getNextPendingTask() -> TransferTask? {
        return tasks.first { task in
            task.status == .pending
        }
    }
    
    private func startTask(_ task: TransferTask) async {
        guard let deviceId = deviceId else {
            task.status = .failed(MTPError.deviceNotFound)
            return
        }
        
        activeTasks.insert(task.id)
        task.status = .transferring
        
        Logger.debug("开始传输: \(task.fileName)")
        
        // 在后台执行传输任务
        task.task = Task.detached { [weak self] in
            do {
                switch task.direction {
                case .upload:
                    try await self?.performUpload(task, deviceId: deviceId)
                case .download:
                    try await self?.performDownload(task, deviceId: deviceId)
                }
                
                await MainActor.run { [weak self] in
                    task.status = .completed
                    self?.completedCount += 1
                    Logger.info("传输完成: \(task.fileName)")
                }
            } catch {
                await MainActor.run { [weak self] in
                    task.status = .failed(error)
                    self?.failedCount += 1
                    Logger.error("传输失败: \(task.fileName) - \(error.localizedDescription)")
                }
            }
            
            await MainActor.run { [weak self] in
                _ = self?.activeTasks.remove(task.id)
            }
        }
    }
    
    nonisolated private func performUpload(_ task: TransferTask, deviceId: String) async throws {
        guard let sourceURL = task.sourceURL else {
            throw MTPError.invalidParameter("sourceURL")
        }
        
        // 检查冲突
        let finalFileName = try await resolveConflict(
            task: task,
            deviceId: deviceId,
            isUpload: true
        )
        
        // 获取 fileManager（需要在主线程）
        let fileManager = await MainActor.run { MTPFileManager.shared }
        
        // 执行上传
        _ = try await fileManager.uploadFile(
            deviceId: deviceId,
            sourceURL: sourceURL,
            toParentId: task.destinationParentId,
            fileName: finalFileName,
            progress: { progress in
                Task { @MainActor in
                    let transferred = Int64(Double(task.fileSize) * progress)
                    task.updateProgress(progress, transferred: transferred)
                }
            }
        )
        
        await MainActor.run {
            self.recordUploadedName(task.resolvedFileName ?? finalFileName, deviceId: deviceId, parentId: task.destinationParentId)
        }
    }
    
    nonisolated private func performDownload(_ task: TransferTask, deviceId: String) async throws {
        guard let sourceFileId = task.sourceFileId,
              task.destinationURL != nil else {
            throw MTPError.invalidParameter("sourceFileId or destinationURL")
        }
        
        // 检查冲突
        let finalDestination = try await resolveConflict(
            task: task,
            deviceId: deviceId,
            isUpload: false
        )
        
        // 获取 fileManager（需要在主线程）
        let fileManager = await MainActor.run { MTPFileManager.shared }
        
        // 执行下载
        try await fileManager.downloadFile(
            deviceId: deviceId,
            fileId: sourceFileId,
            fileName: task.fileName,
            to: URL(fileURLWithPath: finalDestination),
            progress: { progress in
                Task { @MainActor in
                    let transferred = Int64(Double(task.fileSize) * progress)
                    task.updateProgress(progress, transferred: transferred)
                }
            }
        )
    }
    
    // MARK: - 冲突处理
    
    nonisolated private func resolveConflict(task: TransferTask, deviceId: String, isUpload: Bool) async throws -> String {
        let fileName = task.fileName
        
        // 检查是否存在冲突
        let hasConflict: Bool
        if isUpload {
            hasConflict = try await checkUploadConflict(deviceId: deviceId, fileName: fileName, parentId: task.destinationParentId)
        } else {
            hasConflict = FileManager.default.fileExists(atPath: task.destinationURL?.path ?? "")
        }
        
        guard hasConflict else {
            return isUpload ? fileName : (task.destinationURL?.path ?? "")
        }
        
        // 获取冲突解决策略（需要在主线程）
        let conflictResolution = await MainActor.run { task.conflictResolution }
        
        // 根据策略处理冲突
        switch conflictResolution {
        case .rename:
            let newName = generateUniqueName(fileName, isUpload: isUpload, task: task)
            await MainActor.run {
                task.resolvedFileName = newName
            }
            return newName
            
        case .skip:
            throw MTPError.operationCancelled
            
        case .overwrite:
            return isUpload ? fileName : (task.destinationURL?.path ?? "")
            
        case .ask:
            // 暂停任务，等待用户决定
            await MainActor.run {
                task.status = .paused
            }
            throw MTPError.operationCancelled // 暂时取消，等待用户处理
        }
    }
    
    nonisolated private func checkUploadConflict(deviceId: String, fileName: String, parentId: String?) async throws -> Bool {
        try await hasCachedUploadConflict(deviceId: deviceId, fileName: fileName, parentId: parentId)
    }
    
    nonisolated private func generateUniqueName(_ originalName: String, isUpload: Bool, task: TransferTask) -> String {
        let nameWithoutExt = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        var counter = 1
        var newName = originalName
        
        while true {
            if isUpload {
                // 检查MTP设备上是否存在
                // 简化实现：直接添加数字后缀
                newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
                counter += 1
                if counter > 100 { break } // 防止无限循环
            } else {
                // 检查本地文件系统
                guard let destURL = task.destinationURL else { break }
                let parentURL = destURL.deletingLastPathComponent()
                newName = ext.isEmpty ? "\(nameWithoutExt) (\(counter))" : "\(nameWithoutExt) (\(counter)).\(ext)"
                let newURL = parentURL.appendingPathComponent(newName)
                
                if !FileManager.default.fileExists(atPath: newURL.path) {
                    return newURL.path
                }
                counter += 1
            }
        }
        
        return newName
    }
    
    // MARK: - 任务控制
    
    /// 暂停任务
    func pauseTask(_ task: TransferTask) {
        task.task?.cancel()
        task.status = .paused
        activeTasks.remove(task.id)
        Logger.debug("暂停任务: \(task.fileName)")
    }
    
    /// 恢复任务
    func resumeTask(_ task: TransferTask) {
        guard task.status == .paused else { return }
        task.status = .pending
        Logger.debug("恢复任务: \(task.fileName)")
        
        if !isProcessing {
            processQueue()
        }
    }
    
    /// 取消任务
    func cancelTask(_ task: TransferTask) {
        task.task?.cancel()
        task.status = .cancelled
        activeTasks.remove(task.id)
        Logger.debug("取消任务: \(task.fileName)")
    }
    
    /// 重试失败的任务
    func retryTask(_ task: TransferTask) {
        guard case .failed = task.status else { return }
        task.status = .pending
        task.progress = 0
        task.transferredBytes = 0
        Logger.debug("重试任务: \(task.fileName)")
        
        if !isProcessing {
            processQueue()
        }
    }
    
    /// 移动任务位置
    func moveTask(from source: IndexSet, to destination: Int) {
        tasks.move(fromOffsets: source, toOffset: destination)
        Logger.debug("任务已重新排序")
    }
    
    /// 清除已完成的任务
    func clearCompletedTasks() {
        tasks.removeAll { task in
            task.status == .completed
        }
        completedCount = 0
        Logger.debug("已清除完成的任务")
    }
    
    /// 清除所有任务
    func clearAllTasks() {
        // 取消所有进行中的任务
        for task in tasks where task.status == .transferring {
            task.task?.cancel()
        }
        
        tasks.removeAll()
        activeTasks.removeAll()
        completedCount = 0
        failedCount = 0
        totalProgress = 0
        Logger.debug("已清除所有任务")
    }
    
    // MARK: - 统计
    
    private func updateTotalProgress() {
        guard !tasks.isEmpty else {
            totalProgress = 0
            return
        }
        
        let totalSize = tasks.reduce(0) { $0 + $1.fileSize }
        let transferredSize = tasks.reduce(0) { $0 + $1.transferredBytes }
        
        totalProgress = totalSize > 0 ? Double(transferredSize) / Double(totalSize) : 0
    }
    
    var pendingCount: Int {
        tasks.filter { $0.status == .pending }.count
    }
    
    var transferringCount: Int {
        tasks.filter { $0.status == .transferring }.count
    }
    
    var pausedCount: Int {
        tasks.filter { $0.status == .paused }.count
    }
    
    private func enqueueUploadTask(
        deviceId: String,
        sourceURL: URL,
        destinationParentId: String?,
        conflictResolution: ConflictResolution = .ask
    ) {
        let filePath = sourceURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let fileSize = attributes[.size] as? Int64 else {
            Logger.error("无法获取文件大小: \(filePath)")
            return
        }
        
        let task = TransferTask(
            fileName: sourceURL.lastPathComponent,
            fileSize: fileSize,
            direction: .upload,
            sourceURL: sourceURL,
            sourceFileId: nil,
            destinationURL: nil,
            destinationParentId: destinationParentId
        )
        task.conflictResolution = conflictResolution
        
        tasks.append(task)
        self.deviceId = deviceId
        
        Logger.debug("添加上传任务: \(task.fileName)")
    }
    
    private func primeUploadConflictCache(deviceId: String, parentId: String?) async {
        let key = UploadDestinationKey(deviceId: deviceId, parentId: parentId)
        guard !loadedUploadConflictKeys.contains(key) else { return }
        
        do {
            let files = try await fileManager.listFiles(deviceId: deviceId, parentId: parentId)
            uploadConflictNameCache[key] = Set(files.map(\.name))
            loadedUploadConflictKeys.insert(key)
        } catch {
            Logger.warning("预加载上传冲突缓存失败: \(error.localizedDescription)")
        }
    }
    
    private func hasCachedUploadConflict(deviceId: String, fileName: String, parentId: String?) async throws -> Bool {
        let key = UploadDestinationKey(deviceId: deviceId, parentId: parentId)
        
        if !loadedUploadConflictKeys.contains(key) {
            let files = try await fileManager.listFiles(deviceId: deviceId, parentId: parentId)
            uploadConflictNameCache[key] = Set(files.map(\.name))
            loadedUploadConflictKeys.insert(key)
        }
        
        return uploadConflictNameCache[key]?.contains(fileName) ?? false
    }
    
    private func recordUploadedName(_ fileName: String, deviceId: String, parentId: String?) {
        let key = UploadDestinationKey(deviceId: deviceId, parentId: parentId)
        uploadConflictNameCache[key, default: []].insert(fileName)
        loadedUploadConflictKeys.insert(key)
    }
}
