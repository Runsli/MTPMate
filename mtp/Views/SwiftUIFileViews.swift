//
//  SwiftUIFileViews.swift
//  mtp
//
//  Native SwiftUI file browsing views.
//

import SwiftUI
import AppKit

struct SwiftUIFileTableView: View {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    @Binding var sortOrder: [KeyPathComparator<FileItem>]
    
    var body: some View {
        Table(files, selection: $viewModel.selectedFiles, sortOrder: $sortOrder) {
            TableColumn("名称", value: \.name) { file in
                HStack(spacing: 6) {
                    FileIcon(file: file, size: 16)
                    Text(file.name)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    open(file)
                }
            }
            .width(min: 240, ideal: 360)
            
            TableColumn("修改时间", value: \.modifiedDate) { file in
                Text(file.modifiedDate, format: .dateTime.year().month().day().hour().minute())
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 170)
            
            TableColumn("大小", value: \.size) { file in
                Text(file.isDirectory ? "--" : file.formattedSize)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)
            
            TableColumn("类型", value: \.fileExtension) { file in
                Text(file.isDirectory ? "文件夹" : fileTypeText(file))
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 110)
        }
        .contextMenu(forSelectionType: String.self) { selection in
            fileContextMenu(selection: selection)
        } primaryAction: { selection in
            if let id = selection.first, let file = files.first(where: { $0.id == id }) {
                open(file)
            }
        }
        .onKeyPress(.space) {
            viewModel.previewSelectedFiles()
            return .handled
        }
        .onKeyPress(.return) {
            viewModel.openSelectedFile()
            return .handled
        }
        .onKeyPress(.delete) {
            viewModel.deleteSelectedFiles()
            return .handled
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(selection: Set<String>) -> some View {
        if selection.isEmpty {
            Button("刷新") {
                AppCommandCenter.shared.refresh()
            }
            Button("全选") {
                viewModel.selectAllFiles()
            }
        } else {
            Button("打开") {
                viewModel.openSelectedFile()
            }
            .disabled(selection.count != 1)
            
            Button("快速查看") {
                viewModel.previewSelectedFiles()
            }
            
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
    
    private func open(_ file: FileItem) {
        if file.isDirectory {
            viewModel.navigateToFolder(file)
        } else {
            viewModel.openFile(file)
        }
    }
}

struct SwiftUIFileIconGridView: View {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    
    private let columns = [
        GridItem(.adaptive(minimum: 86, maximum: 112), spacing: 18, alignment: .top)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(files) { file in
                    fileCell(file)
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contextMenu {
            Button("刷新") {
                AppCommandCenter.shared.refresh()
            }
            Button("全选") {
                viewModel.selectAllFiles()
            }
        }
        .onKeyPress(.space) {
            viewModel.previewSelectedFiles()
            return .handled
        }
        .onKeyPress(.delete) {
            viewModel.deleteSelectedFiles()
            return .handled
        }
    }
    
    private func fileCell(_ file: FileItem) -> some View {
        let isSelected = viewModel.selectedFiles.contains(file.id)
        
        return VStack(spacing: 6) {
            FileIcon(file: file, size: 40)
            
            Text(file.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 82)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .frame(width: 94, height: 86)
        .contentShape(Rectangle())
        .onTapGesture {
            select(file)
        }
        .onTapGesture(count: 2) {
            open(file)
        }
        .contextMenu {
            fileContextMenu(file)
        }
    }
    
    @ViewBuilder
    private func fileContextMenu(_ file: FileItem) -> some View {
        Button("打开") {
            open(file)
        }
        
        if !file.isDirectory {
            Button("快速查看") {
                viewModel.selectFile(file.id)
                viewModel.previewSelectedFiles()
            }
        }
        
        Divider()
        
        Button("下载") {
            viewModel.selectFile(file.id)
            viewModel.downloadSelectedFiles()
        }
        
        Divider()
        
        Button("删除", role: .destructive) {
            viewModel.selectFile(file.id)
            viewModel.deleteSelectedFiles()
        }
    }
    
    private func select(_ file: FileItem) {
        if NSEvent.modifierFlags.contains(.command) {
            viewModel.toggleFileSelection(file.id)
        } else {
            viewModel.selectFile(file.id)
        }
    }
    
    private func open(_ file: FileItem) {
        if file.isDirectory {
            viewModel.navigateToFolder(file)
        } else {
            viewModel.openFile(file)
        }
    }
}

struct SwiftUIColumnBrowserView: View {
    @ObservedObject var viewModel: MTPViewModel
    let files: [FileItem]
    @State private var columns: [ColumnState] = []
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(columns) { column in
                    List(column.files, selection: selectionBinding(for: column.id)) { file in
                        HStack(spacing: 6) {
                            FileIcon(file: file, size: 16)
                            Text(file.name)
                                .lineLimit(1)
                            Spacer()
                            if file.isDirectory {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                        .tag(file.id)
                        .onTapGesture {
                            select(file, in: column)
                        }
                        .onTapGesture(count: 2) {
                            open(file)
                        }
                        .contextMenu {
                            columnContextMenu(file)
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(width: 240)
                    
                    Divider()
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            resetColumns()
        }
        .onChange(of: files) { _, _ in
            resetColumns()
        }
        .onKeyPress(.space) {
            viewModel.previewSelectedFiles()
            return .handled
        }
        .onKeyPress(.delete) {
            viewModel.deleteSelectedFiles()
            return .handled
        }
    }
    
    @ViewBuilder
    private func columnContextMenu(_ file: FileItem) -> some View {
        Button("打开") {
            open(file)
        }
        
        if !file.isDirectory {
            Button("快速查看") {
                viewModel.selectFile(file.id)
                viewModel.previewSelectedFiles()
            }
        }
        
        Divider()
        
        Button("下载") {
            viewModel.selectFile(file.id)
            viewModel.downloadSelectedFiles()
        }
        
        Button("删除", role: .destructive) {
            viewModel.selectFile(file.id)
            viewModel.deleteSelectedFiles()
        }
    }
    
    private func resetColumns() {
        columns = [ColumnState(files: files)]
    }
    
    private func selectionBinding(for columnId: UUID) -> Binding<Set<String>> {
        Binding {
            columns.first(where: { $0.id == columnId })?.selection ?? []
        } set: { newValue in
            if let index = columns.firstIndex(where: { $0.id == columnId }) {
                columns[index].selection = newValue
            }
        }
    }
    
    private func select(_ file: FileItem, in column: ColumnState) {
        viewModel.selectFile(file.id)
        
        guard let index = columns.firstIndex(where: { $0.id == column.id }) else { return }
        columns = Array(columns.prefix(index + 1))
        columns[index].selection = [file.id]
        
        if file.isDirectory {
            Task {
                let children = await loadChildren(for: file)
                await MainActor.run {
                    columns.append(ColumnState(files: children, parentId: file.id))
                }
            }
        }
    }
    
    private func open(_ file: FileItem) {
        if file.isDirectory {
            viewModel.navigateToFolder(file)
        } else {
            viewModel.openFile(file)
        }
    }
    
    private func loadChildren(for folder: FileItem) async -> [FileItem] {
        guard let device = viewModel.selectedDevice else { return [] }
        
        do {
            return try await MTPFileManager.shared.listFiles(deviceId: device.id, parentId: folder.id)
        } catch {
            Logger.error("加载分栏内容失败: \(error.localizedDescription)")
            return []
        }
    }
    
    private struct ColumnState: Identifiable, Equatable {
        let id = UUID()
        var files: [FileItem]
        var parentId: String?
        var selection: Set<String> = []
    }
}

private struct FileIcon: View {
    let file: FileItem
    let size: CGFloat
    
    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
    
    private var icon: NSImage {
        if file.isDirectory {
            return NSImage(named: NSImage.folderName) ?? NSImage()
        }
        
        let fileType = file.fileExtension.isEmpty ? "public.data" : file.fileExtension
        return NSWorkspace.shared.icon(forFileType: fileType)
    }
}

private func fileTypeText(_ file: FileItem) -> String {
    if file.fileExtension.isEmpty {
        return "文件"
    }
    
    return file.fileExtension.uppercased()
}
