//
//  MTPViewModel.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import Foundation
import SwiftUI
import Combine
import AppKit
import UserNotifications
import UniformTypeIdentifiers

// 路径组件结构，包含名称和ID
struct PathComponent: Identifiable, Equatable {
    let id: String
    let name: String
    let folderId: String? // nil 表示根目录
    
    static func root() -> PathComponent {
        PathComponent(id: "root", name: "/", folderId: nil)
    }
}

struct PromisedExportFailure: Equatable {
    let path: String
    let message: String
}

struct PromisedExportResult: Equatable {
    var succeeded: Int = 0
    var failed: [PromisedExportFailure] = []
    var skipped: Int = 0
    
    var hasFailures: Bool {
        !failed.isEmpty
    }
    
    mutating func merge(_ other: PromisedExportResult) {
        succeeded += other.succeeded
        failed.append(contentsOf: other.failed)
        skipped += other.skipped
    }
}

@MainActor
final class MTPViewModel: ObservableObject {
    @Published var devices: [MTPDevice] = []
    @Published var detectedDevices: [DetectedDevice] = [] // 所有检测到的设备
    @Published var selectedDevice: MTPDevice?
    @Published var currentFiles: [FileItem] = []
    @Published var currentPath: String = "/"
    @Published var pathComponents: [PathComponent] = [.root()]
    @Published var isScanning: Bool = false
    @Published var isLoading: Bool = false
    @Published var selectedFiles: Set<String> = []
    @Published var errorMessage: String?
    @Published var transferStatusMessage: String?
    
    private let deviceManager = MTPDeviceManager.shared
    private let fileManager = MTPFileManager.shared
    private let usbMonitor = USBDeviceMonitor.shared
    private final class FolderTraversalState {
        var visitedFolderIds: Set<String> = []
    }
    
    init() {
        // 设置USB设备变化回调
        usbMonitor.onDeviceChanged = { [weak self] in
            Task { @MainActor in
                await self?.handleUSBDeviceChanged()
            }
        }
        
        // 设置USB设备检测回调
        usbMonitor.onUSBDeviceDetected = { [weak self] deviceInfo, isConnected in
            Task { @MainActor in
                await self?.handleUSBDeviceDetected(deviceInfo, isConnected: isConnected)
            }
        }
        
        // 启动USB监听
        usbMonitor.startMonitoring()
    }
    
    /// 处理USB设备变化
    private func handleUSBDeviceChanged() async {
        Logger.info("USB设备变化，自动扫描MTP设备...")
        
        // 如果当前没有在扫描，则触发扫描
        if !isScanning {
            await scanDevices()
        }
    }
    
    /// 处理检测到的USB设备
    private func handleUSBDeviceDetected(_ deviceInfo: USBDeviceInfo, isConnected: Bool) async {
        if isConnected {
            // 设备插入
            let detectedDevice = DetectedDevice.fromUSBDevice(deviceInfo)
            
            // 检查是否已存在
            if !detectedDevices.contains(where: { $0.id == detectedDevice.id }) {
                detectedDevices.append(detectedDevice)
                Logger.debug("添加检测到的设备: \(detectedDevice.displayName)")
            }
        } else {
            // 设备拔出
            detectedDevices.removeAll { device in
                if let usbInfo = device.usbDeviceInfo {
                    return usbInfo.vendorID == deviceInfo.vendorID && usbInfo.productID == deviceInfo.productID
                }
                return false
            }
            Logger.debug("移除检测到的设备: \(deviceInfo.displayName)")
            
            // 如果当前选中的设备被拔出，清除文件列表和选中状态
            if let selectedDevice = selectedDevice {
                // 检查当前选中的设备是否匹配拔出的USB设备
                let isCurrentDeviceRemoved = devices.contains { device in
                    device.id == selectedDevice.id
                }
                
                if isCurrentDeviceRemoved {
                    Logger.warning("当前选中的设备已拔出，清除文件列表")
                    // 清除文件列表
                    currentFiles = []
                    // 清除选中的文件
                    selectedFiles.removeAll()
                    // 重置路径
                    currentPath = "/"
                    pathComponents = [.root()]
                    // 清除选中的设备
                    self.selectedDevice = nil
                }
            }
        }
        
        // 更新检测到的设备状态
        updateDetectedDevicesStatus()
    }
    
