//
//  USBDeviceMonitor.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import Foundation
import IOKit
import IOKit.usb
import Combine

final class USBDeviceMonitor {
    static let shared = USBDeviceMonitor()
    
    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0
    private var isMonitoring = false
    
    // 回调闭包，当检测到USB设备变化时调用
    var onDeviceChanged: (() -> Void)?
    var onUSBDeviceDetected: ((USBDeviceInfo, Bool) -> Void)? // 设备信息，是否插入
    
    // 当前检测到的USB设备
    @Published var detectedUSBDevices: [USBDeviceInfo] = []
    
    // 智能扫描重试管理
    private var pendingScans: [String: Int] = [:] // deviceKey -> retryCount
    private var scanWorkItems: [String: DispatchWorkItem] = [:]
    
    private init() {}
    
    deinit {
        stopMonitoring()
    }
    
    func startMonitoring() {
        guard !isMonitoring else {
            Logger.warning("USB监听已在运行")
            return
        }
        
        Logger.info("开始监听USB设备插拔...")
        
        // 创建通知端口
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notificationPort = notificationPort else {
            Logger.error("无法创建IONotificationPort")
            return
        }
        
        // 将通知端口添加到运行循环
        let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue()
        guard let source = runLoopSource else {
            Logger.error("无法获取RunLoopSource")
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
            return
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
        
        // 监听USB设备插入
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        let addedCallback: IOServiceMatchingCallback = { (refcon, iterator) in
            let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handleDeviceAdded(iterator: iterator)
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let addResult = IOServiceAddMatchingNotification(
            notificationPort,
            kIOFirstMatchNotification,
            matchingDict,
            addedCallback,
            selfPtr,
            &addedIterator
        )
        
        if addResult == KERN_SUCCESS {
            // 处理已存在的设备
            handleDeviceAdded(iterator: addedIterator)
        } else {
            Logger.error("无法注册USB设备插入监听")
            stopMonitoring()
            return
        }
        
        // 监听USB设备拔出
        let matchingDict2 = IOServiceMatching(kIOUSBDeviceClassName)
        let removedCallback: IOServiceMatchingCallback = { (refcon, iterator) in
            let monitor = Unmanaged<USBDeviceMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handleDeviceRemoved(iterator: iterator)
        }
        
        let removeResult = IOServiceAddMatchingNotification(
            notificationPort,
            kIOTerminatedNotification,
            matchingDict2,
            removedCallback,
            selfPtr,
            &removedIterator
        )
        
        if removeResult == KERN_SUCCESS {
            // 处理已存在的设备
            handleDeviceRemoved(iterator: removedIterator)
        } else {
            Logger.error("无法注册USB设备拔出监听")
            stopMonitoring()
            return
        }
        
        isMonitoring = true
        Logger.info("USB设备监听已启动")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        Logger.info("停止监听USB设备插拔...")
        
        if addedIterator != 0 {
            IOObjectRelease(addedIterator)
            addedIterator = 0
        }
        
        if removedIterator != 0 {
            IOObjectRelease(removedIterator)
            removedIterator = 0
        }
        
        if let notificationPort = notificationPort {
            let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue()
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, CFRunLoopMode.defaultMode)
            }
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }
        
        isMonitoring = false
        Logger.info("USB设备监听已停止")
    }
    
    private func handleDeviceAdded(iterator: io_iterator_t) {
        var service: io_service_t = 0
        
        while case let nextService = IOIteratorNext(iterator), nextService != 0 {
            service = nextService
            defer { IOObjectRelease(service) }
            
            // 获取设备信息
            if let deviceInfo = getDeviceInfo(service: service) {
                Logger.shared.logUSBDeviceChange(deviceInfo.displayName, connected: true)
                Logger.debug("厂商: \(deviceInfo.vendorName) (VID: \(String(format: "%04X", deviceInfo.vendorID)))")
                Logger.debug("产品ID: \(String(format: "%04X", deviceInfo.productID))")
                Logger.debug("Android设备: \(deviceInfo.isAndroidDevice ? "是" : "否")")
                Logger.debug("支持MTP: \(deviceInfo.isMTPCapable ? "是" : "否")")
                
                // 如果是Android设备，添加到检测列表
                if deviceInfo.isAndroidDevice {
                    DispatchQueue.main.async {
                        // 避免重复添加
                        if !self.detectedUSBDevices.contains(where: { $0.vendorID == deviceInfo.vendorID && $0.productID == deviceInfo.productID }) {
                            self.detectedUSBDevices.append(deviceInfo)
                        }
                        
                        // 通知UI更新
                        self.onUSBDeviceDetected?(deviceInfo, true)
                    }
                    
                    // 如果支持MTP，使用智能重试机制触发扫描
                    if deviceInfo.isMTPCapable {
                        Logger.info("检测到MTP设备，启动智能扫描...")
                        self.scheduleSmartScan(for: deviceInfo)
                    }
                }
            }
        }
    }
    
