//
//  NativeOutlineView.swift
//  mtp
//
//  macOS 原生 NSOutlineView 实现，支持文件夹展开/折叠
//

import SwiftUI
import AppKit

// MARK: - SwiftUI 包装器
struct NativeOutlineView: NSViewRepresentable {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let outlineView = FinderStyleOutlineView()
        outlineView.style = .fullWidth
        outlineView.rowSizeStyle = .default
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsMultipleSelection = true
        outlineView.allowsColumnReordering = false
        outlineView.allowsColumnResizing = true
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outlineView.floatsGroupRows = false
        outlineView.rowHeight = 24
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.indentationPerLevel = 16
        outlineView.autoresizesOutlineColumn = true
        outlineView.selectionHighlightStyle = .regular
        outlineView.gridStyleMask = []
        outlineView.backgroundColor = .textBackgroundColor
        
        // 设置双击动作
        outlineView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        outlineView.target = context.coordinator
        
        // 创建列
        setupColumns(for: outlineView, coordinator: context.coordinator)
        
        // 设置数据源和代理
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        
        // 启用拖拽（拖出）
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        
        // 启用拖放（拖入）
        outlineView.registerForDraggedTypes([.fileURL])
        
        // 设置右键菜单
        outlineView.menu = context.coordinator.createContextMenu()
        
        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView else { return }
        
        context.coordinator.viewModel = viewModel
        context.coordinator.rootFiles = files
        
        outlineView.reloadData()
        