    /// 更新检测到的设备状态（标记哪些已启用MTP）
    private func updateDetectedDevicesStatus() {
        var updatedDevices: [DetectedDevice] = []
        
        // 首先添加所有MTP设备
        for mtpDevice in devices {
            let detectedDevice = DetectedDevice.fromMTPDevice(mtpDevice)
            updatedDevices.append(detectedDevice)
        }
        
        // 然后添加未启用MTP的USB设备
        for detectedDevice in detectedDevices {
            if !detectedDevice.isMTPEnabled {
                // 检查是否已经有对应的MTP设备
                let hasMTPVersion = devices.contains { mtpDevice in
                    // 简单的匹配逻辑，可以根据需要改进
                    mtpDevice.manufacturer == detectedDevice.vendorName ||
                    mtpDevice.name.contains(detectedDevice.vendorName)
                }
                
                if !hasMTPVersion {
                    updatedDevices.append(detectedDevice)
                }
            }
        }
        
        detectedDevices = updatedDevices
    }
    
    private func checkSystemRequirements() async {
        // 检查 libmtp 是否可用
        let mtpAvailable = MTPBridge.initializeMTP()
        if !mtpAvailable {
            errorMessage = """
            ❌ MTP 库初始化失败
            
            请确保已安装 libmtp：
            brew install libmtp
            """
            return
        }
        
        // 检查是否有基本的USB访问权限
        // 这里可以添加更多的系统检查
    }
    
    func scanDevices() async {
        Logger.info("开始扫描设备...")
        isScanning = true
        errorMessage = nil
        
        do {
            let scannedDevices = try await deviceManager.scanDevices()
            Logger.info("收到 \(scannedDevices.count) 个设备")
            
            // 确保在主线程更新UI
            await MainActor.run {
                self.devices = scannedDevices
                Logger.debug("UI已更新，当前设备数量: \(self.devices.count)")
                
                // 如果成功扫描到设备，取消所有待处理的智能扫描
                if !scannedDevices.isEmpty {
                    usbMonitor.cancelAllPendingScans()
                    Logger.debug("扫描成功，已取消待处理的重试扫描")
                }
                
                if scannedDevices.isEmpty {
                    errorMessage = """
                    未检测到 MTP 设备。请确保：
                    
                    📱 手机端设置：
                    • 手机已通过 USB 连接并解锁
                    • 在通知栏选择"文件传输(MTP)"模式
                    • 点击"信任此计算机"（如果弹出）
                    
                    🔧 如果仍无法检测，请在终端运行：
                    mtp-detect
                    
                    查看详细错误信息
                    """
                } else {
                    Logger.debug("设备详情:")
                    for device in scannedDevices {
                        Logger.debug("- \(device.name) (ID: \(device.id), 连接状态: \(device.isConnected))")
                    }
                }
            }
        } catch {
            Logger.error("扫描设备失败: \(error.localizedDescription)")
            
            await MainActor.run {
                if let nsError = error as NSError?, nsError.code == -1000 {
                    // 权限错误，显示详细的解决方案
                    errorMessage = nsError.localizedRecoverySuggestion ?? nsError.localizedDescription
                } else {
                    errorMessage = "扫描设备失败: \(error.localizedDescription)\n\n💡 提示：尝试重新连接手机或检查USB连接"
                }
            }
        }
        
        await MainActor.run {
            isScanning = false
            Logger.debug("扫描完成，isScanning = false")
        }
    }
    
