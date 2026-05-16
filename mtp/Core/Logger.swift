//
//  Logger.swift
//  mtp
//
//  Created by Li on 2026/4/19.
//

import Foundation
import os.log

/// 统一的日志管理器，避免重复和冗余的日志输出
final class Logger {
    static let shared = Logger()
    
    // 使用 OSLog 进行结构化日志记录
    private static let subsystem = "com.runsli.mtpmate"
    private let mtpLogger = os.Logger(subsystem: Logger.subsystem, category: "MTP")
    private let fileLogger = os.Logger(subsystem: Logger.subsystem, category: "FileOperation")
    private let usbLogger = os.Logger(subsystem: Logger.subsystem, category: "USB")
    
    // 日志级别
    enum Level {
        case debug
        case info
        case warning
        case error
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
        
        var prefix: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }
    
    // 操作类型
    enum Operation {
        case deviceScan
        case deviceConnect
        case fileOperation
        case usbMonitor
        
        var emoji: String {
            switch self {
            case .deviceScan: return "📱"
            case .deviceConnect: return "🔗"
            case .fileOperation: return "📁"
            case .usbMonitor: return "🔌"
            }
        }
        
        var logger: os.Logger {
            switch self {
            case .deviceScan, .deviceConnect:
                return Logger.shared.mtpLogger
            case .fileOperation:
                return Logger.shared.fileLogger
            case .usbMonitor:
                return Logger.shared.usbLogger
            }
        }
    }
    
    private var lastLogTime: [String: Date] = [:]
    private let minLogInterval: TimeInterval = 1.0 // 最小日志间隔（秒）
    private let queue = DispatchQueue(label: "com.runsli.mtpmate.logger", qos: .utility)
    
    private init() {}
    
    /// 记录日志，自动去重
    func log(_ level: Level, operation: Operation? = nil, message: String, file: String = #file, function: String = #function) {
        queue.async {
            let key = "\(file):\(function):\(message)"
            let now = Date()
            
            // 检查是否需要去重
            if let lastTime = self.lastLogTime[key], now.timeIntervalSince(lastTime) < self.minLogInterval {
                return // 跳过重复日志
            }
            
            self.lastLogTime[key] = now
            
            let prefix = operation?.emoji ?? level.prefix
            let logMessage = "\(prefix) \(message)"
            
            // 输出到控制台（仅在调试模式）
            #if DEBUG
            print(logMessage)
            #endif
            
            // 输出到系统日志
            let logger = operation?.logger ?? self.mtpLogger
            logger.log(level: level.osLogType, "\(logMessage)")
        }
    }
    
    /// 记录设备扫描开始
    func logScanStart() {
        log(.info, operation: .deviceScan, message: "开始扫描MTP设备")
    }
    
    /// 记录设备扫描结果
    func logScanResult(deviceCount: Int, devices: [String] = []) {
        if deviceCount == 0 {
            log(.warning, operation: .deviceScan, message: "未发现MTP设备")
        } else {
            log(.info, operation: .deviceScan, message: "发现 \(deviceCount) 个MTP设备")
            if !devices.isEmpty && devices.count <= 3 {
                // 只显示前3个设备名称，避免日志过长
                log(.debug, message: "设备: \(devices.joined(separator: ", "))")
            }
        }
    }
    
    /// 记录设备连接状态
    func logDeviceConnection(_ deviceName: String, connected: Bool) {
        let status = connected ? "已连接" : "已断开"
        log(.info, operation: .deviceConnect, message: "\(deviceName) \(status)")
    }
    
    /// 记录文件操作
    func logFileOperation(_ operation: String, fileName: String, success: Bool, error: Error? = nil) {
        if success {
            log(.info, operation: .fileOperation, message: "\(operation): \(fileName)")
        } else {
            let errorMsg = error?.localizedDescription ?? "未知错误"
            log(.error, operation: .fileOperation, message: "\(operation)失败: \(fileName) - \(errorMsg)")
        }
    }
    
    /// 记录批量文件操作结果
    func logBatchOperation(_ operation: String, successCount: Int, failCount: Int) {
        if failCount == 0 {
            log(.info, operation: .fileOperation, message: "\(operation)完成: \(successCount) 个文件")
        } else {
            log(.warning, operation: .fileOperation, message: "\(operation)完成: 成功 \(successCount) 个，失败 \(failCount) 个")
        }
    }
    
    /// 记录USB设备变化
    func logUSBDeviceChange(_ deviceName: String, connected: Bool) {
        let status = connected ? "插入" : "拔出"
        log(.info, operation: .usbMonitor, message: "USB设备\(status): \(deviceName)")
    }
    
    /// 清理旧的日志记录
    func cleanup() {
        queue.async {
            let cutoffTime = Date().addingTimeInterval(-300) // 5分钟前
            self.lastLogTime = self.lastLogTime.filter { $0.value > cutoffTime }
        }
    }
}

// MARK: - 便捷扩展

extension Logger {
    /// 调试日志
    static func debug(_ message: String, file: String = #file, function: String = #function) {
        shared.log(.debug, message: message, file: file, function: function)
    }
    
    /// 信息日志
    static func info(_ message: String, file: String = #file, function: String = #function) {
        shared.log(.info, message: message, file: file, function: function)
    }
    
    /// 警告日志
    static func warning(_ message: String, file: String = #file, function: String = #function) {
        shared.log(.warning, message: message, file: file, function: function)
    }
    
    /// 错误日志
    static func error(_ message: String, file: String = #file, function: String = #function) {
        shared.log(.error, message: message, file: file, function: function)
    }
}