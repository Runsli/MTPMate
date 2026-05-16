//
//  NativeFileViews.swift
//  mtp
//
//  使用 AppKit 原生组件实现访达风格的文件视图
//

import SwiftUI
import AppKit

// MARK: - 原生列表视图（使用 NSTableView）
struct NativeListView: NSViewRepresentable {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = QuickLookEnabledTableView() // 使用自定义 TableView
        
        // 配置表格视图
        tableView.style = .fullWidth
        tableView.rowSizeStyle = .default
        tableView.usesAlternatingRowBackgroundColors = false // 访达默认不使用交替背景
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.target = context.coordinator
        tableView.coordinator = context.coordinator // 设置协调器引用
        
        // 添加列
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "名称"
        nameColumn.width = 300
        nameColumn.minWidth = 200
        tableView.addTableColumn(nameColumn)
        
        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "修改时间"
        dateColumn.width = 120
        dateColumn.minWidth = 100
        tableView.addTableColumn(dateColumn)
        
        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "大小"
        sizeColumn.width = 100
        sizeColumn.minWidth = 80
        tableView.addTableColumn(sizeColumn)
        
        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = "类型"
        typeColumn.width = 100
        typeColumn.minWidth = 80
        tableView.addTableColumn(typeColumn)
        
        // 设置数据源和代理
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        
        // 启用拖拽
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        
        // 添加右键菜单
        tableView.menu = context.coordinator.createContextMenu()
        
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        
        // 保存引用
        context.coordinator.tableView = tableView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        
        let needsReload = context.coordinator.files != files
        context.coordinator.files = files
        context.coordinator.viewModel = viewModel
        
        if needsReload {
            tableView.reloadData()
        }
        
        // 使用 DispatchQueue 避免布局递归
        let selectedIndexes = IndexSet(files.enumerated().compactMap { index, file in
            viewModel.selectedFiles.contains(file.id) ? index : nil
        })
        
        if !selectedIndexes.isEmpty || !tableView.selectedRowIndexes.isEmpty {
            DispatchQueue.main.async {
                tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, files: files)
    }
    
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var viewModel: MTPViewModel
        var files: [FileItem]
        weak var tableView: NSTableView?
        
        init(viewModel: MTPViewModel, files: [FileItem]) {
            self.viewModel = viewModel
            self.files = files
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            return files.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < files.count else { return nil }
            let file = files[row]
            
            let cellView = NSTableCellView()
            let textField = NSTextField()
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.isEditable = false
            textField.font = .systemFont(ofSize: 13)
            
            switch tableColumn?.identifier.rawValue {
            case "name":
                // 名称列：图标 + 文件名
                let imageView = NSImageView()
                imageView.image = NSImage(systemSymbolName: file.icon, accessibilityDescription: nil)
                imageView.contentTintColor = file.isDirectory ? .systemBlue : iconColor(for: file)
                imageView.translatesAutoresizingMaskIntoConstraints = false
                
                textField.stringValue = file.name
                textField.translatesAutoresizingMaskIntoConstraints = false
                
                cellView.addSubview(imageView)
                cellView.addSubview(textField)
                
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                ])
                
