//
//  NativeTableView.swift
//  mtp
//
//  macOS 原生 NSTableView 实现，完全访达风格
//

import SwiftUI
import AppKit

// MARK: - SwiftUI 包装器
struct NativeTableView: NSViewRepresentable {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        let tableView = FinderStyleTableView()
        tableView.style = .fullWidth
        tableView.rowSizeStyle = .default
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.floatsGroupRows = false
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .regular
        tableView.gridStyleMask = []
        tableView.backgroundColor = .textBackgroundColor
        
        // 设置双击动作
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        tableView.target = context.coordinator
        
        // 创建列
        setupColumns(for: tableView, coordinator: context.coordinator)
        
        // 设置数据源和代理
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        
        // 启用拖拽（拖出）
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        
        // 启用拖放（拖入）
        tableView.registerForDraggedTypes([.fileURL])
        
        // 设置右键菜单
        tableView.menu = context.coordinator.createContextMenu()
        
        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        
        let needsReload = context.coordinator.files != files
        context.coordinator.viewModel = viewModel
        context.coordinator.files = files
        
        if needsReload {
            tableView.reloadData()
        }
        
        // 更新选中状态。NSTableView 展示的是 coordinator 内部排序后的数组。
        let selectedIndexes = context.coordinator.rowIndexes(for: viewModel.selectedFiles)
        
        if tableView.selectedRowIndexes != selectedIndexes {
            tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, files: files)
    }
    
    private func setupColumns(for tableView: NSTableView, coordinator: Coordinator) {
        // 名称列
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.title = "名称"
        nameColumn.width = 300
        nameColumn.minWidth = 150
        nameColumn.resizingMask = .userResizingMask
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        tableView.addTableColumn(nameColumn)
        
        // 修改时间列
        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("date"))
        dateColumn.title = "修改时间"
        dateColumn.width = 140
        dateColumn.minWidth = 100
        dateColumn.resizingMask = .userResizingMask
        dateColumn.sortDescriptorPrototype = NSSortDescriptor(key: "modifiedDate", ascending: false)
        tableView.addTableColumn(dateColumn)
        
        // 大小列
        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "大小"
        sizeColumn.width = 100
        sizeColumn.minWidth = 80
        sizeColumn.resizingMask = .userResizingMask
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "size", ascending: false)
        tableView.addTableColumn(sizeColumn)
        
        // 类型列
        let typeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeColumn.title = "类型"
        typeColumn.width = 100
        typeColumn.minWidth = 80
        typeColumn.resizingMask = .userResizingMask
        typeColumn.sortDescriptorPrototype = NSSortDescriptor(key: "fileExtension", ascending: true)
        tableView.addTableColumn(typeColumn)
    }
    
    // MARK: - Coordinator
    @MainActor
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var viewModel: MTPViewModel
        var files: [FileItem] {
            didSet {
                if oldValue != files {
                    cachedSortedFiles = nil
                }
            }
        }
        weak var tableView: NSTableView?
        private var sortDescriptors: [NSSortDescriptor] = []
        private var cachedSortedFiles: [FileItem]?
        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.doesRelativeDateFormatting = true
            return formatter
        }()
        private var iconCache: [String: NSImage] = [:]
        
        init(viewModel: MTPViewModel, files: [FileItem]) {
            self.viewModel = viewModel
            self.files = files
            super.init()
        }
        
        // MARK: - Data Source
        func numberOfRows(in tableView: NSTableView) -> Int {
            return sortedFiles().count
        }
        
        func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
            let sortedFiles = sortedFiles()
            guard row < sortedFiles.count else { return nil }
            return sortedFiles[row]
        }
        
        // MARK: - Delegate
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let sortedFiles = sortedFiles()
            guard row < sortedFiles.count else { return nil }
            let file = sortedFiles[row]
            
            switch tableColumn?.identifier.rawValue {
            case "name":
                let identifier = NSUserInterfaceItemIdentifier("nameCell")
                let cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? FinderNameCellView
                    ?? FinderNameCellView(identifier: identifier)
                cellView.configure(fileName: file.name, icon: icon(for: file))
                return cellView
            
            case "date":
                return configuredTextCell(
                    tableView,
                    identifier: "dateCell",
                    text: dateFormatter.string(from: file.modifiedDate)
                )
            
            case "size":
                return configuredTextCell(
                    tableView,
                    identifier: "sizeCell",
                    text: file.isDirectory ? "—" : file.formattedSize,
                    alignment: .right
                )
            
            case "type":
                return configuredTextCell(
                    tableView,
                    identifier: "typeCell",
                    text: file.isDirectory ? "文件夹" : (file.fileExtension.isEmpty ? "—" : file.fileExtension.uppercased())
                )
            
            default:
                return nil
            }
        }
        
        // MARK: - 排序
        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            sortDescriptors = tableView.sortDescriptors
            cachedSortedFiles = nil
            tableView.reloadData()
            
            // 保持选中状态
            let selectedIds = viewModel.selectedFiles
            let sortedFiles = sortedFiles()
            let newSelectedIndexes = IndexSet(sortedFiles.enumerated().compactMap { index, file in
                selectedIds.contains(file.id) ? index : nil
            })
            tableView.selectRowIndexes(newSelectedIndexes, byExtendingSelection: false)
        }
        
        private func sortedFiles() -> [FileItem] {
            if let cachedSortedFiles {
                return cachedSortedFiles
            }
            
            let sorted: [FileItem]
            guard !sortDescriptors.isEmpty else {
                // 默认排序：文件夹在前，然后按名称
                sorted = files.sorted { file1, file2 in
                    if file1.isDirectory != file2.isDirectory {
                        return file1.isDirectory
                    }
                    return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
                }
                cachedSortedFiles = sorted
                return sorted
            }
            
            // 手动实现排序
            sorted = files.sorted { file1, file2 in
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
            cachedSortedFiles = sorted
            return sorted
        }
        
        func rowIndexes(for selectedIds: Set<String>) -> IndexSet {
            let sortedFiles = sortedFiles()
            return IndexSet(sortedFiles.enumerated().compactMap { index, file in
                selectedIds.contains(file.id) ? index : nil
            })
        }
        
        // MARK: - 选择
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            
            let sortedFiles = sortedFiles()
            let selectedIds = Set(tableView.selectedRowIndexes.compactMap { index in
                index < sortedFiles.count ? sortedFiles[index].id : nil
            })
            
            Task { @MainActor in
                self.viewModel.selectedFiles = selectedIds
            }
        }
        
        // MARK: - 双击
        @objc func handleDoubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            let sortedFiles = sortedFiles()
            guard row >= 0 && row < sortedFiles.count else { return }
            
            let file = sortedFiles[row]
            if file.isDirectory {
                viewModel.navigateToFolder(file)
            } else {
                viewModel.openFile(file)
            }
        }
        
        // MARK: - 拖拽（拖出）
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            let sortedFiles = sortedFiles()
            guard row < sortedFiles.count else { return nil }
            let file = sortedFiles[row]
            
            guard !file.isDirectory else { return nil }
            
            return FilePromiseProvider(viewModel: viewModel, file: file)
        }
        
        // MARK: - 拖放（拖入）
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            // 只接受从外部拖入的文件
            guard info.draggingSource as? NSTableView !== tableView else {
                return []
            }
            
            // 检查是否有文件URL
            guard info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil) else {
                return []
            }
            
            // 设置为在整个表格上放置（而不是在特定行）
            tableView.setDropRow(-1, dropOperation: .on)
            
            return .copy
        }
        
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            // 获取拖入的文件URL
            guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
                return false
            }
            
            Logger.debug("拖入 \(urls.count) 个文件")
            
            // 上传文件
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
        private func configuredTextCell(
            _ tableView: NSTableView,
            identifier: String,
            text: String,
            alignment: NSTextAlignment = .left
        ) -> FinderTextCellView {
            let itemIdentifier = NSUserInterfaceItemIdentifier(identifier)
            let cellView = tableView.makeView(withIdentifier: itemIdentifier, owner: self) as? FinderTextCellView
                ?? FinderTextCellView(identifier: itemIdentifier)
            cellView.configure(text: text, alignment: alignment)
            return cellView
        }
        
        private func icon(for file: FileItem) -> NSImage? {
            if file.isDirectory {
                return NSImage(named: NSImage.folderName)
            }
            
            let fileType = file.fileExtension.isEmpty ? "public.data" : file.fileExtension
            if let cachedIcon = iconCache[fileType] {
                return cachedIcon
            }
            
            let icon = NSWorkspace.shared.icon(forFileType: fileType)
            icon.size = NSSize(width: 16, height: 16)
            iconCache[fileType] = icon
            return icon
        }
    }
}