    private func handleDeviceRemoved(iterator: io_iterator_t) {
        var service: io_service_t = 0
        
        while case let nextService = IOIteratorNext(iterator), nextService != 0 {
            service = nextService
            defer { IOObjectRelease(service) }
            
            // 获取设备信息用于匹配
            if let deviceInfo = getDeviceInfo(service: service) {
                Logger.shared.logUSBDeviceChange(deviceInfo.displayName, connected: false)
                
                if deviceInfo.isAndroidDevice {
                    // 取消该设备的待处理扫描
                    cancelPendingScan(for: deviceInfo)
                    
                    DispatchQueue.main.async {
                        // 从检测列表中移除
                        self.detectedUSBDevices.removeAll { device in
                            device.vendorID == deviceInfo.vendorID && device.productID == deviceInfo.productID
                        }
                        
                        // 通知UI更新
                        self.onUSBDeviceDetected?(deviceInfo, false)
                        
                        // 触发MTP设备扫描以更新列表
                        self.onDeviceChanged?()
                    }
                }
            }
        }
    }
    
    private func getDeviceInfo(service: io_service_t) -> USBDeviceInfo? {
        var vendorID: UInt16 = 0
        var productID: UInt16 = 0
        var deviceName = "Unknown Device"
        var manufacturerName = "Unknown"
        var serialNumber: String?
        var deviceClass: UInt8 = 0
        var deviceSubClass: UInt8 = 0
        
        // 获取厂商ID
        if let vendorIDRef = IORegistryEntryCreateCFProperty(service, "idVendor" as CFString, kCFAllocatorDefault, 0) {
            let vendorIDValue = vendorIDRef.takeRetainedValue()
            let cfNumber = unsafeBitCast(vendorIDValue, to: CFNumber.self)
            CFNumberGetValue(cfNumber, .sInt16Type, &vendorID)
        }
        
        // 获取产品ID
        if let productIDRef = IORegistryEntryCreateCFProperty(service, "idProduct" as CFString, kCFAllocatorDefault, 0) {
            let productIDValue = productIDRef.takeRetainedValue()
            let cfNumber = unsafeBitCast(productIDValue, to: CFNumber.self)
            CFNumberGetValue(cfNumber, .sInt16Type, &productID)
        }
        
        // 获取设备类别
        if let deviceClassRef = IORegistryEntryCreateCFProperty(service, "bDeviceClass" as CFString, kCFAllocatorDefault, 0) {
            let deviceClassValue = deviceClassRef.takeRetainedValue()
            let cfNumber = unsafeBitCast(deviceClassValue, to: CFNumber.self)
            CFNumberGetValue(cfNumber, .sInt8Type, &deviceClass)
        }
        
        // 获取设备子类别
        if let deviceSubClassRef = IORegistryEntryCreateCFProperty(service, "bDeviceSubClass" as CFString, kCFAllocatorDefault, 0) {
            let deviceSubClassValue = deviceSubClassRef.takeRetainedValue()
            let cfNumber = unsafeBitCast(deviceSubClassValue, to: CFNumber.self)
            CFNumberGetValue(cfNumber, .sInt8Type, &deviceSubClass)
        }
        
        // 获取设备名称（多个可能的属性名）
        let nameProperties = [
            "USB Product Name",
            "kUSBProductString",
            "Product Name",
            "IORegistryEntryName"
        ]
        
        for property in nameProperties {
            if let nameRef = IORegistryEntryCreateCFProperty(service, property as CFString, kCFAllocatorDefault, 0) {
                let nameValue = nameRef.takeRetainedValue()
                if CFGetTypeID(nameValue) == CFStringGetTypeID() {
                    let name = nameValue as! String
                    if !name.isEmpty && name != "Unknown Device" {
                        deviceName = name
                        break
                    }
                }
            }
        }
        
        // 获取制造商名称
        let manufacturerProperties = [
            "USB Vendor Name",
            "kUSBVendorString",
            "Manufacturer",
            "Vendor Name"
        ]
        
        for property in manufacturerProperties {
            if let manufacturerRef = IORegistryEntryCreateCFProperty(service, property as CFString, kCFAllocatorDefault, 0) {
                let manufacturerValue = manufacturerRef.takeRetainedValue()
                if CFGetTypeID(manufacturerValue) == CFStringGetTypeID() {
                    let manufacturer = manufacturerValue as! String
                    if !manufacturer.isEmpty && manufacturer != "Unknown" {
                        manufacturerName = manufacturer
                        break
                    }
                }
            }
        }
        
        // 获取序列号
        if let serialRef = IORegistryEntryCreateCFProperty(service, "USB Serial Number" as CFString, kCFAllocatorDefault, 0) {
            let serialValue = serialRef.takeRetainedValue()
            if CFGetTypeID(serialValue) == CFStringGetTypeID() {
                let serial = serialValue as! String
                if !serial.isEmpty {
                    serialNumber = serial
                }
            }
        }
        
        // 判断是否为Android设备
        let isAndroid = isAndroidDevice(vendorID: vendorID, productID: productID, deviceName: deviceName, manufacturerName: manufacturerName)
        
        // 判断是否支持MTP（基于设备类别或已知信息）
        let isMTPCapable = isAndroid || deviceClass == 6 || deviceName.lowercased().contains("mtp")
        
        return USBDeviceInfo(
            name: deviceName,
            vendorID: vendorID,
            productID: productID,
            manufacturerName: manufacturerName,
            serialNumber: serialNumber,
            deviceClass: deviceClass,
            deviceSubClass: deviceSubClass,
            isAndroidDevice: isAndroid,
            isMTPCapable: isMTPCapable
        )
    }
    
