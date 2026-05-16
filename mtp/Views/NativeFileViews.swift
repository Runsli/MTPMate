//
//  NativeFileViews.swift
//  mtp
//
//  使用 AppKit 原生组件实现访达风格的文件视图
//

import SwiftUI
import AppKit

private enum NativeFileIconProvider {
    static let iconGridIconSize = NSSize(width: 64, height: 64)
    static let iconGridItemSize = NSSize(width: 112, height: 124)
    static let iconGridNameWidth: CGFloat = 104
    
    static func icon(for file: FileItem, size: NSSize) -> NSImage {
        let icon: NSImage
        
        if file.isDirectory {
            icon = NSImage(named: NSImage.folderName) ?? NSImage()
        } else {
            let fileType = file.fileExtension.isEmpty ? "public.data" : file.fileExtension
            icon = NSWorkspace.shared.icon(forFileType: fileType)
        }
        
        let copiedIcon = icon.copy() as? NSImage ?? icon
        copiedIcon.size = size
        return copiedIcon
    }
}

// MARK: - 原生图标视图（使用 NSCollectionView）
struct NativeIconView: NSViewRepresentable {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let collectionView = QuickLookEnabledCollectionView() // 使用自定义 CollectionView
        
        // 配置集合视图布局
        let flowLayout = NSCollectionViewFlowLayout()
        flowLayout.itemSize = NativeFileIconProvider.iconGridItemSize
        flowLayout.minimumInteritemSpacing = 24
        flowLayout.minimumLineSpacing = 22
        flowLayout.sectionInset = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        collectionView.collectionViewLayout = flowLayout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.textBackgroundColor]
        collectionView.coordinator = context.coordinator // 设置协调器引用
        
        // 注册单元格
        collectionView.register(
            FileIconCollectionItem.self,
            forItemWithIdentifier: NSUserInterfaceItemIdentifier("FileIconItem")
        )
        
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        
        // 保存引用
        context.coordinator.collectionView = collectionView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let collectionView = nsView.documentView as? NSCollectionView else { return }
        
        let needsReload = context.coordinator.files != files
        context.coordinator.files = files
        context.coordinator.viewModel = viewModel
        
        if needsReload {
            collectionView.reloadData()
        }
        
        // 使用 DispatchQueue 避免布局递归
        let selectedIndexPaths = Set(files.enumerated().compactMap { index, file in
            viewModel.selectedFiles.contains(file.id) ? IndexPath(item: index, section: 0) : nil
        })
        
        if !selectedIndexPaths.isEmpty || !collectionView.selectionIndexPaths.isEmpty {
            DispatchQueue.main.async {
                collectionView.selectionIndexPaths = selectedIndexPaths
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, files: files)
    }
    
    @MainActor
    class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var viewModel: MTPViewModel
        var files: [FileItem]
        weak var collectionView: NSCollectionView?
        
        init(viewModel: MTPViewModel, files: [FileItem]) {
            self.viewModel = viewModel
            self.files = files
        }
        
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            return files.count
        }
        
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: NSUserInterfaceItemIdentifier("FileIconItem"),
                for: indexPath
            ) as! FileIconCollectionItem
            
            let file = files[indexPath.item]
            
            item.configure(with: file)
            
            // 设置双击处理
            item.onDoubleClick = { [weak self] in
                guard let self = self else { return }
                if file.isDirectory {
                    self.viewModel.navigateToFolder(file)
                } else {
                    self.viewModel.openFile(file)
                }
            }
            
            return item
        }
        
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            updateSelection(collectionView)
        }
        
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            updateSelection(collectionView)
        }
        
        private func updateSelection(_ collectionView: NSCollectionView) {
            let selectedIds = Set(collectionView.selectionIndexPaths.compactMap { indexPath in
                indexPath.item < files.count ? files[indexPath.item].id : nil
            })
            
            // 使用 Task 避免在视图更新期间修改状态
            Task { @MainActor in
                self.viewModel.selectedFiles = selectedIds
            }
        }
        
        @objc func quickLookAction() {
            viewModel.previewSelectedFiles()
        }
    }
}

