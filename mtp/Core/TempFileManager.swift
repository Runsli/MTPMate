//
//  TempFileManager.swift
//  mtp
//
//  Created by Li on 2026/4/19.
//

import Foundation

/// 临时文件管理器，负责创建和清理临时文件
@MainActor
final class TempFileManager {
    static let shared = TempFileManager()
    
    private var tempFiles: Set<URL> = []
    private let cleanupDelay: TimeInterval = 60 // 60秒后清理
    
    private init() {
        // 启动时清理旧的临时文件
        cleanupOldTempFiles()
    }
    
    /// 创建临时文件路径
    func createTempFile(for fileName: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(fileName)
        
        // 如果文件已存在，生成唯一名称
        if FileManager.default.fileExists(atPath: tempURL.path) {
            let uniqueName = generateUniqueName(for: fileName)
            let uniqueURL = tempDir.appendingPathComponent(uniqueName)
            tempFiles.insert(uniqueURL)
            return uniqueURL
        }
        
        tempFiles.insert(tempURL)
        return tempURL
    }
    
    /// 注册临时文件以便后续清理
    func registerTempFile(_ url: URL) {
        tempFiles.insert(url)
    }
    
    /// 延迟清理临时文件
    func scheduleCleanup(for url: URL, delay: TimeInterval? = nil) {
        let cleanupTime = delay ?? cleanupDelay
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(cleanupTime * 1_000_000_000))
            self.cleanup(url)  // 在主线程上调用
        }
    }
    
    /// 立即清理临时文件
    func cleanup(_ url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                Logger.debug("清理临时文件: \(url.lastPathComponent)")
            }
            tempFiles.remove(url)
        } catch {
            Logger.error("清理临时文件失败: \(error.localizedDescription)")
        }
    }
    
    /// 清理所有临时文件
    func cleanupAll() {
        for url in tempFiles {
            cleanup(url)
        }
    }
    
    /// 清理旧的临时文件（启动时调用）
    private func cleanupOldTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            let cutoffDate = Date().addingTimeInterval(-3600) // 1小时前
            
            for url in contents {
                // 只清理我们应用创建的文件（可以通过前缀或其他标识）
                guard url.lastPathComponent.hasPrefix("mtp_") else { continue }
                
                let attributes = try url.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = attributes.creationDate, creationDate < cutoffDate {
                    try? FileManager.default.removeItem(at: url)
                    Logger.debug("清理旧临时文件: \(url.lastPathComponent)")
                }
            }
        } catch {
            Logger.error("清理旧临时文件失败: \(error.localizedDescription)")
        }
    }
    
    /// 生成唯一文件名
    private func generateUniqueName(for fileName: String) -> String {
        let nameWithoutExtension = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let timestamp = Int(Date().timeIntervalSince1970)
        
        if ext.isEmpty {
            return "mtp_\(nameWithoutExtension)_\(timestamp)"
        } else {
            return "mtp_\(nameWithoutExtension)_\(timestamp).\(ext)"
        }
    }
}