    /// 刷新设备信息但保持连接状态
    func refreshDevices() async {
        Logger.info("刷新设备信息（保持连接）...")
        isScanning = true
        errorMessage = nil
        
        do {
            let refreshedDevices = try await deviceManager.refreshDevices()
            Logger.info("刷新收到 \(refreshedDevices.count) 个设备")
            
            // 保持当前选中的设备
            let currentSelectedDeviceId = selectedDevice?.id
            
            await MainActor.run {
                self.devices = refreshedDevices
                
                // 如果之前有选中的设备，尝试保持选中状态
                if let selectedId = currentSelectedDeviceId {
                    self.selectedDevice = refreshedDevices.first { $0.id == selectedId }
                    if self.selectedDevice != nil {
                        Logger.debug("保持设备连接状态: \(selectedId)")
                    } else {
                        Logger.warning("之前选中的设备已断开: \(selectedId)")
                    }
                }
                
                Logger.debug("设备信息已刷新，当前设备数量: \(self.devices.count)")
            }
        } catch {
            Logger.error("刷新设备失败: \(error.localizedDescription)")
            
            await MainActor.run {
                errorMessage = "刷新设备失败: \(error.localizedDescription)"
            }
        }
        
        await MainActor.run {
            isScanning = false
            Logger.debug("刷新完成，isScanning = false")
        }
    }
    
    func refreshCurrentLocation() async {
        if selectedDevice == nil {
            await scanDevices()
            return
        }
        
        guard let currentComponent = pathComponents.last else {
            await refreshDevices()
            return
        }
        
        await loadFiles(folderId: currentComponent.folderId)
    }
    
    func connectDevice(_ device: MTPDevice) async {
        do {
            try await deviceManager.connectDevice(device.id)
            selectedDevice = device
            // 重置导航到根目录
            pathComponents = [.root()]
            currentPath = "/"
            await loadFiles(folderId: nil)
        } catch {
            errorMessage = "连接设备失败: \(error.localizedDescription)"
        }
    }
    
    func disconnectDevice() {
        if let device = selectedDevice {
            deviceManager.disconnectDevice(device.id)
        }
        selectedDevice = nil
        currentFiles = []
        currentPath = "/"
        pathComponents = [.root()]
        selectedFiles.removeAll()
    }
    
    func loadFiles(folderId: String?) async {
        guard let device = selectedDevice else { return }
        
        isLoading = true
        errorMessage = nil
        
        // 清除之前的选中状态
        selectedFiles.removeAll()
        
        Logger.debug("加载文件夹 ID: \(folderId ?? "根目录")")
        
        do {
            let files = try await fileManager.listFiles(deviceId: device.id, parentId: folderId)
            Logger.info("成功加载 \(files.count) 个文件/文件夹")
            self.currentFiles = files
            
            if files.isEmpty {
                Logger.debug("文件夹为空")
            }
        } catch {
            Logger.error("加载文件失败: \(error.localizedDescription)")
            errorMessage = "加载文件失败: \(error.localizedDescription)"
            self.currentFiles = []
        }
        
        isLoading = false
    }
    
    func navigateToFolder(_ folder: FileItem) {
        guard folder.isDirectory else { return }
        Task {
            // 创建新的路径组件
            let newComponent = PathComponent(
                id: folder.id,
                name: folder.name,
                folderId: folder.id
            )
            
            // 添加到路径组件数组
            pathComponents.append(newComponent)
            
            // 更新路径显示
            updateCurrentPath()
            
            await loadFiles(folderId: folder.id)
        }
    }
    
    func navigateToPathComponent(_ component: PathComponent) async {
        // 找到该组件在路径中的位置
        guard let index = pathComponents.firstIndex(of: component) else {
            Logger.warning("路径组件未找到")
            return
        }
        
        // 截断路径到该组件
        pathComponents = Array(pathComponents[0...index])
        
        // 更新路径显示
        updateCurrentPath()
        
        // 加载该文件夹的内容
        await loadFiles(folderId: component.folderId)
    }
    
    func goBack() async {
        guard pathComponents.count > 1 else { return }
        
        // 移除最后一个路径组件
        pathComponents.removeLast()
        
        // 更新路径显示
        updateCurrentPath()
        
        // 加载父文件夹
        guard let parentComponent = pathComponents.last else { return }
        await loadFiles(folderId: parentComponent.folderId)
    }
    
    private func updateCurrentPath() {
        if pathComponents.count == 1 {
            currentPath = "/"
        } else {
            currentPath = "/" + pathComponents.dropFirst().map { $0.name }.joined(separator: "/")
        }
    }
    
    // MARK: - 简化的文件传输功能
    