// 自定义集合视图单元格
class FileIconCollectionItem: NSCollectionViewItem {
    private let iconImageView = NSImageView()
    private let nameLabel = NSTextField()
    var onDoubleClick: (() -> Void)?
    
    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        
        // 配置图标
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.shadow = NSShadow()
        iconImageView.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.1)
        iconImageView.shadow?.shadowOffset = NSSize(width: 0, height: -1)
        iconImageView.shadow?.shadowBlurRadius = 1
        view.addSubview(iconImageView)
        
        // 配置文件名
        nameLabel.isBordered = false
        nameLabel.backgroundColor = .clear
        nameLabel.isEditable = false
        nameLabel.alignment = .center
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.maximumNumberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.drawsBackground = false
        view.addSubview(nameLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            iconImageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: NativeFileIconProvider.iconGridIconSize.width),
            iconImageView.heightAnchor.constraint(equalToConstant: NativeFileIconProvider.iconGridIconSize.height),
            
            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            nameLabel.widthAnchor.constraint(lessThanOrEqualToConstant: NativeFileIconProvider.iconGridNameWidth),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -4)
        ])
        
        // 添加双击手势
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        view.addGestureRecognizer(doubleClick)
    }
    
    @objc private func handleDoubleClick() {
        onDoubleClick?()
    }
    
    func configure(with file: FileItem) {
        iconImageView.image = NativeFileIconProvider.icon(for: file, size: NativeFileIconProvider.iconGridIconSize)
        iconImageView.contentTintColor = nil
        nameLabel.stringValue = file.name
    }
    
    override var isSelected: Bool {
        didSet {
            updateAppearance()
        }
    }
    
    private func updateAppearance() {
        if isSelected {
            nameLabel.backgroundColor = .controlAccentColor
            nameLabel.textColor = .white
            nameLabel.drawsBackground = true
            nameLabel.layer?.cornerRadius = 4
            nameLabel.layer?.masksToBounds = true
        } else {
            nameLabel.backgroundColor = .clear
            nameLabel.textColor = .labelColor
            nameLabel.drawsBackground = false
        }
    }
    
}

// MARK: - 原生分栏视图（多列层级导航）
struct NativeBrowserView: View {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    @State private var columnHierarchy: [ColumnLevel] = []
    @State private var selectedInColumn: [String: String] = [:] // columnId -> fileId
    @State private var scrollToId: String? // 用于自动滚动到最新列
    