            case "date":
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                textField.stringValue = formatter.string(from: file.modifiedDate)
                textField.textColor = .secondaryLabelColor
                textField.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(textField)
                
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                ])
                
            case "size":
                textField.stringValue = file.isDirectory ? "—" : file.formattedSize
                textField.textColor = .secondaryLabelColor
                textField.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(textField)
                
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                ])
                
            case "type":
                textField.stringValue = file.isDirectory ? "文件夹" : (file.fileExtension.isEmpty ? "—" : file.fileExtension.uppercased())
                textField.textColor = .secondaryLabelColor
                textField.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(textField)
                
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
                ])
                
            default:
                break
            }
            
            return cellView
        }
        
        // MARK: - 拖拽支持
        
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < files.count else { return nil }
            let file = files[row]
            
            // 跳过文件夹
            if file.isDirectory {
                return nil
            }
            
            // 使用 NSFilePromiseProvider（推荐方式，不会阻塞主线程）
            let provider = FilePromiseProvider(viewModel: viewModel, file: file)
            return provider
        }
        
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
            print("🎯 开始拖拽 \(rowIndexes.count) 个文件")
        }
        
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            if operation == .copy {
                print("✅ 拖拽复制完成")
            }
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            
            let selectedIndexes = tableView.selectedRowIndexes
            let selectedIds = Set(selectedIndexes.compactMap { index in
                index < files.count ? files[index].id : nil
            })
            
            Task { @MainActor in
                self.viewModel.selectedFiles = selectedIds
            }
        }
        
        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0 && row < files.count else { return }
            
            let file = files[row]
            if file.isDirectory {
                viewModel.navigateToFolder(file)
            } else {
                viewModel.openFile(file)
            }
        }
        
        func createContextMenu() -> NSMenu {
            let menu = NSMenu()
            
            // 动态更新菜单项
            menu.delegate = self
            
            return menu
        }
        
        private func iconColor(for file: FileItem) -> NSColor {
            switch file.fileExtension {
            case "jpg", "jpeg", "png", "gif", "heic", "webp":
                return .systemOrange
            case "mp4", "mov", "avi", "mkv":
                return .systemPurple
            case "mp3", "m4a", "wav", "flac":
                return .systemPink
            case "pdf":
                return .systemRed
            case "zip", "rar", "7z":
                return .systemGray
            default:
                return .secondaryLabelColor
            }
        }
    }
}

