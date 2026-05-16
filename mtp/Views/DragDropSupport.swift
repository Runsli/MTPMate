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
    var viewModel: MTPViewModel?
    var file: FileItem?
    private var promiseDelegate: FilePromiseDelegate?
    
    init(viewModel: MTPViewModel, file: FileItem) {
        // 创建代理对象
        let promiseDelegate = FilePromiseDelegate(viewModel: viewModel, file: file)
        self.viewModel = viewModel
        self.file = file
        self.promiseDelegate = promiseDelegate
        
        // 设置文件类型
        let fileType: String
        if file.fileExtension.isEmpty {
            fileType = "public.data"
        } else {
            fileType = "public.\(file.fileExtension)"
        }
        
        super.init()
        self.fileType = fileType
        self.delegate = promiseDelegate
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init() {
        super.init()
    }
}

// MARK: - 批量文件 Promise Provider
@objc class BatchFilePromiseProvider: NSFilePromiseProvider {
    var viewModel: MTPViewModel?
    var files: [FileItem] = []
    private var promiseDelegate: BatchFilePromiseDelegate?
    
    init(viewModel: MTPViewModel, files: [FileItem]) {
        // 创建代理对象
        let promiseDelegate = BatchFilePromiseDelegate(viewModel: viewModel, files: files)
        self.viewModel = viewModel
        self.files = files
        self.promiseDelegate = promiseDelegate
        
        super.init()
        self.fileType = "public.data"
        self.delegate = promiseDelegate
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init() {
        super.init()
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
        
        Task { @MainActor [viewModel, file] in
            do {
                try await viewModel.downloadPromisedFile(file, to: url)
                print("✅ 文件已下载: \(url.path)")
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
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
        
        Task { @MainActor [viewModel, files] in
            do {
                for file in files {
                    let destinationURL = url.appendingPathComponent(file.name)
                    try await viewModel.downloadPromisedFile(file, to: destinationURL)
                }
                print("✅ \(files.count) 个文件已下载")
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
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