    struct ColumnLevel: Identifiable {
        let id: String
        let files: [FileItem]
        let parentFolderId: String?
        let depth: Int
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 0) {
                        // 显示所有列
                        ForEach(columnHierarchy) { column in
                            VStack(spacing: 0) {
                                ColumnListView(
                                    files: column.files,
                                    selectedFileId: selectedInColumn[column.id],
                                    onSelect: { fileId in
                                        handleFileSelection(in: column, fileId: fileId)
                                    }
                                )
                            }
                            .frame(width: 250)
                            .id(column.id) // 为每列设置ID，用于滚动定位
                            
                            Divider()
                        }
                        
                        // 最后一列：预览面板（仅在选中非文件夹项目时显示）
                        if let lastColumn = columnHierarchy.last,
                           let selectedId = selectedInColumn[lastColumn.id],
                           let selectedFile = lastColumn.files.first(where: { $0.id == selectedId }),
                           !selectedFile.isDirectory { // 只有选中文件时才显示预览面板
                            
                            // 如果选中的是文件，显示预览
                            NativeBrowserPreviewPane(file: selectedFile)
                                .frame(minWidth: 250, maxHeight: .infinity)
                                .id("preview-file") // 预览面板也需要ID
                        } else if !columnHierarchy.isEmpty && columnHierarchy.last.map({ !$0.files.isEmpty }) ?? false {
                            // 只有在最后一列有内容但没有选中项时，才显示空白提示
                            VStack(spacing: 16) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(SemanticFonts.iconLarge)
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("选择一个项目")
                                    .font(SemanticFonts.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(minWidth: 250, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor))
                            .id("preview-empty")
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: scrollToId) { _, newId in
                    // 当scrollToId改变时，自动滚动到指定列
                    if let id = newId {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(id, anchor: .trailing)
                        }
                    }
                }
            }
        }
        .onAppear {
            initializeColumns()
        }
        .onChange(of: viewModel.pathComponents) { _, _ in
            // 路径改变时，重新初始化列并清空选中状态
            Task { @MainActor in
                updateColumnsFromPath()
            }
        }
        .onChange(of: files) { oldFiles, newFiles in
            // 只有当文件列表实际改变时才更新第一列
            // 避免在加载过程中频繁闪现
            if oldFiles.count != newFiles.count || 
               oldFiles.map({ $0.id }) != newFiles.map({ $0.id }) {
                // 更新第一列的文件内容，但保留选中状态
                if let firstColumn = columnHierarchy.first {
                    let updatedColumn = ColumnLevel(
                        id: firstColumn.id,
                        files: newFiles,
                        parentFolderId: firstColumn.parentFolderId,
                        depth: firstColumn.depth
                    )
                    columnHierarchy[0] = updatedColumn
                }
            }
        }
    }
    
    private func initializeColumns() {
        // 初始化第一列（当前路径的文件）
        let rootColumnId = UUID().uuidString
        let rootColumn = ColumnLevel(
            id: rootColumnId,
            files: files,
            parentFolderId: viewModel.pathComponents.last?.folderId,
            depth: 0
        )
        columnHierarchy = [rootColumn]
        
        // 清空之前的选中状态，但保留第一列的ID以便后续使用
        selectedInColumn = [:]
    }
    
    private func updateColumnsFromPath() {
        // 当路径改变时，重新初始化列并清空选中状态
        initializeColumns()
    }
    
    private func handleFileSelection(in column: ColumnLevel, fileId: String) {
        // 更新选中状态
        selectedInColumn[column.id] = fileId
        
        // 移除该列之后的所有列
        if let columnIndex = columnHierarchy.firstIndex(where: { $0.id == column.id }) {
            columnHierarchy = Array(columnHierarchy.prefix(columnIndex + 1))
        }
        
        // 如果选中的是文件夹，加载其内容到下一列
        if let file = column.files.first(where: { $0.id == fileId }), file.isDirectory {
            loadFolderInNextColumn(folder: file, afterColumn: column)
        } else {
            // 如果选中的是文件，滚动到预览面板
            scrollToId = "preview-file"
        }
        
        // 使用 Task 避免在视图更新期间修改状态
        Task { @MainActor in
            viewModel.selectedFiles = [fileId]
        }
    }
    
    private func handleDoubleClick(file: FileItem, in column: ColumnLevel) {
        // 在列视图中，双击和单击效果相同
        // 文件夹：已在单击时处理（加载下一列）
        // 文件：已在单击时处理（显示预览）
        // 这里保持空实现或移除，因为单击已经处理了所有逻辑
    }
    
    private func loadFolderInNextColumn(folder: FileItem, afterColumn: ColumnLevel) {
        guard let device = viewModel.selectedDevice else { return }
        
        Task {
            do {
                // 加载文件夹内容
                let folderFiles = try await MTPFileManager.shared.listFiles(
                    deviceId: device.id,
                    parentId: folder.id
                )
                
                await MainActor.run {
                    // 创建新列
                    let newColumn = ColumnLevel(
                        id: UUID().uuidString,
                        files: folderFiles,
                        parentFolderId: folder.id,
                        depth: afterColumn.depth + 1
                    )
                    
                    // 添加到列层级
                    columnHierarchy.append(newColumn)
                    
                    // 自动滚动到新添加的列（类似访达）
                    scrollToId = newColumn.id
                }
            } catch {
                print("❌ 加载文件夹失败: \(error)")
            }
        }
    }
}

