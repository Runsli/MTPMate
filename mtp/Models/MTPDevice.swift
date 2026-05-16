//
//  MTPDevice.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import Foundation

struct MTPDevice: Identifiable {
    let id: String
    let name: String
    let manufacturer: String
    let model: String
    let serialNumber: String
    var isConnected: Bool
    var batteryLevel: Int?
    var batteryTemperature: Int? // 摄氏度
    var storageInfo: StorageInfo?
    var usbSpeed: String? // USB 2.0 / USB 3.0
    var systemVersion: String?
    var lastConnectedDate: Date?
    
    struct StorageInfo {
        let totalSpace: Int64
        let freeSpace: Int64
        
        var usedSpace: Int64 {
            guard totalSpace >= 0, freeSpace >= 0, freeSpace <= totalSpace else {
                return 0
            }
            return totalSpace - freeSpace
        }
        
        var usedPercentage: Double {
            guard totalSpace > 0, freeSpace >= 0, freeSpace <= totalSpace else { 
                return 0 
            }
            return Double(usedSpace) / Double(totalSpace)
        }
    }
}

// 模拟数据
extension MTPDevice {
    static let sample = MTPDevice(
        id: "device_001",
        name: "Pixel 8 Pro",
        manufacturer: "Google",
        model: "Pixel 8 Pro",
        serialNumber: "1234567890ABCDEF",
        isConnected: true,
        batteryLevel: 85,
        batteryTemperature: 32,
        storageInfo: StorageInfo(totalSpace: 128_000_000_000, freeSpace: 45_000_000_000),
        usbSpeed: "USB 3.0",
        systemVersion: "Android 14",
        lastConnectedDate: Date()
    )
    
    static let samples = [
        sample,
        MTPDevice(
            id: "device_002",
            name: "Samsung Galaxy S24",
            manufacturer: "Samsung",
            model: "SM-S921B",
            serialNumber: "ABCDEF1234567890",
            isConnected: false,
            batteryLevel: 60,
            batteryTemperature: 28,
            storageInfo: StorageInfo(totalSpace: 256_000_000_000, freeSpace: 120_000_000_000),
            usbSpeed: "USB 2.0",
            systemVersion: "Android 14",
            lastConnectedDate: Date().addingTimeInterval(-3600)
        )
    ]
}
