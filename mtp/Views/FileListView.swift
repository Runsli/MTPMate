//
//  FileListView.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

struct FileListView: View {
    @ObservedObject var viewModel: MTPViewModel
    @StateObject private var settings = AppSettings.shared
    @State private var isDropTargeted = false
    @State private var searchText = ""
    @State private var selectedFilterOption: FilterOption = .all
    @State private var showingNewFolderDialog = false
    @State private var newFolderName = ""
    @State private var sortOrder: [KeyPathComparator<FileItem>] = []
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
        NavigationStack {
            VStack(spacing: 0) {
                // 路径导航栏
                PathNavigationBar(viewModel: viewModel)
                
                Divider()
                
                // 文件列表
                if viewModel.selectedDevice == nil {
                    MTPEmptyStateView(
                        systemImage: "iphone.and.arrow.forward",
                        title: "选择一台设备",
                        message: "连接 Android 设备后，在侧边栏选择设备即可浏览文件。"
                    )
                } else if viewModel.isLoading {
                    ProgressView("加载中...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleFiles.isEmpty {
                    MTPEmptyStateView(
                        systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                        title: searchText.isEmpty ? "文件夹为空" : "未找到匹配的文件",
                        message: searchText.isEmpty ? "这个位置暂时没有文件。你可以拖拽文件到这里上传。" : "请尝试其他关键词，或清除筛选条件后重新搜索。"
                    )
                } else {
                    Group {
                        switch settings.fileViewMode {
                        case .icons:
                            NativeIconView(
                                viewModel: viewModel,
                                files: visibleFiles
                            )
                        case .list:
                            NativeTableView(
                                viewModel: viewModel,
                                files: visibleFiles
                            )
                        case .columns:
                            NativeBrowserView(
                                viewModel: viewModel,
                                files: visibleFiles
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .onDrop(of: [.fileURL], delegate: FileDropDelegate(
                        viewModel: viewModel,
                        isTargeted: $isDropTargeted
                    ))
                    .overlay(
                        isDropTargeted ?
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 3)
                            .padding(4)
                        : nil
                    )
                }
                
                // 状态栏
                StatusBar(viewModel: viewModel)
            }
            .navigationTitle(viewModel.selectedDevice?.name ?? "文件")
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Picker("视图", selection: $settings.fileViewModeRaw) {
                        ForEach(FileViewMode.allCases, id: \.rawValue) { mode in
                            Label(mode.rawValue, systemImage: mode.icon)
                                .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewModel.selectedDevice == nil)
                    .help("切换视图模式")
                }
            }
            .searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: "搜索文件..."
            )
            .alert("新建文件夹", isPresented: $showingNewFolderDialog) {
                TextField("文件夹名称", text: $newFolderName)
                Button("取消", role: .cancel) {
                    newFolderName = ""
                }
                Button("创建") {
                    viewModel.createFolder(name: newFolderName)
                    newFolderName = ""
                }
                .disabled(newFolderName.isEmpty)
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
            .onChange(of: settings.showHiddenFiles) { _, _ in
                refreshVisibleFiles()
            }
        }
    }
    
    private var sortOrderBinding: Binding<[KeyPathComparator<FileItem>]> {
        Binding {
            sortOrder
        } set: { newValue in
            sortOrder = newValue
            refreshVisibleFiles(using: newValue)
        }
    }
    
    private func refreshVisibleFiles() {
        refreshVisibleFiles(using: sortOrder)
    }
    
    private func refreshVisibleFiles(using sortOrder: [KeyPathComparator<FileItem>]) {
        visibleFiles = filteredAndSortedFiles(using: sortOrder)
    }
    
    private func filteredAndSortedFiles(using sortOrder: [KeyPathComparator<FileItem>]) -> [FileItem] {
        var files = viewModel.currentFiles
        
        if !settings.showHiddenFiles {
            files = files.filter { !$0.name.hasPrefix(".") }
        }
        
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
        
        // 应用排序
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
            // 默认排序：文件夹在前，然后按名称排序
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

struct StatusBar: View {
    @ObservedObject var viewModel: MTPViewModel
    @StateObject private var settings = AppSettings.shared
    
    var body: some View {
        if settings.showStatusBar {
            HStack(spacing: 0) {
                // 左侧：项目统计
                HStack(spacing: 4) {
                    if let transferStatusMessage = viewModel.transferStatusMessage {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)
                        
                        Text(transferStatusMessage)
                            .font(SemanticFonts.fileDetail)
                            .foregroundColor(.secondary)
                    } else if viewModel.selectedFiles.isEmpty {
                        // 未选中时显示总数
                        Text(itemCountText)
                            .font(SemanticFonts.fileDetail)
                            .foregroundColor(.secondary)
                    } else {
                        // 选中时显示选中数量
                        Text(selectedCountText)
                            .font(SemanticFonts.fileDetail)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.leading, 8)
                .frame(maxHeight: .infinity)  // 垂直填充
                .alignmentGuide(VerticalAlignment.center) { d in d[VerticalAlignment.center] }
                
                Spacer()
            }
            .frame(height: 22)  // 访达状态栏高度
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(
                Divider(),
                alignment: .top
            )
        }
    }
    
    private var itemCountText: String {
        let count = viewModel.currentFiles.count
        if count == 0 {
            return "无项目"
        } else if count == 1 {
            return "1 个项目"
        } else {
            return "\(count) 个项目"
        }
    }
    
    private var selectedCountText: String {
        let selectedCount = viewModel.selectedFiles.count
        let totalCount = viewModel.currentFiles.count
        
        if selectedCount == 1 {
            return "已选中 1 个项目，共 \(totalCount) 个"
        } else {
            return "已选中 \(selectedCount) 个项目，共 \(totalCount) 个"
        }
    }
}

struct PathNavigationBar: View {
    @ObservedObject var viewModel: MTPViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(viewModel.pathComponents.enumerated()), id: \.element.id) { index, component in
                    Button(action: {
                        navigateToComponent(component)
                    }) {
                        Text(component.name == "/" ? "根目录" : component.name)
                            .font(SemanticFonts.filePreviewDetail)
                            .foregroundColor(index == viewModel.pathComponents.count - 1 ? .primary : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    if index < viewModel.pathComponents.count - 1 {
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
    
    private func navigateToComponent(_ component: PathComponent) {
        Task {
            await viewModel.navigateToPathComponent(component)
        }
    }
}

#Preview {
    FileListView(viewModel: MTPViewModel())
        .frame(width: 800, height: 600)
}
