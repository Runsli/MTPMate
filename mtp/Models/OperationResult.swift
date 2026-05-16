//
//  OperationResult.swift
//  mtp
//
//  Created by Li on 2026/4/19.
//

import Foundation

/// 批量操作结果
struct OperationResult<T> {
    let succeeded: [T]
    let failed: [(T, Error)]
    
    var successCount: Int { succeeded.count }
    var failCount: Int { failed.count }
    var totalCount: Int { successCount + failCount }
    
    var isFullSuccess: Bool { failCount == 0 }
    var isPartialSuccess: Bool { successCount > 0 && failCount > 0 }
    var isFullFailure: Bool { successCount == 0 && failCount > 0 }
    
    /// 生成用户友好的摘要信息
    var summary: String {
        if isFullSuccess {
            return "成功完成 \(successCount) 个操作"
        } else if isPartialSuccess {
            return "完成 \(totalCount) 个操作：成功 \(successCount) 个，失败 \(failCount) 个"
        } else if isFullFailure {
            return "所有操作失败（\(failCount) 个）"
        } else {
            return "未执行任何操作"
        }
    }
    
    /// 获取失败的详细信息
    var failureDetails: String {
        failed.map { item, error in
            "\(item): \(error.localizedDescription)"
        }.joined(separator: "\n")
    }
}

/// 文件操作结果
typealias FileOperationResult = OperationResult<FileItem>

/// 传输进度信息
struct TransferProgress {
    let fileName: String
    let bytesTransferred: Int64
    let totalBytes: Int64
    let percentage: Double
    let speed: Double? // 字节/秒
    let estimatedTimeRemaining: TimeInterval?
    
    var formattedSpeed: String? {
        guard let speed = speed else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
    }
    
    var formattedTimeRemaining: String? {
        guard let time = estimatedTimeRemaining else { return nil }
        
        if time < 60 {
            return String(format: "%.0f秒", time)
        } else if time < 3600 {
            return String(format: "%.0f分钟", time / 60)
        } else {
            return String(format: "%.1f小时", time / 3600)
        }
    }
}

/// 操作队列项
struct OperationQueueItem: Identifiable {
    let id = UUID()
    let type: OperationType
    let files: [FileItem]
    var status: OperationStatus
    var progress: Double
    var error: Error?
    
    enum OperationType {
        case download
        case upload
        case delete
        case copy
        case move
    }
    
    enum OperationStatus {
        case pending
        case inProgress
        case completed
        case failed
        case cancelled
    }
    
    var displayName: String {
        switch type {
        case .download: return "下载"
        case .upload: return "上传"
        case .delete: return "删除"
        case .copy: return "复制"
        case .move: return "移动"
        }
    }
}
