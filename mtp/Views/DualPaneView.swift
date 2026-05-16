//
//  DualPaneView.swift
//  mtp
//
//  Created by Li on 2026/4/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct DualPaneView: View {
    @ObservedObject var viewModel: MTPViewModel
    @StateObject private var localFileManager = LocalFileManager()
    @State private var activePane: PaneType = .device
    @State private var showingLocalFilePicker = false
    
    enum PaneType {
        case device
        case local
    }
    
    var body: some View {
        HSplitView {
            // 左栏：MTP设备文件
            VStack(spacing: 0) {
                // 设备栏标题
                HStack {
                    Image(systemName: "iphone")
                        .foregroundColor(.blue)
                    Text("设备文件")
                        .font(SemanticFonts.headline)
                    Spacer()
                }
                .padding()
                .background(activePane == .device ? Color.accentColor.opacity(0.1) : Color.clear)
                .onTapGesture {
                    activePane = .device
                }
                
                Divider()
                
                // 设备文件内容
                DeviceFilePane(viewModel: viewModel, isActive: activePane == .device)
            }
            .frame(minWidth: 400)
            
            // 右栏：本地文件系统
            VStack(spacing: 0) {
                // 本地文件栏标题
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(.orange)
                    Text("本地文件")
                        .font(SemanticFonts.headline)
                    Spacer()
                    Button(action: { showingLocalFilePicker = true }) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .help("选择文件夹")
                }
                .padding()
                .background(activePane == .local ? Color.accentColor.opacity(0.1) : Color.clear)
                .onTapGesture {
                    activePane = .local
                }
                
                Divider()
                
                // 本地文件内容
                LocalFilePane(
                    fileManager: localFileManager, 
                    isActive: activePane == .local,
                    onTransferToDevice: { urls in
                        transferFilesToDevice(urls)
                    }
                )
            }
            .frame(minWidth: 400)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // 传输按钮
                Button(action: transferSelectedToLocal) {
                    Label("传输到本地", systemImage: "arrow.right")
                }
                .disabled(viewModel.selectedFiles.isEmpty || localFileManager.currentURL == nil)
                .help("将选中的设备文件传输到本地文件夹")
                
                Button(action: transferSelectedToDevice) {
                    Label("传输到设备", systemImage: "arrow.left")
                }
                .disabled(localFileManager.selectedFiles.isEmpty || viewModel.selectedDevice == nil)
                .help("将选中的本地文件传输到设备")
                
                Divider()
                
                // 同步按钮
                Button(action: showSyncOptions) {
                    Label("同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(viewModel.selectedDevice == nil || localFileManager.currentURL == nil)
                .help("同步文件夹")
            }
        }
        .fileImporter(
            isPresented: $showingLocalFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    localFileManager.navigateToURL(url)
                }
            case .failure(let error):
                print("选择文件夹失败: \(error)")
            }
        }
    }
    
    private func transferSelectedToLocal() {
        guard !viewModel.selectedFiles.isEmpty,
              let localURL = localFileManager.currentURL else { return }
        
        Task {
            await viewModel.downloadSelectedFiles(to: localURL)
            await localFileManager.refresh()
        }
    }
    
    private func transferSelectedToDevice() {
        guard !localFileManager.selectedFiles.isEmpty,
              viewModel.selectedDevice != nil else { return }
        
        let urls = localFileManager.selectedFiles.compactMap { fileId in
            localFileManager.files.first { $0.id == fileId }?.url
        }
        
        transferFilesToDevice(urls)
    }
    
    private func transferFilesToDevice(_ urls: [URL]) {
        Task {
            await viewModel.uploadFiles(urls)
        }
    }
    
    private func showSyncOptions() {
        // TODO: 实现同步选项对话框
    }
}

// MARK: - Device File Pane
struct DeviceFilePane: View {
    @ObservedObject var viewModel: MTPViewModel
    let isActive: Bool
    @State private var searchText = ""
    @State private var selectedFilterOption: FilterOption = .all
    @State private var visibleFiles: [FileItem] = []
    
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
            if viewModel.selectedDevice == nil {
                DeviceSelectionView(viewModel: viewModel)
            } else {
                // 路径导航
                PathNavigationBar(viewModel: viewModel)
                
                Divider()
                
                // 筛选和搜索栏
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
                if viewModel.isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleFiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                            .font(SemanticFonts.iconMedium)
                            .foregroundColor(.secondary)
                        Text(searchText.isEmpty ? "文件夹为空" : "未找到匹配的文件")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    NativeTableView(
                        viewModel: viewModel,
                        files: visibleFiles
                    )
                }
            }
        }
        .onAppear(perform: refreshVisibleFiles)
        .onChange(of: viewModel.currentFiles) { _, _ in
            refreshVisibleFiles()
        }
        .onChange(of: searchText) { _, _ in
            refreshVisibleFiles()
        }
        .onChange(of: selectedFilterOption) { _, _ in
            refreshVisibleFiles()
        }
    }
    
    private func refreshVisibleFiles() {
        visibleFiles = filteredAndSortedFiles()
    }
    
    private func filteredAndSortedFiles() -> [FileItem] {
        var files = viewModel.currentFiles
        
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
        
        files.sort { file1, file2 in
            if file1.isDirectory != file2.isDirectory {
                return file1.isDirectory && !file2.isDirectory
            }
            return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
        }
        
        return files
    }
}

// MARK: - Device Selection View
struct DeviceSelectionView: View {
    @ObservedObject var viewModel: MTPViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(SemanticFonts.iconLarge)
                .foregroundColor(.secondary)
            Text("请选择设备")
                .font(SemanticFonts.title3)
                .foregroundColor(.secondary)
            
            if viewModel.devices.isEmpty {
                VStack(spacing: 8) {
                    Text("未检测到设备")
                        .foregroundColor(.secondary)
                    Button("扫描设备") {
                        Task {
                            await viewModel.scanDevices()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 8) {
                    Text("可用设备:")
                        .foregroundColor(.secondary)
                    
                    ForEach(viewModel.devices) { device in
                        Button(action: {
                            Task {
                                await viewModel.connectDevice(device)
                            }
                        }) {
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundColor(.blue)
                                Text(device.name)
                                Spacer()
                            }
                            .padding()
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    DualPaneView(viewModel: MTPViewModel())
        .frame(width: 1000, height: 700)
}