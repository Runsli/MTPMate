//
//  LocalFilePane.swift
//  mtp
//
//  Created by Li on 2026/4/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct LocalFilePane: View {
    @ObservedObject var fileManager: LocalFileManager
    let isActive: Bool
    let onTransferToDevice: ([URL]) -> Void
    
    @State private var searchText = ""
    @State private var selectedFilterOption: FilterOption = .all
    @State private var sortOrder: [KeyPathComparator<LocalFileItem>] = []
    @State private var showingNewFolderDialog = false
    @State private var newFolderName = ""
    
    enum FilterOption: String, CaseIterable {
        case all = "全部"
        case images = "图片"
        case videos = "视频"
        case audio = "音频"
        case documents = "文档"
        case folders = "文件夹"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 路径导航
            LocalPathNavigationBar(fileManager: fileManager)
            
            Divider()
            
            // 筛选栏
            HStack(spacing: 12) {
                Picker("筛选", selection: $selectedFilterOption) {
                    ForEach(FilterOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                
                Spacer()
                
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索文件...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .frame(maxWidth: 200)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // 文件列表
            if fileManager.isLoading {
                ProgressView("加载中...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = fileManager.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(SemanticFonts.iconMedium)
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                        .font(SemanticFonts.iconMedium)
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "文件夹为空" : "未找到匹配的文件")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LocalFileTable(
                    fileManager: fileManager,
                    files: sortedFiles,
                    sortOrder: $sortOrder,
                    isActive: isActive,
                    onTransferToDevice: onTransferToDevice
                )
            }
        }
        .alert("新建文件夹", isPresented: $showingNewFolderDialog) {
            TextField("文件夹名称", text: $newFolderName)
            Button("取消", role: .cancel) {
                newFolderName = ""
            }
            Button("创建") {
                fileManager.createFolder(name: newFolderName)
                newFolderName = ""
            }
            .disabled(newFolderName.isEmpty)
        }
    }
    
    private var filteredFiles: [LocalFileItem] {
        var files = fileManager.files
        
        // 搜索过滤
        if !searchText.isEmpty {
            files = files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        
        // 类型过滤
        switch selectedFilterOption {
        case .all:
            break
        case .images:
            files = files.filter { ["jpg", "jpeg", "png", "gif", "heic", "webp"].contains($0.fileExtension) }
        case .videos:
            files = files.filter { ["mp4", "mov", "avi", "mkv"].contains($0.fileExtension) }
        case .audio:
            files = files.filter { ["mp3", "m4a", "wav", "flac"].contains($0.fileExtension) }
        case .documents:
            files = files.filter { ["pdf", "doc", "docx", "txt", "md"].contains($0.fileExtension) }
        case .folders:
            files = files.filter { $0.isDirectory }
        }
        
        return files
    }
    
    private var sortedFiles: [LocalFileItem] {
        var files = filteredFiles
        
        if !sortOrder.isEmpty {
            files.sort { file1, file2 in
                for comparator in sortOrder {
                    let result = comparator.compare(file1, file2)
                    if result != .orderedSame {
                        return result == .orderedAscending
                    }
                }
                return false
            }
        } else {
            files.sort { file1, file2 in
                if file1.isDirectory != file2.isDirectory {
                    return file1.isDirectory && !file2.isDirectory
                }
                return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
            }
        }
        
        return files
    }
}

// MARK: - Local Path Navigation Bar
struct LocalPathNavigationBar: View {
    @ObservedObject var fileManager: LocalFileManager
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(fileManager.pathComponents.enumerated()), id: \.element.id) { index, component in
                    Button(action: {
                        fileManager.navigateToPathComponent(component)
                    }) {
                        Text(component.name)
                            .font(SemanticFonts.filePreviewDetail)
                            .foregroundColor(index == fileManager.pathComponents.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    if index < fileManager.pathComponents.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(SemanticFonts.iconTiny)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Local File Table
struct LocalFileTable: View {
    @ObservedObject var fileManager: LocalFileManager
    let files: [LocalFileItem]
    @Binding var sortOrder: [KeyPathComparator<LocalFileItem>]
    let isActive: Bool
    let onTransferToDevice: ([URL]) -> Void
    
    @State private var selectedFileForRename: LocalFileItem?
    @State private var renameText = ""
    @State private var lastSelectedId: String?
    
    var body: some View {
        Table(files, selection: $fileManager.selectedFiles, sortOrder: $sortOrder) {
            TableColumn("名称", value: \.name) { file in
                HStack(spacing: 8) {
                    Image(systemName: file.icon)
                        .foregroundColor(file.isDirectory ? .orange : .secondary)
                    Text(file.name)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if file.isDirectory {
                        fileManager.navigateToFolder(file)
                    } else {
                        fileManager.openFile(file)
                    }
                }
                .onTapGesture(count: 1) { 
                    handleSingleTap(file: file)
                }
            }
            .width(min: 150, ideal: 200)
            
            TableColumn("大小", value: \.size) { file in
                Text(file.isDirectory ? "—" : file.formattedSize)
                    .foregroundColor(.secondary)
            }
            .width(min: 60, ideal: 80)
            
            TableColumn("修改时间", value: \.modifiedDate) { file in
                Text(file.modifiedDate, style: .date)
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .contextMenu {
            if !fileManager.selectedFiles.isEmpty {
                Button("传输到设备") {
                    let selectedUrls = fileManager.selectedFiles.compactMap { fileId in
                        fileManager.files.first { $0.id == fileId }?.url
                    }
                    onTransferToDevice(selectedUrls)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                
                Divider()
                
                Button("打开") {
                    if let file = files.first(where: { fileManager.selectedFiles.contains($0.id) }) {
                        fileManager.openFile(file)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(fileManager.selectedFiles.count != 1)
                
                Button("在访达中显示") {
                    if let file = files.first(where: { fileManager.selectedFiles.contains($0.id) }) {
                        fileManager.revealInFinder(file)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(fileManager.selectedFiles.count != 1)
                
                Divider()
                
                Button("移到废纸篓", role: .destructive) {
                    fileManager.deleteSelectedFiles()
                }
                .keyboardShortcut(.delete, modifiers: [])
            } else {
                Button("刷新") {
                    Task {
                        await fileManager.refresh()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Button("新建文件夹") {
                    // TODO: 显示新建文件夹对话框
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("全选") {
                    fileManager.selectAllFiles()
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }
        .onKeyPress(.return) {
            if fileManager.selectedFiles.count == 1,
               let selectedFile = files.first(where: { fileManager.selectedFiles.contains($0.id) }) {
                if selectedFile.isDirectory {
                    fileManager.navigateToFolder(selectedFile)
                } else {
                    fileManager.openFile(selectedFile)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            fileManager.deselectAllFiles()
            return .handled
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            // 处理从其他应用拖拽的文件
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { _, error in
                    if let error = error {
                        print("拖拽文件失败: \(error)")
                    }
                    // TODO: 实现文件复制逻辑
                }
            }
            return true
        }
    }
    
    private func handleSingleTap(file: LocalFileItem) {
        let modifierFlags = NSEvent.modifierFlags
        
        if modifierFlags.contains(.command) {
            fileManager.toggleFileSelection(file.id)
            lastSelectedId = file.id
        } else if modifierFlags.contains(.shift) {
            if let lastId = lastSelectedId {
                fileManager.selectRange(from: lastId, to: file.id)
            } else {
                fileManager.selectFile(file.id, multiSelect: false)
            }
            lastSelectedId = file.id
        } else {
            fileManager.selectFile(file.id, multiSelect: false)
            lastSelectedId = file.id
        }
    }
}

#Preview {
    LocalFilePane(
        fileManager: LocalFileManager(),
        isActive: true,
        onTransferToDevice: { _ in }
    )
    .frame(width: 400, height: 600)
}