    private func isAndroidDevice(vendorID: UInt16, productID: UInt16, deviceName: String, manufacturerName: String) -> Bool {
        // 常见的Android设备厂商ID（扩展列表）
        let androidVendorIDs: Set<UInt16> = [
            0x18D1, // Google
            0x04E8, // Samsung
            0x2717, // Xiaomi
            0x2A70, // OnePlus
            0x0BB4, // HTC
            0x12D1, // Huawei
            0x19D2, // ZTE
            0x0FCE, // Sony Ericsson
            0x22B8, // Motorola
            0x1004, // LG
            0x0E8D, // MediaTek
            0x1F3A, // Allwinner
            0x2916, // Android
            0x1782, // Spreadtrum
            0x2A47, // Realme
            0x2D95, // Vivo
            0x29A9, // Oppo
            0x05C6, // Qualcomm (某些设备使用)
            0x0489, // Foxconn (代工厂)
            0x1BBB, // T-Mobile
            0x0B05, // ASUS
            0x0955, // NVIDIA
            0x1D91, // BYD
            0x2A45, // Meizu
            0x2AE5, // Fairphone
            0x2C7C, // Quectel
        ]
        
        // 检查是否是已知的Android设备厂商
        if androidVendorIDs.contains(vendorID) {
            return true
        }
        
        // 检查设备名称是否包含Android相关关键词
        let deviceNameLower = deviceName.lowercased()
        let manufacturerLower = manufacturerName.lowercased()
        let androidKeywords = ["android", "phone", "mobile", "galaxy", "pixel", "xiaomi", "oneplus", "huawei", "redmi", "poco"]
        
        for keyword in androidKeywords {
            if deviceNameLower.contains(keyword) || manufacturerLower.contains(keyword) {
                return true
            }
        }
        
        return false
    }
    
