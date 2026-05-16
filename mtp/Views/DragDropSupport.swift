//
//  DragDropSupport.swift
//  mtp
//
//  拖拽支持：从 MTP 设备拖拽文件到 macOS 本地
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FilePromiseType {
    static func identifier(for file: FileItem) -> String {
        if file.isDirectory {
            return UTType.folder.identifier
        }
        
        guard !file.fileExtension.isEmpty,
              let type = UTType(filenameExtension: file.fileExtension) else {
            return UTType.data.identifier
        }
        
        guard !type.identifier.hasPrefix("dyn.") else {
            return UTType.data.identifier
        }
        
        return type.identifier
    }
}

enum FilePromiseDestination {
    static func url(for file: FileItem, in destinationDirectory: URL) -> URL {
        destinationDirectory.appendingPathComponent(file.name, isDirectory: file.isDirectory)
    }
}

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
        
        super.init()
        self.fileType = FilePromiseType.identifier(for: file)
        self.delegate = promiseDelegate
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @available(*, unavailable, message: "Use init(viewModel:file:) instead.")
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
        let destinationURL = FilePromiseDestination.url(for: file, in: url)
        Logger.info("开始导出: \(file.name) -> \(destinationURL.path)")
        
        Task { @MainActor [viewModel, file] in
            do {
                try await viewModel.downloadPromisedItem(file, to: destinationURL)
                Logger.info("导出完成: \(file.name) -> \(destinationURL.path)")
                completionHandler(nil)
            } catch {
                Logger.error("导出失败: \(file.name) -> \(destinationURL.path) - \(error.localizedDescription)")
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