        // 更新选中状态
        updateSelection(outlineView: outlineView, coordinator: context.coordinator)
    }
    
    private func updateSelection(outlineView: NSOutlineView, coordinator: Coordinator) {
        var selectedRows = IndexSet()
        
        func findRows(for item: Any?, at row: Int) {
            if let fileItem = item as? FileItem {
                if viewModel.selectedFiles.contains(fileItem.id) {
                    selectedRows.insert(row)
                }
            }
            
            let childCount = outlineView.numberOfChildren(ofItem: item)
            for i in 0..<childCount {
                if let child = outlineView.child(i, ofItem: item) {
                    let childRow = outlineView.row(forItem: child)
                    if childRow >= 0 {
                        findRows(for: child, at: childRow)
                    }
                }
            }
        }
        
        findRows(for: nil, at: 0)
        
        if outlineView.selectedRowIndexes != selectedRows {
            outlineView.selectRowIndexes(selectedRows, byExtendingSelection: false)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, files: files)
    }
    
    private func setupColumns(for outlineView: NSOutlineView, coordinator: Coordinator) {
        // 名称列（outline 列）
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "名称"
        nameColumn.width = 300
        nameColumn.minWidth = 150
        nameColumn.resizingMask = .userResizingMask
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true)
        outlineView.addTableColumn(nameColumn)
        outlineView.outlineTableColumn = nameColumn
        
        // 修改时间列
        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "修改时间"
        dateColumn.width = 140
        dateColumn.minWidth = 100
        dateColumn.resizingMask = .userResizingMask
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "modifiedDate", ascending: false)
        outlineView.addTableColumn(dateColumn)
        
        // 大小列
        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "大小"
        sizeColumn.width = 100
        sizeColumn.minWidth = 80
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        outlineView.addTableColumn(sizeColumn)
        
        // 类型列
        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = "类型"
        typeColumn.width = 100
        typeColumn.minWidth = 80
        typeColumn.resizingMask = .userResizingMask
        typeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "fileExtension", ascending: true)
        outlineView.addTableColumn(typeColumn)
    }
    
    // MARK: - Coordinator
    @MainActor
    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var viewModel: MTPViewModel
        var rootFiles: [FileItem]
        weak var outlineView: NSOutlineView?
        private var sortDescriptors: [NSSortDescriptor] = []
        private var expandedFolders: [String: [FileItem]] = [:] // folderId -> children
        private var loadingFolders: Set<String> = []
        
        init(viewModel: MTPViewModel, files: [FileItem]) {
            self.viewModel = viewModel
            self.rootFiles = files
            super.init()
        }
        
        // MARK: - Data Source
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                // 根级别
                return sortedFiles(rootFiles).count
            } else if let fileItem = item as? FileItem {
                // 文件夹的子项
                if fileItem.isDirectory {
                    return expandedFolders[fileItem.id]?.count ?? 0
                }
            }
            return 0
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                // 根级别
                return sortedFiles(rootFiles)[index]
            } else if let fileItem = item as? FileItem {
                // 文件夹的子项
                if let children = expandedFolders[fileItem.id] {
                    return sortedFiles(children)[index]
                }
            }
            return FileItem.samples[0] // 不应该到这里
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            if let fileItem = item as? FileItem {
                return fileItem.isDirectory
            }
            return false
        }
        
        func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
            return item
        }
        
        // MARK: - Delegate
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let fileItem = item as? FileItem else { return nil }
            
            let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
            var cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = identifier
            }
            
            // 清除旧内容
            cellView?.subviews.forEach { $0.removeFromSuperview() }
            
            switch tableColumn?.identifier.rawValue {
            case "name":
                // 图标 + 文件名（outline 列会自动添加展开/折叠三角形）
                let imageView = NSImageView()
                imageView.image = icon(for: fileItem)
                imageView.imageScaling = .scaleProportionallyDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                
                let textField = NSTextField()
                textField.stringValue = fileItem.name
                textField.isBordered = false
                textField.backgroundColor = .clear
                textField.isEditable = false
                textField.font = .systemFont(ofSize: NSFont.systemFontSize)
                textField.lineBreakMode = .byTruncatingTail
                textField.translatesAutoresizingMaskIntoConstraints = false
                
                cellView?.addSubview(imageView)
                cellView?.addSubview(textField)
                
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -6),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
                
            case "date":
                let textField = createTextField()
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                formatter.doesRelativeDateFormatting = true
                textField.stringValue = formatter.string(from: fileItem.modifiedDate)
                textField.textColor = SystemColors.secondaryTextNS
                cellView?.addSubview(textField)
                constrainTextField(textField, in: cellView!)
                
            case "size":
                let textField = createTextField()
                textField.stringValue = fileItem.isDirectory ? "—" : fileItem.formattedSize
                textField.textColor = SystemColors.secondaryTextNS
                textField.alignment = .right
                cellView?.addSubview(textField)
                constrainTextField(textField, in: cellView!)
                
            case "type":
                let textField = createTextField()
                if fileItem.isDirectory {
                    textField.stringValue = "文件夹"
                } else {
                    textField.stringValue = fileItem.fileExtension.isEmpty ? "—" : fileItem.fileExtension.uppercased()
                }
                textField.textColor = SystemColors.secondaryTextNS
                cellView?.addSubview(textField)
                constrainTextField(textField, in: cellView!)
                
            default:
                break
            }
            
            return cellView
        }
        
        // MARK: - 展开/折叠
        func outlineViewItemWillExpand(_ notification: Notification) {
            guard let fileItem = notification.userInfo?["NSObject"] as? FileItem else { return }
            
            // 如果还没有加载子项，则加载
            if expandedFolders[fileItem.id] == nil && !loadingFolders.contains(fileItem.id) {
                loadingFolders.insert(fileItem.id)
                loadFolderContents(fileItem)
            }
        }
        
        private func loadFolderContents(_ folder: FileItem) {
            guard let device = viewModel.selectedDevice else { return }
            
            Task {
                do {
                    let children = try await MTPFileManager.shared.listFiles(
                        deviceId: device.id,
                        parentId: folder.id
                    )
                    
                    await MainActor.run {
                        _ = self.expandedFolders[folder.id] = children
                        self.loadingFolders.remove(folder.id)
                        self.outlineView?.reloadItem(folder, reloadChildren: true)
                    }
                } catch {
                    Logger.error("加载文件夹内容失败: \(error.localizedDescription)")
                    _ = await MainActor.run {
                        self.loadingFolders.remove(folder.id)
                    }
                }
            }
        }
        
        // MARK: - 排序
        func outlineView(_ outlineView: NSOutlineView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            sortDescriptors = outlineView.sortDescriptors
            outlineView.reloadData()
        }
        
        private func sortedFiles(_ files: [FileItem]) -> [FileItem] {
            guard !sortDescriptors.isEmpty else {
                // 默认排序：文件夹在前，然后按名称
                return files.sorted { file1, file2 in
                    if file1.isDirectory != file2.isDirectory {
                        return file1.isDirectory
                    }
                    return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
                }
            }
            
            // 手动实现排序
            return files.sorted { file1, file2 in
                for descriptor in sortDescriptors {
                    let ascending = descriptor.ascending
                    
                    switch descriptor.key {
                    case "name":
                        let result = file1.name.localizedCaseInsensitiveCompare(file2.name)
                        if result != .orderedSame {
                            return ascending ? (result == .orderedAscending) : (result == .orderedDescending)
                        }
                    case "modifiedDate":
                        if file1.modifiedDate != file2.modifiedDate {
                            return ascending ? (file1.modifiedDate < file2.modifiedDate) : (file1.modifiedDate > file2.modifiedDate)
                        }
                    case "size":
                        if file1.size != file2.size {
                            return ascending ? (file1.size < file2.size) : (file1.size > file2.size)
                        }
                    case "fileExtension":
                        let result = file1.fileExtension.localizedCaseInsensitiveCompare(file2.fileExtension)
                        if result != .orderedSame {
                            return ascending ? (result == .orderedAscending) : (result == .orderedDescending)
                        }
                    default:
                        break
                    }
                }
                return false
            }
        }
        
        // MARK: - 选择
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            
            var selectedIds = Set<String>()
            for row in outlineView.selectedRowIndexes {
                if let item = outlineView.item(atRow: row) as? FileItem {
                    selectedIds.insert(item.id)
                }
            }
            
            Task { @MainActor in
                self.viewModel.selectedFiles = selectedIds
            }
        }
        
        // MARK: - 双击
        @objc func handleDoubleClick(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let item = sender.item(atRow: row) as? FileItem else { return }
            
            if item.isDirectory {
                // 双击文件夹：导航进入
                viewModel.navigateToFolder(item)
            } else {
                // 双击文件：打开
                viewModel.openFile(item)
            }
        }
        
        // MARK: - 拖拽（拖出）
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let fileItem = item as? FileItem else { return nil }
            guard !fileItem.isDirectory else { return nil }
            
            return FilePromiseProvider(viewModel: viewModel, file: fileItem)
        }
        
        // MARK: - 拖放（拖入）
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            // 只接受从外部拖入的文件
            guard info.draggingSource as? NSOutlineView !== outlineView else {
                return []
            }
            
            // 检查是否有文件URL
            guard info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else {
                return []
            }
            
            // 如果拖到文件夹上，允许放入该文件夹
            if let fileItem = item as? FileItem, fileItem.isDirectory {
                return .copy
            }
            
            // 否则放入当前文件夹
            return .copy
        }
        
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            // 获取拖入的文件URL
            guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
                return false
            }
            
            Logger.debug("拖入 \(urls.count) 个文件")
            
            // 确定目标文件夹
            // 如果拖到文件夹上，上传到该文件夹；否则上传到当前文件夹
            if let fileItem = item as? FileItem, fileItem.isDirectory {
                // TODO: 实现拖到特定文件夹的功能
                Logger.warning("暂不支持拖到特定文件夹，将上传到当前文件夹")
            }
            
            // 上传文件到当前文件夹
            Task {
                await viewModel.uploadFiles(urls)
            }
            
            return true
        }
        
        // MARK: - 右键菜单
        func createContextMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }
        
        // MARK: - 辅助方法
        private func createTextField() -> NSTextField {
            let textField = NSTextField()
            textField.isBordered = false
            textField.backgroundColor = .clear
            textField.isEditable = false
            textField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            return textField
        }
        
        private func constrainTextField(_ textField: NSTextField, in cellView: NSTableCellView) {
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])
        }
        
        private func icon(for file: FileItem) -> NSImage? {
            if file.isDirectory {
                return NSImage(named: NSImage.folderName)
            }
            
            let fileType = file.fileExtension.isEmpty ? "public.data" : file.fileExtension
            let icon = NSWorkspace.shared.icon(forFileType: fileType)
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }
    }
}