    private func isPotentialMTPDevice(deviceInfo: USBDeviceInfo) -> Bool {
        // 常见的Android设备厂商ID（扩展列表）
        let androidVendorIDs: Set<UInt16> = [
            0x18D1, // Google
            0x04E8, // Samsung
            0x2717, // Xiaomi
            0x2A70, // OnePlus
            0x0BB4, // HTC
            0x12D1, // Huawei
            0x19D2, // ZTE
            0x0FCE, // Sony Ericsson
            0x22B8, // Motorola
            0x1004, // LG
            0x0E8D, // MediaTek
            0x1F3A, // Allwinner
            0x2916, // Android
            0x1782, // Spreadtrum
            0x2A47, // Realme
            0x2D95, // Vivo
            0x29A9, // Oppo
            0x05C6, // Qualcomm (某些设备使用)
            0x0489, // Foxconn (代工厂)
            0x1BBB, // T-Mobile
            0x0B05, // ASUS
            0x0955, // NVIDIA
            0x1D91, // BYD
            0x2A45, // Meizu
            0x2AE5, // Fairphone
            0x2C7C, // Quectel
        ]
        
        // 检查是否是已知的Android设备厂商
        if androidVendorIDs.contains(deviceInfo.vendorID) {
            return true
        }
        
        // 检查设备名称是否包含Android相关关键词
        let deviceNameLower = deviceInfo.name.lowercased()
        let androidKeywords = ["android", "mtp", "phone", "mobile", "galaxy", "pixel", "xiaomi", "oneplus", "huawei"]
        
        for keyword in androidKeywords {
            if deviceNameLower.contains(keyword) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - 智能扫描重试机制
    
    /// 为新检测到的MTP设备安排智能扫描
    /// 使用递增延迟的重试策略，确保设备有足够时间初始化MTP协议栈
    private func scheduleSmartScan(for deviceInfo: USBDeviceInfo) {
        let deviceKey = "\(deviceInfo.vendorID)-\(deviceInfo.productID)"
        
        // 取消之前的扫描任务（如果有）
        scanWorkItems[deviceKey]?.cancel()
        scanWorkItems.removeValue(forKey: deviceKey)
        
        // 重置重试计数
        pendingScans[deviceKey] = 0
        
        // 使用递增延迟策略：1秒、3秒、6秒、10秒
        let delays: [TimeInterval] = [1.0, 3.0, 6.0, 10.0]
        
        for (index, delay) in delays.enumerated() {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                
                let currentRetry = self.pendingScans[deviceKey] ?? 0
                
                // 只执行当前重试次数对应的扫描
                if currentRetry == index {
                    Logger.debug("智能扫描尝试 \(index + 1)/\(delays.count) for \(deviceInfo.displayName)")
                    
                    DispatchQueue.main.async {
                        self.onDeviceChanged?()
                    }
                    
                    // 增加重试计数
                    self.pendingScans[deviceKey] = currentRetry + 1
                    
                    // 如果是最后一次尝试，清理状态
                    if index == delays.count - 1 {
                        self.pendingScans.removeValue(forKey: deviceKey)
                        self.scanWorkItems.removeValue(forKey: deviceKey)
                        Logger.debug("智能扫描完成 for \(deviceInfo.displayName)")
                    }
                }
            }
            
            // 保存工作项以便取消
            scanWorkItems[deviceKey] = workItem
            
            // 安排延迟执行
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + delay,
                execute: workItem
            )
        }
        
        Logger.info("已为 \(deviceInfo.displayName) 安排 \(delays.count) 次智能扫描")
    }
    
    /// 取消指定设备的待处理扫描
    func cancelPendingScan(for deviceInfo: USBDeviceInfo) {
        let deviceKey = "\(deviceInfo.vendorID)-\(deviceInfo.productID)"
        scanWorkItems[deviceKey]?.cancel()
        scanWorkItems.removeValue(forKey: deviceKey)
        pendingScans.removeValue(forKey: deviceKey)
        Logger.debug("已取消 \(deviceInfo.displayName) 的待处理扫描")
    }
    
    /// 取消所有待处理的扫描
    func cancelAllPendingScans() {
        for workItem in scanWorkItems.values {
            workItem.cancel()
        }
        scanWorkItems.removeAll()
        pendingScans.removeAll()
        Logger.debug("已取消所有待处理的扫描")
    }
}

struct USBDeviceInfo {
    let name: String
    let vendorID: UInt16
    let productID: UInt16
    let manufacturerName: String
    let serialNumber: String?
    let deviceClass: UInt8
    let deviceSubClass: UInt8
    let isAndroidDevice: Bool
    let isMTPCapable: Bool
    
    var displayName: String {
        // 生成更友好的显示名称
        if !name.isEmpty && name != "Unknown Device" {
            return name
        } else if !manufacturerName.isEmpty && manufacturerName != "Unknown" {
            return "\(manufacturerName) Device"
        } else {
            return "Android Device"
        }
    }
    
    var vendorName: String {
        // 根据厂商ID返回厂商名称
        switch vendorID {
        case 0x18D1: return "Google"
        case 0x04E8: return "Samsung"
        case 0x2717: return "Xiaomi"
        case 0x2A70: return "OnePlus"
        case 0x0BB4: return "HTC"
        case 0x12D1: return "Huawei"
        case 0x19D2: return "ZTE"
        case 0x0FCE: return "Sony"
        case 0x22B8: return "Motorola"
        case 0x1004: return "LG"
        case 0x0E8D: return "MediaTek"
        case 0x1F3A: return "Allwinner"
        case 0x2916: return "Android"
        case 0x1782: return "Spreadtrum"
        case 0x2A47: return "Realme"
        case 0x2D95: return "Vivo"
        case 0x29A9: return "Oppo"
        case 0x05C6: return "Qualcomm"
        case 0x0489: return "Foxconn"
        case 0x1BBB: return "T-Mobile"
        case 0x0B05: return "ASUS"
        case 0x0955: return "NVIDIA"
        case 0x1D91: return "BYD"
        case 0x2A45: return "Meizu"
        case 0x2AE5: return "Fairphone"
        case 0x2C7C: return "Quectel"
        default: return manufacturerName.isEmpty ? "Unknown" : manufacturerName
        }
    }
}