    /// 使用系统对话框上传文件
    func uploadFiles() {
        guard selectedDevice != nil else { return }
        
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "选择要上传的文件"
        
        if panel.runModal() == .OK {
            Task {
                await uploadFiles(panel.urls)
            }
        }
    }
    
    /// 使用系统对话框下载选中的文件
    func downloadSelectedFiles() {
        let files = currentFiles.filter { selectedFiles.contains($0.id) }
        guard !files.isEmpty, let device = selectedDevice else { return }
        let settings = AppSettings.shared
        
        if settings.useDefaultDownloadDirectory, let directoryURL = settings.defaultDownloadDirectoryURL {
            Task {
                await downloadFiles(files, deviceId: device.id, to: directoryURL, appendingFileName: true)
            }
            return
        }
        
        if files.count == 1 {
            // 单个文件，使用保存对话框
            let panel = NSSavePanel()
            panel.nameFieldStringValue = files[0].name
            panel.prompt = "保存文件"
            
            if panel.runModal() == .OK, let url = panel.url {
                Task {
                    await downloadFiles(files, deviceId: device.id, to: url, appendingFileName: false)
                }
            }
        } else {
            // 多个文件，选择文件夹
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "选择保存位置"
            
            if panel.runModal() == .OK, let url = panel.url {
                Task {
                    await downloadFiles(files, deviceId: device.id, to: url, appendingFileName: true)
                }
            }
        }
    }
    
    /// 下载选中的文件到指定目录（用于双栏传输）
    func downloadSelectedFiles(to destinationURL: URL) async {
        let files = currentFiles.filter { selectedFiles.contains($0.id) }
        guard !files.isEmpty, let device = selectedDevice else { return }
        
        await downloadFiles(files, deviceId: device.id, to: destinationURL, appendingFileName: true)
    }
    
    /// 上传指定的文件（用于双栏传输）
    func uploadFiles(_ urls: [URL]) async {
        guard let device = selectedDevice else { return }
        
        let currentFolderId = pathComponents.last?.folderId
        let uploadableURLs = urls.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        
        guard !uploadableURLs.isEmpty else { return }
        
        var existingNames = Set(currentFiles.map(\.name))
        if existingNames.isEmpty {
            do {
                existingNames = Set(try await fileManager.listFiles(deviceId: device.id, parentId: currentFolderId).map(\.name))
            } catch {
                Logger.warning("加载上传冲突信息失败: \(error.localizedDescription)")
            }
        }
        
        var succeeded = 0
        var failed: [(URL, Error)] = []
        var skipped = 0
        
        for url in uploadableURLs {
            do {
                guard let finalName = chooseUploadName(
                    originalName: url.lastPathComponent,
                    existingNames: existingNames,
                    resolution: AppSettings.shared.conflictResolution
                ) else {
                    skipped += 1
                    continue
                }
                
                _ = try await fileManager.uploadFile(
                    deviceId: device.id,
                    sourceURL: url,
                    toParentId: currentFolderId,
                    fileName: finalName,
                    progress: { _ in }
                )
                
                existingNames.insert(finalName)
                succeeded += 1
                Logger.info("上传完成: \(finalName)")
            } catch {
                failed.append((url, error))
                Logger.error("上传失败: \(url.lastPathComponent) - \(error.localizedDescription)")
            }
        }
        
        await loadFiles(folderId: currentFolderId)
        publishTransferResult(action: "上传", succeeded: succeeded, failed: failed.count, skipped: skipped)
    }
    
