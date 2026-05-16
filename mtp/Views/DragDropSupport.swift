//
//  DragDropSupport.swift
//  mtp
//
//  拖拽支持：从 MTP 设备拖拽文件到 macOS 本地
//

import Foundation
import AppKit
import SwiftUI

// MARK: - 文件 Promise Provider
@objc class FilePromiseProvider: NSFilePromiseProvider {
    let viewModel: MTPViewModel
    let file: FileItem
    private let promiseDelegate: FilePromiseDelegate
    
    init(viewModel: MTPViewModel, file: FileItem) {
        self.viewModel = viewModel
        self.file = file
        
        // 创建代理对象
        self.promiseDelegate = FilePromiseDelegate(viewModel: viewModel, file: file)
        
        // 设置文件类型
        let fileType: String
        if file.fileExtension.isEmpty {
            fileType = "public.data"
        } else {
            fileType = "public.\(file.fileExtension)"
        }
        
        super.init(fileType: fileType, delegate: promiseDelegate)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @available(*, unavailable)
    override init() {
        fatalError("init() has not been implemented")
    }
}

// MARK: - 批量文件 Promise Provider
@objc class BatchFilePromiseProvider: NSFilePromiseProvider {
    let viewModel: MTPViewModel
    let files: [FileItem]
    private let promiseDelegate: BatchFilePromiseDelegate
    
    init(viewModel: MTPViewModel, files: [FileItem]) {
        self.viewModel = viewModel
        self.files = files
        
        // 创建代理对象
        self.promiseDelegate = BatchFilePromiseDelegate(viewModel: viewModel, files: files)
        
        super.init(fileType: "public.data", delegate: promiseDelegate)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @available(*, unavailable)
    override init() {
        fatalError("init() has not been implemented")
    }
}

// MARK: - NSFilePromiseProviderDelegate
@objc class FilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let viewModel: MTPViewModel
    let file: FileItem
    
    init(viewModel: MTPViewModel, file: FileItem) {
        self.viewModel = viewModel
        self.file = file
        super.init()
    }
    
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        return file.name
    }
    
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        print("📥 开始下载文件到: \(url.path)")
        
        // 使用 DispatchQueue 避免拖拽重入问题
        DispatchQueue.main.async { [weak viewModel, file] in
            guard let viewModel = viewModel,
                  let deviceId = viewModel.selectedDevice?.id else {
                completionHandler(NSError(domain: "MTP", code: -1, userInfo: [NSLocalizedDescriptionKey: "未选择设备"]))
                return
            }
            
            // 添加到传输队列
            TransferQueueManager.shared.addDownloadTask(
                deviceId: deviceId,
                file: file,
                destinationURL: url,
                conflictResolution: .rename
            )
            
            print("✅ 文件已添加到传输队列: \(url.path)")
            completionHandler(nil)
        }
    }
    
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }
}

// MARK: - 批量文件 Promise Delegate
@objc class BatchFilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let viewModel: MTPViewModel
    let files: [FileItem]
    
    init(viewModel: MTPViewModel, files: [FileItem]) {
        self.viewModel = viewModel
        self.files = files
        super.init()
    }
    
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        return "\(files.count) 个文件"
    }
    
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        print("📥 批量下载 \(files.count) 个文件到: \(url.path)")
        
        // 使用 DispatchQueue 避免拖拽重入问题
        DispatchQueue.main.async { [weak viewModel, files] in
            guard let viewModel = viewModel,
                  let deviceId = viewModel.selectedDevice?.id else {
                completionHandler(NSError(domain: "MTP", code: -1, userInfo: [NSLocalizedDescriptionKey: "未选择设备"]))
                return
            }
            
            // 批量添加到传输队列
            TransferQueueManager.shared.addDownloadTasks(
                deviceId: deviceId,
                files: files,
                destinationURL: url,
                conflictResolution: .ask
            )
            
            print("✅ \(files.count) 个文件已添加到传输队列")
            completionHandler(nil)
        }
    }
    
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }
}

// MARK: - NSTableView 拖拽扩展
extension NSTableView {
    func enableFileDragging() {
        // 注册拖拽类型
        registerForDraggedTypes([.fileURL])
        setDraggingSourceOperationMask(.copy, forLocal: false)
    }
}

// MARK: - NSCollectionView 拖拽扩展
extension NSCollectionView {
    func enableFileDragging() {
        // 注册拖拽类型
        registerForDraggedTypes([.fileURL])
        setDraggingSourceOperationMask(.copy, forLocal: false)
    }
}
