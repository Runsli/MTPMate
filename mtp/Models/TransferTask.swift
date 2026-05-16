//
//  TransferTask.swift
//  mtp
//
//  文件传输任务模型
//

import Foundation
import Combine

/// 传输任务状态
enum TransferStatus: Equatable {
    case pending        // 等待中
    case transferring   // 传输中
    case paused         // 已暂停
    case completed      // 已完成
    case failed(Error)  // 失败
    case cancelled      // 已取消
    
    static func == (lhs: TransferStatus, rhs: TransferStatus) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending),
             (.transferring, .transferring),
             (.paused, .paused),
             (.completed, .completed),
             (.cancelled, .cancelled):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// 传输方向
enum TransferDirection {
    case upload     // 上传到设备
    case download   // 从设备下载
}

/// 冲突解决策略
enum ConflictResolution: String, CaseIterable, Identifiable {
    case ask        // 询问用户
    case rename     // 自动重命名
    case skip       // 跳过
    case overwrite  // 覆盖
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .ask: return "每次询问"
        case .rename: return "自动重命名"
        case .skip: return "跳过"
        case .overwrite: return "覆盖"
        }
    }
}

/// 文件传输任务
@MainActor
class TransferTask: Identifiable, ObservableObject {
    let id: UUID
    let fileName: String
    let fileSize: Int64
    let direction: TransferDirection
    
    // 源和目标
    let sourceURL: URL?          // 本地文件路径（上传时使用）
    let sourceFileId: String?    // MTP文件ID（下载时使用）
    let destinationURL: URL?     // 本地目标路径（下载时使用）
    let destinationParentId: String? // MTP目标文件夹ID（上传时使用）
    
    @Published var status: TransferStatus = .pending
    @Published var progress: Double = 0.0
    @Published var transferredBytes: Int64 = 0
    @Published var speed: Double = 0.0 // 字节/秒
    @Published var estimatedTimeRemaining: TimeInterval = 0
    
    // 冲突处理
    var conflictResolution: ConflictResolution = .ask
    var resolvedFileName: String?
    
    // 任务控制
    var task: Task<Void, Never>?
    private var startTime: Date?
    private var lastUpdateTime: Date?
    private var lastTransferredBytes: Int64 = 0
    
    init(
        fileName: String,
        fileSize: Int64,
        direction: TransferDirection,
        sourceURL: URL? = nil,
        sourceFileId: String? = nil,
        destinationURL: URL? = nil,
        destinationParentId: String? = nil
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.fileSize = fileSize
        self.direction = direction
        self.sourceURL = sourceURL
        self.sourceFileId = sourceFileId
        self.destinationURL = destinationURL
        self.destinationParentId = destinationParentId
    }
    
    /// 更新进度
    func updateProgress(_ newProgress: Double, transferred: Int64) {
        let now = Date()
        
        if startTime == nil {
            startTime = now
        }
        
        progress = newProgress
        transferredBytes = transferred
        
        // 计算速度（每秒更新一次）
        if let lastUpdate = lastUpdateTime, now.timeIntervalSince(lastUpdate) >= 1.0 {
            let bytesTransferred = transferred - lastTransferredBytes
            let timeElapsed = now.timeIntervalSince(lastUpdate)
            speed = Double(bytesTransferred) / timeElapsed
            
            // 估算剩余时间
            if speed > 0 {
                let remainingBytes = fileSize - transferred
                estimatedTimeRemaining = Double(remainingBytes) / speed
            }
            
            lastUpdateTime = now
            lastTransferredBytes = transferred
        } else if lastUpdateTime == nil {
            lastUpdateTime = now
            lastTransferredBytes = transferred
        }
    }
    
    /// 格式化速度
    var formattedSpeed: String {
        if speed < 1024 {
            return String(format: "%.0f B/s", speed)
        } else if speed < 1024 * 1024 {
            return String(format: "%.1f KB/s", speed / 1024)
        } else {
            return String(format: "%.1f MB/s", speed / (1024 * 1024))
        }
    }
    
    /// 格式化剩余时间
    var formattedTimeRemaining: String {
        if estimatedTimeRemaining < 60 {
            return String(format: "%.0f秒", estimatedTimeRemaining)
        } else if estimatedTimeRemaining < 3600 {
            return String(format: "%.0f分钟", estimatedTimeRemaining / 60)
        } else {
            return String(format: "%.1f小时", estimatedTimeRemaining / 3600)
        }
    }
    
    /// 格式化文件大小
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}