// MARK: - NSMenuDelegate for dynamic context menu
extension NativeListView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        if viewModel.selectedFiles.isEmpty {
            // 空白区域右键菜单
            let refreshItem = NSMenuItem(title: "刷新", action: #selector(refreshAction), keyEquivalent: "r")
            refreshItem.target = self
            menu.addItem(refreshItem)
            
            menu.addItem(.separator())
            
            let selectAllItem = NSMenuItem(title: "全选", action: #selector(selectAllAction), keyEquivalent: "a")
            selectAllItem.target = self
            menu.addItem(selectAllItem)
        } else {
            // 选中文件的右键菜单
            if viewModel.selectedFiles.count == 1,
               let file = files.first(where: { viewModel.selectedFiles.contains($0.id) }),
               !file.isDirectory {
                let openItem = NSMenuItem(title: "打开", action: #selector(openAction), keyEquivalent: "")
                openItem.target = self
                menu.addItem(openItem)
                
                let quickLookItem = NSMenuItem(title: "快速查看", action: #selector(quickLookAction), keyEquivalent: " ")
                quickLookItem.target = self
                menu.addItem(quickLookItem)
                
                menu.addItem(.separator())
            }
            
            menu.addItem(.separator())
            
            let downloadItem = NSMenuItem(title: "下载", action: #selector(downloadAction), keyEquivalent: "d")
            downloadItem.target = self
            menu.addItem(downloadItem)
            
            menu.addItem(.separator())
            
            let deleteItem = NSMenuItem(title: "删除", action: #selector(deleteAction), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)
        }
    }
    
    @objc func refreshAction() {
        Task { @MainActor in
            guard let currentComponent = viewModel.pathComponents.last else { return }
            await viewModel.loadFiles(folderId: currentComponent.folderId)
        }
    }
    
    @objc func selectAllAction() {
        viewModel.selectAllFiles()
    }
    
    @objc func openAction() {
        if let file = files.first(where: { viewModel.selectedFiles.contains($0.id) }) {
            if file.isDirectory {
                viewModel.navigateToFolder(file)
            } else {
                viewModel.openFile(file)
            }
        }
    }
    
    @objc func quickLookAction() {
        viewModel.previewSelectedFiles()
    }
    
    @objc func downloadAction() {
        viewModel.downloadSelectedFiles()
    }
    
    @objc func deleteAction() {
        viewModel.deleteSelectedFiles()
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
        flowLayout.itemSize = NSSize(width: 80, height: 100)
        flowLayout.minimumInteritemSpacing = 20
        flowLayout.minimumLineSpacing = 20
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
            iconImageView.widthAnchor.constraint(equalToConstant: 48),
            iconImageView.heightAnchor.constraint(equalToConstant: 48),
            
            nameLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
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
        iconImageView.image = NSImage(systemSymbolName: file.icon, accessibilityDescription: nil)
        iconImageView.contentTintColor = file.isDirectory ? .systemBlue : iconColor(for: file)
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
    
    private func iconColor(for file: FileItem) -> NSColor {
        switch file.fileExtension {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .systemOrange
        case "mp4", "mov", "avi", "mkv":
            return .systemPurple
        case "mp3", "m4a", "wav", "flac":
            return .systemPink
        case "pdf":
            return .systemRed
        case "zip", "rar", "7z":
            return .systemGray
        default:
            return .secondaryLabelColor
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
            Image(systemName: file.icon)
                .font(SemanticFonts.iconSmall)
                .foregroundColor(file.isDirectory ? .blue : iconColor)
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

// 分栏视图的列表部分
struct NativeBrowserListView: NSViewRepresentable {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        // 配置表格视图（类似访达分栏视图）
        tableView.style = .plain
        tableView.rowSizeStyle = .default
        tableView.headerView = nil // 不显示表头
        tableView.allowsMultipleSelection = true
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.target = context.coordinator
        tableView.backgroundColor = .textBackgroundColor
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        
        // 添加单列
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.width = 250
        column.minWidth = 200
        column.maxWidth = 400
        tableView.addTableColumn(column)
        
        // 设置数据源和代理
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        
        // 添加右键菜单
        tableView.menu = context.coordinator.createContextMenu()
        
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        
        context.coordinator.tableView = tableView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        context.coordinator.files = files
        context.coordinator.viewModel = viewModel
        tableView.reloadData()
        
        // 更新选中状态
        let selectedIndexes = IndexSet(files.enumerated().compactMap { index, file in
            viewModel.selectedFiles.contains(file.id) ? index : nil
        })
        tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, files: files)
    }
    
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var viewModel: MTPViewModel
        var files: [FileItem]
        weak var tableView: NSTableView?
        
        init(viewModel: MTPViewModel, files: [FileItem]) {
            self.viewModel = viewModel
            self.files = files
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            return files.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < files.count else { return nil }
            let file = files[row]
            
            let cellView = NSTableCellView()
            cellView.wantsLayer = true
            
            // 展开箭头（仅文件夹）
            if file.isDirectory {
                let arrowView = NSImageView()
                arrowView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                arrowView.contentTintColor = .secondaryLabelColor
                arrowView.translatesAutoresizingMaskIntoConstraints = false
                cellView.addSubview(arrowView)
                
                NSLayoutConstraint.activate([
                    arrowView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
                    arrowView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                    arrowView.widthAnchor.constraint(equalToConstant: 10),
                    arrowView.heightAnchor.constraint(equalToConstant: 10)
                ])
            }
            
            // 图标
            let imageView = NSImageView()
            imageView.image = NSImage(systemSymbolName: file.icon, accessibilityDescription: nil)
            imageView.contentTintColor = file.isDirectory ? .systemBlue : iconColor(for: file)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(imageView)
            
            // 文件名
            let textField = NSTextField()
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.isEditable = false
            textField.font = .systemFont(ofSize: 13)
            textField.stringValue = file.name
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(textField)
            
            let leadingOffset: CGFloat = file.isDirectory ? 26 : 8
            
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: leadingOffset),
                imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])
            
            return cellView
        }
        
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            return 28 // 访达分栏视图的行高
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            
            let selectedIndexes = tableView.selectedRowIndexes
            let selectedIds = Set(selectedIndexes.compactMap { index in
                index < files.count ? files[index].id : nil
            })
            
            Task { @MainActor in
                self.viewModel.selectedFiles = selectedIds
            }
        }
        
        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0 && row < files.count else { return }
            
            let file = files[row]
            if file.isDirectory {
                viewModel.navigateToFolder(file)
            } else {
                viewModel.openFile(file)
            }
        }
        
        func createContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }
        
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            
            if viewModel.selectedFiles.isEmpty {
                // 空白区域右键菜单
                let refreshItem = NSMenuItem(title: "刷新", action: #selector(refreshAction), keyEquivalent: "r")
                refreshItem.target = self
                menu.addItem(refreshItem)
                
                menu.addItem(.separator())
                
                let selectAllItem = NSMenuItem(title: "全选", action: #selector(selectAllAction), keyEquivalent: "a")
                selectAllItem.target = self
                menu.addItem(selectAllItem)
            } else {
                // 选中文件的右键菜单
                if viewModel.selectedFiles.count == 1,
                   let file = files.first(where: { viewModel.selectedFiles.contains($0.id) }),
                   !file.isDirectory {
                    let openItem = NSMenuItem(title: "打开", action: #selector(openAction), keyEquivalent: "")
                    openItem.target = self
                    menu.addItem(openItem)
                    menu.addItem(.separator())
                }
                
                menu.addItem(.separator())
                
                let downloadItem = NSMenuItem(title: "下载", action: #selector(downloadAction), keyEquivalent: "d")
                downloadItem.target = self
                menu.addItem(downloadItem)
                
                menu.addItem(.separator())
                
                let deleteItem = NSMenuItem(title: "删除", action: #selector(deleteAction), keyEquivalent: "")
                deleteItem.target = self
                menu.addItem(deleteItem)
            }
        }
        
        @objc func refreshAction() {
            Task { @MainActor in
                guard let currentComponent = viewModel.pathComponents.last else { return }
                await viewModel.loadFiles(folderId: currentComponent.folderId)
            }
        }
        
        @objc func selectAllAction() {
            viewModel.selectAllFiles()
        }
        
        @objc func openAction() {
            if let file = files.first(where: { viewModel.selectedFiles.contains($0.id) }) {
                if file.isDirectory {
                    viewModel.navigateToFolder(file)
                } else {
                    viewModel.openFile(file)
                }
            }
        }
        
        @objc func downloadAction() {
            viewModel.downloadSelectedFiles()
        }
        
        @objc func deleteAction() {
            viewModel.deleteSelectedFiles()
        }
        
        private func iconColor(for file: FileItem) -> NSColor {
            switch file.fileExtension {
            case "jpg", "jpeg", "png", "gif", "heic", "webp":
                return .systemOrange
            case "mp4", "mov", "avi", "mkv":
                return .systemPurple
            case "mp3", "m4a", "wav", "flac":
                return .systemPink
            case "pdf":
                return .systemRed
            case "zip", "rar", "7z":
                return .systemGray
            default:
                return .secondaryLabelColor
            }
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
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 100, height: 100)
                    
                    Image(systemName: file.icon)
                        .font(SemanticFonts.iconMedium)
                        .foregroundColor(iconColor)
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


// MARK: - 支持 Quick Look 的自定义 TableView
class QuickLookEnabledTableView: NSTableView {
    weak var coordinator: NativeListView.Coordinator?
    
    override func keyDown(with event: NSEvent) {
        // 处理空格键
        if event.keyCode == 49 { // 空格键
            coordinator?.quickLookAction()
            return
        }
        
        // 其他键交给父类处理
        super.keyDown(with: event)
    }
}

// MARK: - 支持 Quick Look 的自定义 CollectionView
class QuickLookEnabledCollectionView: NSCollectionView {
    weak var coordinator: NativeIconView.Coordinator?
    
    override func keyDown(with event: NSEvent) {
        // 处理空格键
        if event.keyCode == 49 { // 空格键
            coordinator?.quickLookAction()
            return
        }
        
        // 其他键交给父类处理
        super.keyDown(with: event)
    }
}
