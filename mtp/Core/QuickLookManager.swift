//
//  QuickLookManager.swift
//  mtp
//
//  Quick Look 预览管理器
//

import Foundation
import Quartz
import AppKit

final class QuickLookManager: NSObject {
    static let shared = QuickLookManager()
    
    private var currentFiles: [FileItem] = []
    private var currentIndex: Int = 0
    private weak var viewModel: MTPViewModel?
    private var temporaryFiles: [URL] = []
    private var previewItems: [QuickLookPreviewItem] = []
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// 显示 Quick Look 预览
    func showPreview(for files: [FileItem], startingAt index: Int, viewModel: MTPViewModel) {
        self.currentFiles = files
        self.currentIndex = index
        self.viewModel = viewModel
        
        // 预创建所有预览项
        self.previewItems = files.map { QuickLookPreviewItem(file: $0, manager: self) }
        
        // 在主线程上操作 Quick Look
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 获取预览面板
            guard let panel = QLPreviewPanel.shared() else {
                print("❌ 无法创建 Quick Look 面板")
                return
            }
            
            // 设置数据源和代理
            panel.dataSource = self
            panel.delegate = self
            
            // 显示面板
            if panel.isVisible {
                panel.reloadData()
            } else {
                panel.makeKeyAndOrderFront(nil)
            }
            
            // 设置当前索引
            panel.currentPreviewItemIndex = index
            
            print("🔍 Quick Look 预览已打开，共 \(files.count) 个文件")
        }
    }
    
    /// 关闭预览
    func closePreview() {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.close()
        }
        cleanupTemporaryFiles()
    }
    
    /// 检查是否可以预览
    func canPreview(_ file: FileItem) -> Bool {
        // 文件夹不能预览
        if file.isDirectory {
            return false
        }
        
        // 检查文件类型是否支持预览
        let supportedExtensions = [
            // 图片
            "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp",
            // 视频
            "mp4", "mov", "m4v", "avi", "mkv",
            // 音频
            "mp3", "m4a", "wav", "aac", "flac",
            // 文档
            "pdf", "txt", "md", "rtf", "doc", "docx",
            // 代码
            "swift", "py", "js", "html", "css", "json", "xml",
            // 压缩包
            "zip", "rar", "7z"
        ]
        
        return supportedExtensions.contains(file.fileExtension.lowercased())
    }
    
    // MARK: - Private Methods
    
    private func cleanupTemporaryFiles() {
        for url in temporaryFiles {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryFiles.removeAll()
        previewItems.removeAll()
    }
    
    /// 下载文件到临时目录用于预览
    fileprivate func downloadFileForPreview(_ file: FileItem) async -> URL? {
        guard let viewModel = viewModel else {
            print("❌ QuickLookManager: viewModel 为 nil")
            return nil
        }
        
        guard let device = await viewModel.selectedDevice else {
            print("❌ QuickLookManager: 未选择设备")
            return nil
        }
        
        print("📱 当前设备: \(device.name) (ID: \(device.id))")
        
        // 创建临时目录
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mtp-preview", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            print("❌ 创建临时目录失败: \(error)")
            return nil
        }
        
        let tempFile = tempDir.appendingPathComponent(file.name)
        
        // 如果文件已存在，直接返回
        if FileManager.default.fileExists(atPath: tempFile.path) {
            print("✅ 使用缓存文件: \(file.name)")
            return tempFile
        }
        
        do {
            print("📥 开始下载文件用于预览:")
            print("   - 文件名: \(file.name)")
            print("   - 文件ID: \(file.id)")
            print("   - 设备ID: \(device.id)")
            print("   - 目标路径: \(tempFile.path)")
            
            try await MTPFileManager.shared.downloadFile(
                deviceId: device.id,
                fileId: file.id,
                fileName: file.name,
                to: tempFile,
                progress: { progress in
                    print("   预览下载进度: \(Int(progress * 100))%")
                }
            )
            
            // 验证文件是否下载成功
            if FileManager.default.fileExists(atPath: tempFile.path) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: tempFile.path)
                let fileSize = attributes?[.size] as? Int64 ?? 0
                print("✅ 预览文件已下载: \(tempFile.path) (大小: \(fileSize) 字节)")
            } else {
                print("❌ 文件下载后不存在: \(tempFile.path)")
                return nil
            }
            
            // 记录临时文件，以便后续清理
            await MainActor.run {
                self.temporaryFiles.append(tempFile)
            }
            
            return tempFile
        } catch {
            print("❌ 下载预览文件失败:")
            print("   - 文件: \(file.name)")
            print("   - 错误: \(error)")
            print("   - 错误详情: \(error.localizedDescription)")
            
            // 不要在这里重新扫描设备，这会导致设备断开
            // 只记录错误信息
            
            return nil
        }
    }
}

// MARK: - QLPreviewPanelDataSource
extension QuickLookManager: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewItems.count
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < previewItems.count else {
            print("⚠️ 预览索引越界: \(index)")
            return nil
        }
        
        return previewItems[index]
    }
}

// MARK: - QLPreviewPanelDelegate
extension QuickLookManager: QLPreviewPanelDelegate {
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        // 处理键盘事件
        if event.type == .keyDown {
            if event.keyCode == 49 { // 空格键
                panel.close()
                return true
            }
        }
        return false
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        // 返回源视图的位置（用于动画）
        return NSRect.zero
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, transitionImageFor item: QLPreviewItem!, contentRect: UnsafeMutablePointer<NSRect>!) -> Any! {
        return nil
    }
}

// MARK: - QuickLookPreviewItem
class QuickLookPreviewItem: NSObject, QLPreviewItem {
    let file: FileItem
    weak var manager: QuickLookManager?
    private var cachedURL: URL?
    private var downloadTask: Task<URL?, Never>?
    
    init(file: FileItem, manager: QuickLookManager) {
        self.file = file
        self.manager = manager
        super.init()
        
        // 立即开始下载
        startDownload()
    }
    
    private func startDownload() {
        guard downloadTask == nil else { return }
        
        downloadTask = Task {
            if let url = await manager?.downloadFileForPreview(file) {
                await MainActor.run {
                    self.cachedURL = url
                    // 通知 Quick Look 刷新
                    if let panel = QLPreviewPanel.shared(), panel.isVisible {
                        panel.refreshCurrentPreviewItem()
                    }
                }
                return url
            }
            return nil
        }
    }
    
    var previewItemURL: URL! {
        return cachedURL
    }
    
    var previewItemTitle: String! {
        return file.name
    }
    
    var previewItemDisplayState: Any! {
        return nil
    }
    
    deinit {
        downloadTask?.cancel()
    }
}