// MARK: - 列视图组件
struct ColumnListView: View {
    let files: [FileItem]
    let selectedFileId: String?
    let onSelect: (String) -> Void
    
    var body: some View {
        if files.isEmpty {
            // 空文件夹提示
            VStack(spacing: 16) {
                Image(systemName: "folder")
                    .font(SemanticFonts.iconLarge)
                    .foregroundColor(.secondary.opacity(0.5))
                Text("文件夹为空")
                    .font(SemanticFonts.headline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(files) { file in
                        ColumnRowView(
                            file: file,
                            isSelected: selectedFileId == file.id,
                            onTap: {
                                onSelect(file.id)
                            }
                        )
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

// MARK: - 列行视图
struct ColumnRowView: View {
    let file: FileItem
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 图标
            Image(nsImage: NativeFileIconProvider.icon(for: file, size: NSSize(width: 18, height: 18)))
                .resizable()
                .scaledToFit()
                .frame(width: 20)
            
            // 文件名
            Text(file.name)
                .font(SemanticFonts.fileName)
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .primary)
            
            Spacer()
            
            // 文件夹箭头
            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(SemanticFonts.iconTiny)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // 双击：执行相同的操作
            onTap()
        }
        .onTapGesture(count: 1) {
            // 单击：执行相同的操作
            onTap()
        }
        .onHover { hovering in
            isHovered = hovering
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

// MARK: - 原生分栏视图预览面板（紧凑版）
struct NativeBrowserPreviewPane: View {
    let file: FileItem
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer()
                    .frame(height: 20)
                
                // 大图标
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 100, height: 100)
                    
                    Image(nsImage: NativeFileIconProvider.icon(for: file, size: NSSize(width: 64, height: 64)))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
                
                // 文件信息
                VStack(spacing: 12) {
                    // 文件名
                    Text(file.name)
                        .font(SemanticFonts.filePreviewName)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 16)
                    
                    Divider()
                        .padding(.horizontal, 30)
                    
                    // 详细信息
                    VStack(spacing: 10) {
                        if !file.isDirectory {
                            CompactInfoRow(label: "大小", value: file.formattedSize)
                        }
                        
                        CompactInfoRow(label: "修改", value: formatDate(file.modifiedDate))
                        
                        if !file.isDirectory && !file.fileExtension.isEmpty {
                            CompactInfoRow(label: "类型", value: file.fileExtension.uppercased())
                        } else if file.isDirectory {
                            CompactInfoRow(label: "类型", value: "文件夹")
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// 紧凑信息行组件
struct CompactInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(SemanticFonts.fileDetail)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(SemanticFonts.filePreviewDetail)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 支持 Quick Look 的自定义 CollectionView
@MainActor
class QuickLookEnabledCollectionView: NSCollectionView {
    weak var coordinator: NativeIconView.Coordinator?
    
    override func keyDown(with event: NSEvent) {
        if handleFinderKeyCommand(event) {
            return
        }
        
        // 其他键交给父类处理
        super.keyDown(with: event)
    }
    
    private func handleFinderKeyCommand(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased()
        
        if event.keyCode == 49 {
            coordinator?.quickLookAction()
            return true
        }
        
        if command, key == "a" {
            AppCommandCenter.shared.selectAll()
            return true
        }
        
        if command, key == "r" {
            AppCommandCenter.shared.refresh()
            return true
        }
        
        if command, key == "d" {
            AppCommandCenter.shared.download()
            return true
        }
        
        if command, event.keyCode == 51 {
            AppCommandCenter.shared.deleteSelected()
            return true
        }
        
        if event.keyCode == 36 {
            AppCommandCenter.shared.openSelected()
            return true
        }
        
        return false
    }
}