// MARK: - 自定义 OutlineView
@MainActor
class FinderStyleOutlineView: NSOutlineView {
    override func keyDown(with event: NSEvent) {
        if handleFinderKeyCommand(event) {
            return
        }
        
        super.keyDown(with: event)
    }
    
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        
        // 如果点击在行上且该行未被选中，则选中它
        if row >= 0 && !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        
        return super.menu(for: event)
    }
    
    private func handleFinderKeyCommand(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        let key = event.charactersIgnoringModifiers?.lowercased()
        
        if event.keyCode == 49 {
            AppCommandCenter.shared.quickLook()
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

// MARK: - Menu Delegate
extension NativeOutlineView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        if viewModel.selectedFiles.isEmpty {
            // 空白区域菜单
            addMenuItem(menu, title: "刷新", action: #selector(refreshAction), keyEquivalent: "r")
            menu.addItem(.separator())
            addMenuItem(menu, title: "全选", action: #selector(selectAllAction), keyEquivalent: "a")
        } else {
            // 选中文件菜单
            if viewModel.selectedFiles.count == 1 {
                addMenuItem(menu, title: "打开", action: #selector(openAction), keyEquivalent: "")
                addMenuItem(menu, title: "快速查看", action: #selector(quickLookAction), keyEquivalent: " ")
                menu.addItem(.separator())
            }
            
            menu.addItem(.separator())
            addMenuItem(menu, title: "下载", action: #selector(downloadAction), keyEquivalent: "d")
            menu.addItem(.separator())
            addMenuItem(menu, title: "删除", action: #selector(deleteAction), keyEquivalent: "")
        }
    }
    
    private func addMenuItem(_ menu: NSMenu, title: String, action: Selector, keyEquivalent: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        menu.addItem(item)
    }
    
    // MARK: - Menu Actions
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
        if let fileId = viewModel.selectedFiles.first,
           let file = findFile(byId: fileId) {
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
    
    private func findFile(byId id: String) -> FileItem? {
        // 在根文件中查找
        if let file = rootFiles.first(where: { $0.id == id }) {
            return file
        }
        
        // 在展开的文件夹中查找
        for children in expandedFolders.values {
            if let file = children.first(where: { $0.id == id }) {
                return file
            }
        }
        
        return nil
    }
}
