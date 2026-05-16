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
                } else if filteredFiles.isEmpty {
                    MTPEmptyStateView(
                        systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                        title: searchText.isEmpty ? "文件夹为空" : "未找到匹配的文件",
                        message: searchText.isEmpty ? "这个位置暂时没有文件。你可以拖拽文件到这里上传。" : "请尝试其他关键词，或清除筛选条件后重新搜索。"
                    )
                } else {
                    Group {
                        switch settings.fileViewMode {
                        case .icons:
                            SwiftUIFileIconGridView(
                                viewModel: viewModel,
                                files: sortedFiles
                            )
                        case .list:
                            SwiftUIFileTableView(
                                viewModel: viewModel,
                                files: sortedFiles,
                                sortOrder: $sortOrder
                            )
                        case .columns:
                            SwiftUIColumnBrowserView(
                                viewModel: viewModel,
                                files: sortedFiles
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
                // 左侧：视图模式切换
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
                
                // 右侧：主要操作
                ToolbarItemGroup(placement: .primaryAction) {
                    // 上传按钮
                    Button(action: { viewModel.uploadFiles() }) {
                        Label("上传", systemImage: "arrow.up.doc")
                    }
                    .disabled(viewModel.selectedDevice == nil)
                    .help("上传文件到设备")
                    
                    // 下载按钮
                    Button(action: { viewModel.downloadSelectedFiles() }) {
                        Label("下载", systemImage: "arrow.down.doc")
                    }
                    .disabled(viewModel.selectedFiles.isEmpty)
                    .help("下载选中的文件")
                    
                    // 更多操作菜单
                    Menu {
                        Section("筛选") {
                            Picker("显示", selection: $selectedFilterOption) {
                                ForEach(FilterOption.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        }
                        
                        Divider()
                        
                        Section("操作") {
                            Button(action: { viewModel.previewSelectedFiles() }) {
                                Label("快速查看", systemImage: "eye")
                            }
                            .disabled(viewModel.selectedFiles.isEmpty)
                            .keyboardShortcut(.space, modifiers: [])
                            
                            Button(action: { showingNewFolderDialog = true }) {
                                Label("新建文件夹", systemImage: "folder.badge.plus")
                            }
                            .disabled(viewModel.selectedDevice == nil)
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                        }
                        
                        Divider()
                        
                        Section("编辑") {
                            Button(action: { viewModel.deleteSelectedFiles() }) {
                                Label("删除", systemImage: "trash")
                            }
                            .disabled(viewModel.selectedFiles.isEmpty)
                            .keyboardShortcut(.delete, modifiers: [])
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                    .help("更多操作")
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
        }
    }
    
    private var filteredFiles: [FileItem] {
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
        
        return files
    }
    
    private var sortedFiles: [FileItem] {
        var files = filteredFiles
        
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
                    if viewModel.selectedFiles.isEmpty {
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

struct FileTable: View {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    @Binding var sortOrder: [KeyPathComparator<FileItem>]
    @State private var selectedFileForRename: FileItem?
    @State private var renameText = ""
    @State private var lastSelectedId: String?
    @State private var hoveredFileId: String?
    
    var body: some View {
        Table(files, selection: $viewModel.selectedFiles, sortOrder: $sortOrder) {
            TableColumn("名称", value: \.name) { file in
                HStack(spacing: 6) {
                    // 访达风格：小图标 + 文件名
                    Image(systemName: file.icon)
                        .font(SemanticFonts.iconSmall)
                        .foregroundColor(file.isDirectory ? .blue : iconColor(for: file))
                        .frame(width: 20)
                    
                    Text(file.name)
                        .font(SemanticFonts.fileName)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if file.isDirectory {
                        viewModel.navigateToFolder(file)
                    } else {
                        viewModel.openFile(file)
                    }
                }
                .onTapGesture(count: 1) { 
                    handleSingleTap(file: file)
                }
                .onHover { hovering in
                    hoveredFileId = hovering ? file.id : nil
                }
            }
            .width(min: 200, ideal: 300)
            
            TableColumn("修改时间", value: \.modifiedDate) { file in
                Text(file.modifiedDate, style: .date)
                    .font(SemanticFonts.filePreviewDetail)
                    .foregroundColor(.secondary)
            }
            .width(min: 100, ideal: 120)
            
            TableColumn("大小", value: \.size) { file in
                Text(file.isDirectory ? "—" : file.formattedSize)
                    .font(SemanticFonts.filePreviewDetail)
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)
            
            TableColumn("类型", value: \.fileExtension) { file in
                Text(file.isDirectory ? "文件夹" : (file.fileExtension.isEmpty ? "—" : file.fileExtension.uppercased()))
                    .font(SemanticFonts.filePreviewDetail)
                    .foregroundColor(.secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .alternatingRowBackgrounds(.disabled) // 访达风格：不使用交替行背景
        .contextMenu {
            if viewModel.selectedFiles.isEmpty {
                Button("刷新") {
                    Task {
                        guard let currentComponent = viewModel.pathComponents.last else { return }
                        await viewModel.loadFiles(folderId: currentComponent.folderId)
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Button("新建文件夹") {
                    // TODO: 显示新建文件夹对话框
                }
                .keyboardShortcut("n", modifiers: .command)
                
                Button("全选") {
                    viewModel.selectAllFiles()
                }
                .keyboardShortcut("a", modifiers: .command)
                
            } else {
                // 如果选中的是单个文件（非文件夹），显示"打开"选项
                if viewModel.selectedFiles.count == 1,
                   let selectedFile = files.first(where: { viewModel.selectedFiles.contains($0.id) }),
                   !selectedFile.isDirectory {
                    Button("打开") {
                        viewModel.openFile(selectedFile)
                    }
                    .keyboardShortcut(.return, modifiers: [])
                    
                    Button("快速查看") {
                        viewModel.previewSelectedFiles()
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    
                    Divider()
                }
                
                Button("下载") {
                    viewModel.downloadSelectedFiles()
                }
                .keyboardShortcut("d", modifiers: .command)
                
                Button("重命名") {
                    if let file = files.first(where: { viewModel.selectedFiles.contains($0.id) }) {
                        selectedFileForRename = file
                        renameText = file.name
                    }
                }
                .keyboardShortcut("r", modifiers: [])
                .disabled(viewModel.selectedFiles.count != 1)
                
                Divider()
                
                Button("删除", role: .destructive) {
                    deleteSelectedFiles()
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
        }
        .onKeyPress(.space) {
            // 空格键预览文件
            viewModel.previewSelectedFiles()
            return .handled
        }
        .onKeyPress(.return) {
            // 回车键打开选中的文件
            if viewModel.selectedFiles.count == 1,
               let selectedFile = files.first(where: { viewModel.selectedFiles.contains($0.id) }) {
                if selectedFile.isDirectory {
                    viewModel.navigateToFolder(selectedFile)
                } else {
                    viewModel.openFile(selectedFile)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            viewModel.deselectAllFiles()
            return .handled
        }
        .alert("重命名", isPresented: Binding(
            get: { selectedFileForRename != nil },
            set: { if !$0 { selectedFileForRename = nil } }
        )) {
            TextField("新名称", text: $renameText)
            Button("取消", role: .cancel) {
                selectedFileForRename = nil
            }
            Button("重命名") {
                if let file = selectedFileForRename {
                    viewModel.renameFile(file, to: renameText)
                }
                selectedFileForRename = nil
            }
            .disabled(renameText.isEmpty)
        }
    }
    
    private func iconColor(for file: FileItem) -> Color {
        switch file.fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .orange
        case "mp4", "mov", "avi", "mkv":
            return .purple
        case "mp3", "m4a", "wav", "flac":
            return .pink
        case "pdf":
            return .red
        case "zip", "rar", "7z":
            return .gray
        default:
            return .secondary
        }
    }
    
    private func handleSingleTap(file: FileItem) {
        let modifierFlags = NSEvent.modifierFlags
        
        if modifierFlags.contains(.command) {
            // Command + 点击：切换选择状态
            viewModel.toggleFileSelection(file.id)
            lastSelectedId = file.id
        } else if modifierFlags.contains(.shift) {
            // Shift + 点击：范围选择
            if let lastId = lastSelectedId {
                viewModel.selectRange(from: lastId, to: file.id)
            } else {
                viewModel.selectFile(file.id, multiSelect: false)
            }
            lastSelectedId = file.id
        } else {
            // 普通点击：单选
            viewModel.selectFile(file.id, multiSelect: false)
            lastSelectedId = file.id
        }
    }
    
    private func deleteSelectedFiles() {
        viewModel.deleteSelectedFiles()
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(SemanticFonts.iconLarge)
                .foregroundColor(.secondary)
            Text("请从左侧选择设备")
                .font(SemanticFonts.title3)
                .foregroundColor(.secondary)
            Text("连接 Android 设备后，从设备列表中选择要访问的设备")
                .font(SemanticFonts.caption1)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    FileListView(viewModel: MTPViewModel())
        .frame(width: 800, height: 600)
}


// MARK: - 图标视图（类似访达图标视图）
struct FileIconsView: View {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    @State private var hoveredFileId: String?
    
    // 访达风格：固定宽度的网格，间距更大
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 20, alignment: .top)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(files) { file in
                    FileIconItem(
                        file: file,
                        isSelected: viewModel.selectedFiles.contains(file.id),
                        isHovered: hoveredFileId == file.id
                    )
                    .onTapGesture(count: 2) {
                        handleDoubleTap(file: file)
                    }
                    .onTapGesture(count: 1) {
                        handleSingleTap(file: file)
                    }
                    .onHover { hovering in
                        hoveredFileId = hovering ? file.id : nil
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contextMenu {
            fileContextMenu()
        }
    }
    
    private func handleSingleTap(file: FileItem) {
        let modifierFlags = NSEvent.modifierFlags
        
        if modifierFlags.contains(.command) {
            viewModel.toggleFileSelection(file.id)
        } else if modifierFlags.contains(.shift) {
            if let lastId = viewModel.selectedFiles.first {
                viewModel.selectRange(from: lastId, to: file.id)
            } else {
                viewModel.selectFile(file.id, multiSelect: false)
            }
        } else {
            viewModel.selectFile(file.id, multiSelect: false)
        }
    }
    
    private func handleDoubleTap(file: FileItem) {
        if file.isDirectory {
            viewModel.navigateToFolder(file)
        } else {
            viewModel.openFile(file)
        }
    }
    
    
    @ViewBuilder
    private func fileContextMenu() -> some View {
        if viewModel.selectedFiles.isEmpty {
            Button("刷新") {
                Task {
                    guard let currentComponent = viewModel.pathComponents.last else { return }
                    await viewModel.loadFiles(folderId: currentComponent.folderId)
                }
            }
        } else {
            Button("打开") {
                if let file = files.first(where: { viewModel.selectedFiles.contains($0.id) }) {
                    if file.isDirectory {
                        viewModel.navigateToFolder(file)
                    } else {
                        viewModel.openFile(file)
                    }
                }
            }
            .disabled(viewModel.selectedFiles.count != 1)
            
            Divider()
            
            Button("复制") {
            }
            
            Divider()
            
            Button("删除", role: .destructive) {
                viewModel.deleteSelectedFiles()
            }
        }
    }
}

// 访达风格的图标项
struct FileIconItem: View {
    let file: FileItem
    let isSelected: Bool
    let isHovered: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            // 图标
            ZStack {
                // 访达风格：图标下方有轻微阴影
                Image(systemName: file.icon)
                    .font(SemanticFonts.iconMedium)
                    .foregroundColor(file.isDirectory ? .blue : iconColor)
                    .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
            }
            .frame(width: 80, height: 64)
            
            // 文件名
            Text(file.name)
                .font(SemanticFonts.fileDetail)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    // 访达风格：选中时文件名有圆角背景
                    RoundedRectangle(cornerRadius: 4)
                        .fill(textBackgroundColor)
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .frame(width: 80)
        .contentShape(Rectangle())
    }
    
    private var iconColor: Color {
        // 根据文件类型返回不同颜色（类似访达）
        switch file.fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .orange
        case "mp4", "mov", "avi", "mkv":
            return .purple
        case "mp3", "m4a", "wav", "flac":
            return .pink
        case "pdf":
            return .red
        case "zip", "rar", "7z":
            return .gray
        default:
            return .secondary
        }
    }
    
    private var textBackgroundColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color.secondary.opacity(0.15)
        } else {
            return Color.clear
        }
    }
}

// MARK: - 分栏视图（类似访达分栏视图）
struct FileColumnsView: View {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    @State private var hoveredFileId: String?
    @State private var columnWidth: CGFloat = 200
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // 当前文件夹列
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(files) { file in
                            FileColumnRowItem(
                                file: file,
                                isSelected: viewModel.selectedFiles.contains(file.id),
                                isHovered: hoveredFileId == file.id
                            )
                            .onTapGesture(count: 2) {
                                handleDoubleTap(file: file)
                            }
                            .onTapGesture(count: 1) {
                                handleSingleTap(file: file)
                            }
                            .onHover { hovering in
                                hoveredFileId = hovering ? file.id : nil
                            }
                        }
                    }
                }
                .frame(width: columnWidth)
                .background(Color(nsColor: .textBackgroundColor))
                
                Divider()
                
                // 预览区域（如果选中了单个文件）
                if viewModel.selectedFiles.count == 1,
                   let selectedFile = files.first(where: { viewModel.selectedFiles.contains($0.id) }) {
                    FilePreviewPane(file: selectedFile)
                        .frame(maxWidth: .infinity)
                } else {
                    // 空白区域
                    Color(nsColor: .textBackgroundColor)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .contextMenu {
            fileContextMenu()
        }
    }
    
    private func handleSingleTap(file: FileItem) {
        let modifierFlags = NSEvent.modifierFlags
        
        if modifierFlags.contains(.command) {
            viewModel.toggleFileSelection(file.id)
        } else if modifierFlags.contains(.shift) {
            if let lastId = viewModel.selectedFiles.first {
                viewModel.selectRange(from: lastId, to: file.id)
            } else {
                viewModel.selectFile(file.id, multiSelect: false)
            }
        } else {
            viewModel.selectFile(file.id, multiSelect: false)
        }
    }
    
    private func handleDoubleTap(file: FileItem) {
        if file.isDirectory {
            viewModel.navigateToFolder(file)
        } else {
            viewModel.openFile(file)
        }
    }
    
    @ViewBuilder
    private func fileContextMenu() -> some View {
        if viewModel.selectedFiles.isEmpty {
            Button("刷新") {
                Task {
                    guard let currentComponent = viewModel.pathComponents.last else { return }
                    await viewModel.loadFiles(folderId: currentComponent.folderId)
                }
            }
        } else {
            Button("打开") {
                if let file = files.first(where: { viewModel.selectedFiles.contains($0.id) }) {
                    if file.isDirectory {
                        viewModel.navigateToFolder(file)
                    } else {
                        viewModel.openFile(file)
                    }
                }
            }
            .disabled(viewModel.selectedFiles.count != 1)
            
            Divider()
            
            Button("下载") {
                viewModel.downloadSelectedFiles()
            }
            
            Divider()
            
            Button("删除", role: .destructive) {
                viewModel.deleteSelectedFiles()
            }
        }
    }
}

// 访达风格的分栏视图行项
struct FileColumnRowItem: View {
    let file: FileItem
    let isSelected: Bool
    let isHovered: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // 展开箭头（仅文件夹显示）
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(SemanticFonts.iconTiny)
                    .foregroundColor(.secondary)
                    .frame(width: 12)
            } else {
                Color.clear.frame(width: 12)
            }
            
            // 图标
            Image(systemName: file.icon)
                .font(SemanticFonts.iconSmall)
                .foregroundColor(file.isDirectory ? .blue : iconColor)
                .frame(width: 20)
            
            // 文件名
            Text(file.name)
                .font(SemanticFonts.filePreviewDetail)
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .primary)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .contentShape(Rectangle())
    }
    
    private var iconColor: Color {
        switch file.fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .orange
        case "mp4", "mov", "avi", "mkv":
            return .purple
        case "mp3", "m4a", "wav", "flac":
            return .pink
        case "pdf":
            return .red
        case "zip", "rar", "7z":
            return .gray
        default:
            return .secondary
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color.secondary.opacity(0.1)
        } else {
            return Color.clear
        }
    }
}

// 文件预览面板
struct FilePreviewPane: View {
    let file: FileItem
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            
            // 大图标
            Image(systemName: file.icon)
                .font(SemanticFonts.iconLarge)
                .foregroundColor(file.isDirectory ? .blue : iconColor)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 2)
            
            // 文件信息
            VStack(spacing: 8) {
                Text(file.name)
                    .font(SemanticFonts.headline)
                    .multilineTextAlignment(.center)
                
                if !file.isDirectory {
                    Text(file.formattedSize)
                        .font(SemanticFonts.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(file.modifiedDate, style: .date)
                    .font(SemanticFonts.caption1)
                    .foregroundColor(.secondary)
                
                if !file.isDirectory && !file.fileExtension.isEmpty {
                    Text(file.fileExtension.uppercased())
                        .font(SemanticFonts.caption1)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                        )
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private var iconColor: Color {
        switch file.fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .orange
        case "mp4", "mov", "avi", "mkv":
            return .purple
        case "mp3", "m4a", "wav", "flac":
            return .pink
        case "pdf":
            return .red
        case "zip", "rar", "7z":
            return .gray
        default:
            return .secondary
        }
    }
}
