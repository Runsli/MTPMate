//
//  TransferTypes.swift
//  mtp
//
//  Shared transfer-related value types.
//

import Foundation

/// 传输方向
enum TransferDirection {
    case upload
    case download
}

/// 文件冲突解决策略
enum ConflictResolution: String, CaseIterable, Identifiable {
    case ask
    case rename
    case skip
    case overwrite
    
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