@MainActor
private final class FinderNameCellView: NSTableCellView {
    private let iconImageView = NSImageView()
    private let nameTextField = NSTextField(labelWithString: "")
    
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    func configure(fileName: String, icon: NSImage?) {
        iconImageView.image = icon
        nameTextField.stringValue = fileName
    }
    
    private func setupViews() {
        guard subviews.isEmpty else { return }
        
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        nameTextField.font = .systemFont(ofSize: NSFont.systemFontSize)
        nameTextField.lineBreakMode = .byTruncatingTail
        nameTextField.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(iconImageView)
        addSubview(nameTextField)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 16),
            iconImageView.heightAnchor.constraint(equalToConstant: 16),
            
            nameTextField.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 6),
            nameTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

@MainActor
private final class FinderTextCellView: NSTableCellView {
    private let valueTextField = NSTextField(labelWithString: "")
    
    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    func configure(text: String, alignment: NSTextAlignment = .left) {
        valueTextField.stringValue = text
        valueTextField.alignment = alignment
    }
    
    private func setupViews() {
        guard subviews.isEmpty else { return }
        
        valueTextField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        valueTextField.textColor = .secondaryLabelColor
        valueTextField.lineBreakMode = .byTruncatingTail
        valueTextField.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(valueTextField)
        
        NSLayoutConstraint.activate([
            valueTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            valueTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            valueTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

// MARK: - 自定义 TableView
@MainActor
class FinderStyleTableView: NSTableView {
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
extension NativeTableView.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        
        if viewModel.selectedFiles.isEmpty {
            // 空白区域菜单
            addMenuItem(menu, title: "刷新", action: #selector(refreshAction), keyEquivalent: "r")
            menu.addItem(.separator())
            addMenuItem(menu, title: "全选", action: #selector(selectAllAction), keyEquivalent: "a")
        } else {
            // 选中文件菜单
            let sortedFiles = sortedFiles()
            if viewModel.selectedFiles.count == 1,
               let file = sortedFiles.first(where: { viewModel.selectedFiles.contains($0.id) }),
               !file.isDirectory {
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
        let sortedFiles = sortedFiles()
        if let file = sortedFiles.first(where: { viewModel.selectedFiles.contains($0.id) }) {
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
