//
//  SystemColors.swift
//  mtp
//
//  系统动态颜色管理 - 自动适配系统强调色和外观模式
//

import SwiftUI
import AppKit

/// 系统颜色管理器 - 使用系统语义化颜色
struct SystemColors {
    
    // MARK: - 文件类型颜色（使用系统颜色）
    
    /// 获取文件类型的图标颜色（NSColor）
    static func fileIconColor(for file: FileItem) -> NSColor {
        if file.isDirectory {
            return .systemBlue  // 文件夹使用系统蓝色
        }
        
        switch file.fileExtension.lowercased() {
        case "jpg", "jpeg", "png", "gif", "heic", "webp", "bmp", "tiff":
            return .systemOrange  // 图片
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv":
            return .systemPurple  // 视频
        case "mp3", "m4a", "wav", "flac", "aac", "ogg":
            return .systemPink    // 音频
        case "pdf":
            return .systemRed     // PDF
        case "zip", "rar", "7z", "tar", "gz":
            return .systemGray    // 压缩文件
        case "doc", "docx", "txt", "rtf", "pages":
            return .systemBlue    // 文档
        case "xls", "xlsx", "numbers", "csv":
            return .systemGreen   // 表格
        case "ppt", "pptx", "key":
            return .systemOrange  // 演示文稿
        case "swift", "py", "js", "java", "cpp", "c", "h":
            return .systemIndigo  // 代码文件
        default:
            return .secondaryLabelColor  // 默认使用次要标签颜色
        }
    }
    
    /// 获取文件类型的图标颜色（SwiftUI Color）
    static func fileIconColorSwiftUI(for file: FileItem) -> Color {
        return Color(nsColor: fileIconColor(for: file))
    }
    
    // MARK: - 传输方向颜色
    
    /// 上传方向颜色
    static var uploadColor: Color {
        Color.accentColor  // 使用系统强调色
    }
    
    /// 上传方向颜色（NSColor）
    static var uploadColorNS: NSColor {
        .controlAccentColor  // 使用系统强调色
    }
    
    /// 下载方向颜色
    static var downloadColor: Color {
        Color.green  // 下载使用绿色
    }
    
    /// 下载方向颜色（NSColor）
    static var downloadColorNS: NSColor {
        .systemGreen
    }
    
    // MARK: - UI 元素颜色
    
    /// 选中背景色
    static var selectionBackground: Color {
        Color.accentColor  // 使用系统强调色
    }
    
    /// 选中背景色（NSColor）
    static var selectionBackgroundNS: NSColor {
        .controlAccentColor
    }
    
    /// 选中文本颜色
    static var selectionText: Color {
        Color.white
    }
    
    /// 选中文本颜色（NSColor）
    static var selectionTextNS: NSColor {
        .selectedTextColor
    }
    
    /// 主要文本颜色
    static var primaryText: Color {
        Color.primary
    }
    
    /// 主要文本颜色（NSColor）
    static var primaryTextNS: NSColor {
        .labelColor
    }
    
    /// 次要文本颜色
    static var secondaryText: Color {
        Color.secondary
    }
    
    /// 次要文本颜色（NSColor）
    static var secondaryTextNS: NSColor {
        .secondaryLabelColor
    }
    
    /// 背景颜色
    static var background: Color {
        Color(nsColor: .textBackgroundColor)
    }
    
    /// 背景颜色（NSColor）
    static var backgroundNS: NSColor {
        .textBackgroundColor
    }
    
    /// 分隔线颜色
    static var separator: Color {
        Color(nsColor: .separatorColor)
    }
    
    /// 分隔线颜色（NSColor）
    static var separatorNS: NSColor {
        .separatorColor
    }
    
    // MARK: - 状态颜色
    
    /// 成功/完成颜色
    static var success: Color {
        Color.green
    }
    
    /// 成功/完成颜色（NSColor）
    static var successNS: NSColor {
        .systemGreen
    }
    
    /// 警告颜色
    static var warning: Color {
        Color.orange
    }
    
    /// 警告颜色（NSColor）
    static var warningNS: NSColor {
        .systemOrange
    }
    
    /// 错误/失败颜色
    static var error: Color {
        Color.red
    }
    
    /// 错误/失败颜色（NSColor）
    static var errorNS: NSColor {
        .systemRed
    }
    
    /// 信息颜色
    static var info: Color {
        Color.blue
    }
    
    /// 信息颜色（NSColor）
    static var infoNS: NSColor {
        .systemBlue
    }
    
    // MARK: - 半透明效果
    
    /// 半透明背景（用于拖拽预览等）
    static var translucentBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.95)
    }
    
    /// 半透明背景（NSColor）
    static var translucentBackgroundNS: NSColor {
        .controlBackgroundColor.withAlphaComponent(0.95)
    }
    
    /// 高亮边框颜色
    static var highlightBorder: Color {
        Color.accentColor
    }
    
    /// 高亮边框颜色（NSColor）
    static var highlightBorderNS: NSColor {
        .controlAccentColor
    }
}

// MARK: - 便捷扩展

extension FileItem {
    /// 获取文件图标颜色（NSColor）
    var iconColorNS: NSColor {
        SystemColors.fileIconColor(for: self)
    }
    
    /// 获取文件图标颜色（SwiftUI Color）
    var iconColor: Color {
        SystemColors.fileIconColorSwiftUI(for: self)
    }
}

extension TransferDirection {
    /// 获取传输方向颜色（SwiftUI）
    var color: Color {
        switch self {
        case .upload:
            return SystemColors.uploadColor
        case .download:
            return SystemColors.downloadColor
        }
    }
    
    /// 获取传输方向颜色（NSColor）
    var colorNS: NSColor {
        switch self {
        case .upload:
            return SystemColors.uploadColorNS
        case .download:
            return SystemColors.downloadColorNS
        }
    }
}
