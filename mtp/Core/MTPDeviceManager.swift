//
//  MTPDeviceManager.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import Foundation
import Combine

// MARK: - 线程安全的设备信息缓存

actor DeviceInfoCache {
    private var cache: [String: MTPDeviceInfo] = [:]
    
    func get(_ key: String) -> MTPDeviceInfo? {
        cache[key]
    }
    
    func set(_ key: String, value: MTPDeviceInfo) {
        cache[key] = value
    }
    
    func remove(_ key: String) {
        cache.removeValue(forKey: key)
    }
    
    func clear() {
        cache.removeAll()
    }
}

@MainActor
final class MTPDeviceManager: ObservableObject {
    static let shared = MTPDeviceManager()
    
    @Published var connectedDevices: [MTPDevice] = []
    @Published var isScanning: Bool = false
    
    private let deviceInfoCache = DeviceInfoCache()
    
    private init() {
        // 初始化 libmtp
        _ = MTPBridge.initializeMTP()
    }
    
    // MARK: - 设备扫描
    
    func scanDevices() async throws -> [MTPDevice] {
        isScanning = true
        defer { isScanning = false }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    Logger.shared.logScanStart()
                    
                    // scanDevices returns non-nullable NSArray in Swift (empty array on error)
                    let deviceInfos = try MTPBridge.scanDevices()
                    
                    // 收集设备名称用于日志
                    let deviceNames = deviceInfos.map { info in
                        let name = info.manufacturer != "Unknown" && info.model != "Unknown" 
                            ? "\(info.manufacturer) \(info.model)" 
                            : (info.model != "Unknown" ? info.model : "未知设备")
                        return name
                    }
                    
                    Logger.shared.logScanResult(deviceCount: deviceInfos.count, devices: deviceNames)
                    
                    Task { @MainActor in
                        var devices: [MTPDevice] = []
                        for info in deviceInfos {
                            let deviceId = info.deviceId ?? "unknown-device"
                            await self.deviceInfoCache.set(deviceId, value: info)
                            devices.append(self.convertToMTPDevice(info))
                        }
                        
                        Logger.debug("转换为 \(devices.count) 个MTPDevice对象")
                        
                        self.connectedDevices = devices
                        continuation.resume(returning: devices)
                    }
                } catch let error as NSError {
                    Logger.error("扫描设备时发生NSError: \(error.localizedDescription) (代码: \(error.code))")
                    
                    // 检查是否是权限问题
                    if error.code == -3 || error.localizedDescription.contains("Unable to initialize device") {
                        let permissionError = NSError(
                            domain: "MTPError",
                            code: -1000,
                            userInfo: [
                                NSLocalizedDescriptionKey: "权限不足，无法访问USB设备",
                                NSLocalizedRecoverySuggestionErrorKey: """
                                请尝试以下解决方案：
                                1. 确保手机已解锁并选择"文件传输(MTP)"模式
                                2. 在手机上点击"信任此计算机"
                                3. 重新插拔 USB 连接后重试
                                4. 如仍失败，请使用 mtp-detect 检查 libmtp 权限状态
                                """
                            ]
                        )
                        continuation.resume(throwing: permissionError)
                    } else {
                        continuation.resume(throwing: error)
                    }
                } catch {
                    Logger.error("扫描设备时发生其他错误: \(error.localizedDescription)")
                    continuation.resume(throwing: MTPError.scanFailed)
                }
            }
        }
    }
    
    /// 刷新设备信息但保持连接状态
    func refreshDevices() async throws -> [MTPDevice] {
        Logger.debug("刷新设备信息（保持连接）")
        return try await scanDevices()
    }
    
    // MARK: - 设备连接
    
    func connectDevice(_ deviceId: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // openDevice returns Void (throws on failure)
                    try MTPBridge.openDevice(deviceId)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func disconnectDevice(_ deviceId: String) {
        MTPBridge.closeDevice(deviceId)
        connectedDevices.removeAll { $0.id == deviceId }
    }
    
    // MARK: - 设备信息
    
    func getDeviceInfo(_ deviceId: String) async throws -> MTPDevice {
        // 先检查缓存
        if let cachedInfo = await deviceInfoCache.get(deviceId) {
            return convertToMTPDevice(cachedInfo)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // getDeviceInfo returns MTPDeviceInfo (throws on error, not nullable in Swift)
                    let info = try MTPBridge.getDeviceInfo(deviceId)
                    
                    Task { @MainActor in
                        await self.deviceInfoCache.set(deviceId, value: info)
                        let device = self.convertToMTPDevice(info)
                        continuation.resume(returning: device)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func convertToMTPDevice(_ info: MTPDeviceInfo) -> MTPDevice {
        let storageInfo = MTPDevice.StorageInfo(
            totalSpace: Int64(info.totalStorage),
            freeSpace: Int64(info.freeStorage)
        )
        
        // 生成更好的设备显示名称
        let deviceName: String
        if info.manufacturer != "Unknown" && info.model != "Unknown" {
            // 如果制造商和型号都可用，组合显示
            if info.manufacturer.lowercased() == info.model.lowercased() {
                // 如果制造商名称已包含在型号中，只显示型号
                deviceName = info.model
            } else if info.model.lowercased().contains(info.manufacturer.lowercased()) {
                // 如果型号已包含制造商名称，只显示型号
                deviceName = info.model
            } else {
                // 组合显示：制造商 + 型号
                deviceName = "\(info.manufacturer) \(info.model)"
            }
        } else if info.model != "Unknown" {
            deviceName = info.model
        } else if info.manufacturer != "Unknown" {
            deviceName = info.manufacturer
        } else {
            deviceName = "MTP设备"
        }
        
        return MTPDevice(
            id: info.deviceId ?? "unknown-device",
            name: deviceName,
            manufacturer: info.manufacturer,
            model: info.model,
            serialNumber: info.serialNumber,
            isConnected: true,
            batteryLevel: info.batteryLevel >= 0 ? Int(info.batteryLevel) : nil,
            batteryTemperature: nil, // MTP 不提供温度信息
            storageInfo: storageInfo,
            usbSpeed: "USB 2.0", // 可以从设备版本推断
            systemVersion: info.deviceVersion,
            lastConnectedDate: Date()
        )
    }
}

// MARK: - 错误类型

enum MTPError: LocalizedError {
    case scanFailed
    case connectionFailed
    case deviceNotFound
    case operationFailed(String)
    case permissionDenied
    case deviceDisconnected
    case fileNotFound
    case insufficientStorage
    case timeout
    case invalidParameter(String)
    case operationCancelled
    
    var errorDescription: String? {
        switch self {
        case .scanFailed:
            return "扫描设备失败"
        case .connectionFailed:
            return "连接设备失败"
        case .deviceNotFound:
            return "设备未找到"
        case .operationFailed(let message):
            return message
        case .permissionDenied:
            return "权限不足，无法访问USB设备"
        case .deviceDisconnected:
            return "设备已断开连接"
        case .fileNotFound:
            return "文件未找到"
        case .insufficientStorage:
            return "存储空间不足"
        case .timeout:
            return "操作超时"
        case .invalidParameter(let param):
            return "参数无效: \(param)"
        case .operationCancelled:
            return "操作已取消"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return """
            请尝试以下解决方案：
            1. 确保手机已解锁并选择"文件传输(MTP)"模式
            2. 在手机上点击"信任此计算机"
            3. 如果问题持续，请使用 sudo 运行应用
            """
        case .deviceDisconnected:
            return "请重新连接设备并重试"
        case .insufficientStorage:
            return "请清理设备存储空间后重试"
        case .timeout:
            return "请检查设备连接状态并重试"
        case .connectionFailed:
            return "请确保设备已解锁并启用MTP模式"
        default:
            return nil
        }
    }
}
