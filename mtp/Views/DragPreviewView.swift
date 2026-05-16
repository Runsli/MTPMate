//
//  DragPreviewView.swift
//  mtp
//
//  拖拽预览视图 - 显示半透明预览和传输方向
//

import SwiftUI

/// 拖拽预览视图
struct DragPreviewView: View {
    let files: [FileItem]
    let direction: TransferDirection
    
    var body: some View {
        VStack(spacing: 8) {
            // 方向指示器
            directionIndicator
            
            // 文件预览
            if files.count == 1, let file = files.first {
                singleFilePreview(file)
            } else {
                multipleFilesPreview
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(directionColor.opacity(0.5), lineWidth: 2)
        )
    }
    
    // MARK: - 方向指示器
    
    private var directionIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: directionIcon)
                .font(SemanticFonts.title2)
                .foregroundColor(directionColor)
            
            Text(directionText)
                .font(SemanticFonts.headline)
                .foregroundColor(directionColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(directionColor.opacity(0.15))
        )
    }
    
    private var directionIcon: String {
        switch direction {
        case .upload:
            return "arrow.up.circle.fill"
        case .download:
            return "arrow.down.circle.fill"
        }
    }
    
    private var directionText: String {
        switch direction {
        case .upload:
            return "上传到设备"
        case .download:
            return "下载到本地"
        }
    }
    
    private var directionColor: Color {
        direction.color
    }
    
    // MARK: - 单文件预览
    
    private func singleFilePreview(_ file: FileItem) -> some View {
        HStack(spacing: 12) {
            // 文件图标
            Image(systemName: file.icon)
                .font(SemanticFonts.iconRegular)
                .foregroundColor(file.iconColor)
                .frame(width: 60, height: 60)
                .background(file.iconColor.opacity(0.1))
                .cornerRadius(8)
            
            // 文件信息
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(SemanticFonts.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(file.formattedSize)
                    .font(SemanticFonts.caption1)
                    .foregroundColor(SystemColors.secondaryText)
            }
            .frame(maxWidth: 200, alignment: .leading)
        }
    }
    
    // MARK: - 多文件预览
    
    private var multipleFilesPreview: some View {
        VStack(spacing: 8) {
            // 文件堆叠图标
            ZStack {
                ForEach(0..<min(3, files.count), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "doc.fill")
                                .font(SemanticFonts.title1)
                                .foregroundColor(.accentColor)
                        )
                        .offset(x: CGFloat(index * 8), y: CGFloat(index * -8))
                }
            }
            .frame(height: 80)
            
            // 文件数量
            Text("\(files.count) 个文件")
                .font(SemanticFonts.headline)
            
            // 总大小
            Text(totalSizeFormatted)
                .font(SemanticFonts.caption1)
                .foregroundColor(SystemColors.secondaryText)
        }
    }
    
    private var totalSizeFormatted: String {
        let totalSize = files.reduce(0) { $0 + $1.size }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

// MARK: - 拖拽预览修饰符

extension View {
    /// 添加拖拽预览
    func dragPreview(files: [FileItem], direction: TransferDirection) -> some View {
        self.onDrag {
            let itemProvider = NSItemProvider()
            
            // 设置拖拽数据
            if let firstFile = files.first {
                itemProvider.suggestedName = files.count == 1 ? firstFile.name : "\(files.count) 个文件"
            }
            
            return itemProvider
        } preview: {
            DragPreviewView(files: files, direction: direction)
        }
    }
}

// MARK: - 拖拽目标高亮视图

struct DropTargetHighlight: View {
    let isTargeted: Bool
    let direction: TransferDirection
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 3, dash: [10, 5])
            )
            .foregroundColor(isTargeted ? highlightColor : .clear)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargeted ? highlightColor.opacity(0.1) : .clear)
            )
            .animation(.easeInOut(duration: 0.2), value: isTargeted)
    }
    
    private var highlightColor: Color {
        direction.color
    }
}

// MARK: - 拖拽目标修饰符

extension View {
    /// 添加拖拽目标高亮
    func dropTargetHighlight(isTargeted: Bool, direction: TransferDirection) -> some View {
        self.overlay(
            DropTargetHighlight(isTargeted: isTargeted, direction: direction)
        )
    }
}

#Preview("单文件上传") {
    DragPreviewView(
        files: [FileItem.samples[2]],
        direction: .upload
    )
    .padding()
}

#Preview("多文件下载") {
    DragPreviewView(
        files: Array(FileItem.samples.prefix(3)),
        direction: .download
    )
    .padding()
}
