//
//  DetectedDevice.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import Foundation

/// 检测到的设备（包括MTP和非MTP设备）
struct DetectedDevice: Identifiable {
    let id: String
    let name: String
    let vendorName: String
    let isAndroidDevice: Bool
    let isMTPCapable: Bool
    let isMTPEnabled: Bool // 是否已启用MTP
    let usbDeviceInfo: USBDeviceInfo?
    let mtpDevice: MTPDevice?
    
    var displayName: String {
        if let mtpDevice = mtpDevice {
            return mtpDevice.name
        } else if let usbInfo = usbDeviceInfo {
            return usbInfo.displayName
        } else {
            return name
        }
    }
    
    var statusDescription: String {
        if isMTPEnabled {
            return "MTP已启用"
        } else if isMTPCapable {
            return "未启用MTP"
        } else {
            return "不支持MTP"
        }
    }
    
    var statusColor: String {
        if isMTPEnabled {
            return "green"
        } else if isMTPCapable {
            return "orange"
        } else {
            return "gray"
        }
    }
    
    // 从USB设备信息创建
    static func fromUSBDevice(_ usbInfo: USBDeviceInfo) -> DetectedDevice {
        return DetectedDevice(
            id: "usb-\(usbInfo.vendorID)-\(usbInfo.productID)",
            name: usbInfo.displayName,
            vendorName: usbInfo.vendorName,
            isAndroidDevice: usbInfo.isAndroidDevice,
            isMTPCapable: usbInfo.isMTPCapable,
            isMTPEnabled: false,
            usbDeviceInfo: usbInfo,
            mtpDevice: nil
        )
    }
    
    // 从MTP设备创建
    static func fromMTPDevice(_ mtpDevice: MTPDevice) -> DetectedDevice {
        return DetectedDevice(
            id: "mtp-\(mtpDevice.id)",
            name: mtpDevice.name,
            vendorName: mtpDevice.manufacturer,
            isAndroidDevice: true,
            isMTPCapable: true,
            isMTPEnabled: true,
            usbDeviceInfo: nil,
            mtpDevice: mtpDevice
        )
    }
}