    /// 下载单个项目给 NSFilePromiseProvider。completion 会等真实下载完成后再回调，让 Finder 使用系统进度。
    func downloadPromisedItem(_ item: FileItem, to destinationURL: URL) async throws {
        guard let device = selectedDevice else {
            throw MTPError.deviceNotFound
        }
        
        transferStatusMessage = "正在导出 \(item.name)..."
        defer { transferStatusMessage = nil }
        
        guard let finalURL = chooseLocalDestination(
            proposedURL: destinationURL,
            resolution: AppSettings.shared.conflictResolution
        ) else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: NSUserCancelledError,
                userInfo: [NSLocalizedDescriptionKey: "已跳过导出：\(item.name)"]
            )
        }
        
        if item.isDirectory {
            try FileManager.default.createDirectory(at: finalURL, withIntermediateDirectories: true)
            var result = PromisedExportResult(succeeded: 1)
            result.merge(await downloadFolderContents(
                item,
                deviceId: device.id,
                to: finalURL,
                traversalState: FolderTraversalState()
            ))
            publishPromisedExportResult(result, rootName: item.name)
            return
        }
        
        try await fileManager.downloadFile(
            deviceId: device.id,
            fileId: item.id,
            fileName: item.name,
            to: finalURL,
            progress: { _ in }
        )
        Logger.info("导出完成: \(item.name) -> \(finalURL.path)")
    }
    
    /// 下载单个文件给 NSFilePromiseProvider。completion 会等真实下载完成后再回调，让 Finder 使用系统进度。
    func downloadPromisedFile(_ file: FileItem, to destinationURL: URL) async throws {
        guard !file.isDirectory else { return }
        
        try await downloadPromisedItem(file, to: destinationURL)
    }
    
    private func downloadFolderContents(
        _ folder: FileItem,
        deviceId: String,
        to destinationURL: URL,
        traversalState: FolderTraversalState
    ) async -> PromisedExportResult {
        guard traversalState.visitedFolderIds.insert(folder.id).inserted else {
            Logger.warning("跳过重复目录: \(folder.name) (\(folder.id))")
            return PromisedExportResult(skipped: 1)
        }
        
        let children: [FileItem]
        do {
            children = try await fileManager.listFiles(deviceId: deviceId, parentId: folder.id)
        } catch {
            Logger.error("列出目录失败: \(folder.name) -> \(destinationURL.path) - \(error.localizedDescription)")
            return PromisedExportResult(failed: [
                PromisedExportFailure(path: destinationURL.path, message: error.localizedDescription)
            ])
        }
        
        var result = PromisedExportResult()
        
        for child in children {
            let childURL = destinationURL.appendingPathComponent(child.name, isDirectory: child.isDirectory)
            
            if child.isDirectory {
                guard let finalChildURL = chooseLocalDestination(
                    proposedURL: childURL,
                    resolution: AppSettings.shared.conflictResolution
                ) else {
                    result.skipped += 1
                    continue
                }
                
                do {
                    try FileManager.default.createDirectory(at: finalChildURL, withIntermediateDirectories: true)
                    result.succeeded += 1
                    result.merge(await downloadFolderContents(
                        child,
                        deviceId: deviceId,
                        to: finalChildURL,
                        traversalState: traversalState
                    ))
                } catch {
                    Logger.error("创建导出目录失败: \(child.name) -> \(finalChildURL.path) - \(error.localizedDescription)")
                    result.failed.append(PromisedExportFailure(
                        path: finalChildURL.path,
                        message: error.localizedDescription
                    ))
                }
            } else {
                guard let finalChildURL = chooseLocalDestination(
                    proposedURL: childURL,
                    resolution: AppSettings.shared.conflictResolution
                ) else {
                    result.skipped += 1
                    continue
                }
                
                do {
                    try await fileManager.downloadFile(
                        deviceId: deviceId,
                        fileId: child.id,
                        fileName: child.name,
                        to: finalChildURL,
                        progress: { _ in }
                    )
                    result.succeeded += 1
                } catch {
                    Logger.error("导出文件失败: \(child.name) -> \(finalChildURL.path) - \(error.localizedDescription)")
                    result.failed.append(PromisedExportFailure(
                        path: finalChildURL.path,
                        message: error.localizedDescription
                    ))
                }
            }
        }
        
        return result
    }
    
    private func publishPromisedExportResult(_ result: PromisedExportResult, rootName: String) {
        Logger.shared.logBatchOperation("导出", successCount: result.succeeded, failCount: result.failed.count)
        
        if result.hasFailures {
            let failurePreview = result.failed.prefix(3)
                .map { "\(($0.path as NSString).lastPathComponent): \($0.message)" }
                .joined(separator: "\n")
            errorMessage = "导出“\(rootName)”完成：成功 \(result.succeeded) 个，失败 \(result.failed.count) 个，跳过 \(result.skipped) 个。\n\(failurePreview)"
        }
        
        sendNotification(
            title: "导出完成",
            body: "成功 \(result.succeeded) 个，失败 \(result.failed.count) 个，跳过 \(result.skipped) 个"
        )
    }
    
    private func downloadFiles(
        _ files: [FileItem],
        deviceId: String,
        to destinationURL: URL,
        appendingFileName: Bool
    ) async {
        var succeeded = 0
        var failed: [(FileItem, Error)] = []
        var skipped = 0
        
        for file in files {
            let proposedURL = appendingFileName ? destinationURL.appendingPathComponent(file.name) : destinationURL
            
            guard let finalURL = chooseLocalDestination(
                proposedURL: proposedURL,
                resolution: AppSettings.shared.conflictResolution
            ) else {
                skipped += 1
                continue
            }
            
            do {
                try await fileManager.downloadFile(
                    deviceId: deviceId,
                    fileId: file.id,
                    fileName: file.name,
                    to: finalURL,
                    progress: { _ in }
                )
                succeeded += 1
                Logger.info("下载完成: \(file.name)")
            } catch {
                failed.append((file, error))
                Logger.error("下载失败: \(file.name) - \(error.localizedDescription)")
            }
        }
        
        publishTransferResult(action: "下载", succeeded: succeeded, failed: failed.count, skipped: skipped)
    }
    
    private func chooseUploadName(
        originalName: String,
        existingNames: Set<String>,
        resolution: ConflictResolution
    ) -> String? {
        guard existingNames.contains(originalName) else {
            return originalName
        }
        
        switch resolution {
        case .rename:
            return uniqueFileName(for: originalName, existingNames: existingNames)
        case .skip:
            return nil
        case .overwrite:
            return originalName
        case .ask:
            switch askConflictResolution(message: "设备上已存在“\(originalName)”。") {
            case .overwrite:
                return originalName
            case .rename:
                return uniqueFileName(for: originalName, existingNames: existingNames)
            case .skip, .ask:
                return nil
            }
        }
    }
    
    private func chooseLocalDestination(
        proposedURL: URL,
        resolution: ConflictResolution
    ) -> URL? {
        guard FileManager.default.fileExists(atPath: proposedURL.path) else {
            return proposedURL
        }
        
        switch resolution {
        case .rename:
            return uniqueLocalURL(for: proposedURL)
        case .skip:
            return nil
        case .overwrite:
            return proposedURL
        case .ask:
            switch askConflictResolution(message: "本地已存在“\(proposedURL.lastPathComponent)”。") {
            case .overwrite:
                return proposedURL
            case .rename:
                return uniqueLocalURL(for: proposedURL)
            case .skip, .ask:
                return nil
            }
        }
    }
    
    private func askConflictResolution(message: String) -> ConflictResolution {
        let alert = NSAlert()
        alert.messageText = "文件已存在"
        alert.informativeText = "请选择如何处理：\(message)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "替换")
        alert.addButton(withTitle: "保留两者")
        alert.addButton(withTitle: "跳过")
        
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .overwrite
        case .alertSecondButtonReturn:
            return .rename
        default:
            return .skip
        }
    }
    
    private func uniqueFileName(for originalName: String, existingNames: Set<String>) -> String {
        let nsName = originalName as NSString
        let baseName = nsName.deletingPathExtension
        let pathExtension = nsName.pathExtension
        var counter = 1
        
        while true {
            let candidate = pathExtension.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(pathExtension)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }
    
    private func uniqueLocalURL(for url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return url
        }
        
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let pathExtension = url.pathExtension
        var counter = 1
        
        while true {
            let fileName = pathExtension.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(pathExtension)"
            let candidate = directory.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }
    
    private func publishTransferResult(action: String, succeeded: Int, failed: Int, skipped: Int) {
        Logger.shared.logBatchOperation(action, successCount: succeeded, failCount: failed)
        
        if failed > 0 {
            errorMessage = "\(action)完成：成功 \(succeeded) 个，失败 \(failed) 个，跳过 \(skipped) 个。"
        }
        
        guard succeeded > 0 || failed > 0 || skipped > 0 else { return }
        sendNotification(
            title: "\(action)完成",
            body: "成功 \(succeeded) 个，失败 \(failed) 个，跳过 \(skipped) 个"
        )
    }
    
    // MARK: - 文件打开功能
    
    func openFile(_ file: FileItem) {
        guard let device = selectedDevice else { return }
        guard !file.isDirectory else { return }
        
        Task {
            do {
                // 创建临时文件路径
                let tempURL = TempFileManager.shared.createTempFile(for: file.name)
                
                Logger.debug("正在下载文件以打开: \(file.name)")
                
                // 下载文件到临时位置
                try await fileManager.downloadFile(
                    deviceId: device.id,
                    fileId: file.id,
                    fileName: file.name,
                    to: tempURL,
                    progress: { _ in } // 简化：不显示进度
                )
                
                Logger.info("文件下载完成，正在打开: \(tempURL.path)")
                
                // 使用系统默认应用打开文件
                await MainActor.run {
                    let success = NSWorkspace.shared.open(tempURL)
                    if !success {
                        Logger.warning("系统无法打开文件: \(tempURL.path)")
                        errorMessage = "无法打开文件，可能没有关联的应用程序"
                    }
                }
                
                // 发送通知
                sendNotification(title: "文件已打开", body: file.name)
                
                // 延迟清理临时文件（给系统时间打开文件）
                TempFileManager.shared.scheduleCleanup(for: tempURL, delay: 300) // 5分钟后清理
                
            } catch {
                Logger.error("打开文件失败: \(file.name) - \(error.localizedDescription)")
                
                await MainActor.run {
                    errorMessage = "打开文件失败: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func openSelectedFile() {
        guard selectedFiles.count == 1,
              let file = currentFiles.first(where: { selectedFiles.contains($0.id) }) else {
            return
        }
        
        if file.isDirectory {
            navigateToFolder(file)
        } else {
            openFile(file)
        }
    }
    
    // MARK: - Quick Look 预览功能
    
    /// 预览选中的文件
    func previewSelectedFiles() {
        guard !selectedFiles.isEmpty else { return }
        
        // 获取选中的文件对象
        let filesToPreview = currentFiles.filter { selectedFiles.contains($0.id) }
        
        // 找到第一个选中文件
        guard let firstFile = filesToPreview.first else {
            return
        }
        
        // 只预览非文件夹的文件
        let previewableFiles = currentFiles.filter { !$0.isDirectory }
        
        guard !previewableFiles.isEmpty else {
            Logger.warning("没有可预览的文件")
            return
        }
        
        // 找到在可预览文件列表中的索引
        let previewIndex = previewableFiles.firstIndex(where: { $0.id == firstFile.id }) ?? 0
        
        Logger.debug("开始预览文件: \(firstFile.name)")
        QuickLookManager.shared.showPreview(for: previewableFiles, startingAt: previewIndex, viewModel: self)
    }
    
    /// 检查文件是否可以预览
    func canPreviewFile(_ file: FileItem) -> Bool {
        return QuickLookManager.shared.canPreview(file)
    }
    
    private func sendNotification(title: String, body: String) {
        guard AppSettings.shared.showNotificationOnComplete else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = AppSettings.shared.playSoundOnComplete ? .default : nil
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("发送通知失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 文件操作
    
    func deleteFiles(_ files: [FileItem]) async -> FileOperationResult {
        guard let device = selectedDevice else {
            return FileOperationResult(succeeded: [], failed: files.map { ($0, MTPError.deviceNotFound) })
        }
        
        var succeeded: [FileItem] = []
        var failed: [(FileItem, Error)] = []
        
        for file in files {
            do {
                Logger.debug("删除文件: \(file.name) (ID: \(file.id))")
                try await fileManager.deleteFile(deviceId: device.id, fileId: file.id)
                succeeded.append(file)
                Logger.info("删除成功: \(file.name)")
            } catch {
                failed.append((file, error))
                Logger.error("删除失败: \(file.name) - \(error.localizedDescription)")
            }
        }
        
        // 记录批量操作结果
        Logger.shared.logBatchOperation("删除", successCount: succeeded.count, failCount: failed.count)
        
        // 刷新文件列表
        let currentFolderId = pathComponents.last?.folderId
        await loadFiles(folderId: currentFolderId)
        
        // 清除选择
        selectedFiles.removeAll()
        
        return FileOperationResult(succeeded: succeeded, failed: failed)
    }
    
    /// 删除选中的文件（UI调用）
    func deleteSelectedFiles() {
        let files = currentFiles.filter { selectedFiles.contains($0.id) }
        guard !files.isEmpty else { return }
        
        Task {
            let result = await deleteFiles(files)
            
            // 显示结果
            if !result.isFullSuccess {
                errorMessage = result.summary
                if result.isPartialSuccess || result.isFullFailure {
                    errorMessage! += "\n\n失败详情:\n" + result.failureDetails
                }
            }
        }
    }
    
    func createFolder(name: String) {
        guard let device = selectedDevice else { return }
        
        // 验证文件夹名称
        let result = FileNameValidator.validateAndSanitize(name)
        let sanitizedName: String
        
        switch result {
        case .success(let validName):
            sanitizedName = validName
        case .failure(let error):
            errorMessage = error.localizedDescription
            return
        }
        
        // 获取当前文件夹ID
        let currentFolderId = pathComponents.last?.folderId
        
        Task {
            do {
                Logger.debug("创建文件夹: \(sanitizedName)")
                let newFolderId = try await fileManager.createFolder(
                    deviceId: device.id,
                    name: sanitizedName,
                    parentId: currentFolderId
                )
                Logger.info("文件夹创建成功，ID: \(newFolderId)")
                
                // 刷新文件列表
                await loadFiles(folderId: currentFolderId)
                
            } catch {
                Logger.error("创建文件夹失败: \(error.localizedDescription)")
                errorMessage = "创建文件夹失败: \(error.localizedDescription)"
            }
        }
    }
    
    func renameFile(_ file: FileItem, to newName: String) {
        guard let device = selectedDevice else { return }
        
        // 验证新文件名
        let result = FileNameValidator.validateAndSanitize(newName)
        let sanitizedName: String
        
        switch result {
        case .success(let validName):
            sanitizedName = validName
        case .failure(let error):
            errorMessage = error.localizedDescription
            return
        }
        
        Task {
            do {
                Logger.debug("重命名文件: \(file.name) -> \(sanitizedName)")
                try await fileManager.renameFile(
                    deviceId: device.id,
                    fileId: file.id,
                    newName: sanitizedName
                )
                Logger.info("重命名成功")
                
                // 刷新文件列表
                let currentFolderId = pathComponents.last?.folderId
                await loadFiles(folderId: currentFolderId)
                
            } catch {
                Logger.error("重命名失败: \(error.localizedDescription)")
                errorMessage = "重命名失败: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - 文件选择
    
    func toggleFileSelection(_ fileId: String) {
        if selectedFiles.contains(fileId) {
            selectedFiles.remove(fileId)
        } else {
            selectedFiles.insert(fileId)
        }
    }
    
    func selectAllFiles() {
        selectedFiles = Set(currentFiles.map { $0.id })
    }
    
    func deselectAllFiles() {
        selectedFiles.removeAll()
    }
    
    func selectFile(_ fileId: String, multiSelect: Bool = false) {
        if multiSelect {
            toggleFileSelection(fileId)
        } else {
            selectedFiles = [fileId]
        }
    }
    
    func selectRange(from startId: String, to endId: String) {
        guard let startIndex = currentFiles.firstIndex(where: { $0.id == startId }),
              let endIndex = currentFiles.firstIndex(where: { $0.id == endId }) else {
            return
        }
        
        let range = min(startIndex, endIndex)...max(startIndex, endIndex)
        let rangeIds = Set(currentFiles[range].map { $0.id })
        selectedFiles.formUnion(rangeIds)
    }
    
    // MARK: - 清理资源
    
    deinit {
        // 清理临时文件
        Task { @MainActor in
            TempFileManager.shared.cleanupAll()
        }
    }
}