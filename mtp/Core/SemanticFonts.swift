import SwiftUI

/// 语义化字体系统
/// 提供统一的字体样式，支持动态类型和可访问性
struct SemanticFonts {
    
    // MARK: - 标题字体
    
    /// 大标题 - 用于主要页面标题
    static let largeTitle = Font.largeTitle
    
    /// 标题1 - 用于重要区域标题
    static let title1 = Font.title
    
    /// 标题2 - 用于次级标题
    static let title2 = Font.title2
    
    /// 标题3 - 用于小节标题
    static let title3 = Font.title3
    
    // MARK: - 正文字体
    
    /// 标题行 - 用于列表项标题、强调文本
    static let headline = Font.headline
    
    /// 副标题 - 用于次要标题
    static let subheadline = Font.subheadline
    
    /// 正文 - 用于主要内容文本
    static let body = Font.body
    
    /// 标注 - 用于辅助说明文本
    static let callout = Font.callout
    
    /// 脚注 - 用于次要信息
    static let footnote = Font.footnote
    
    /// 说明文字1 - 用于小号说明文字
    static let caption1 = Font.caption
    
    /// 说明文字2 - 用于最小号说明文字
    static let caption2 = Font.caption2
    
    // MARK: - 图标字体
    
    /// 大图标 - 用于空状态、引导页面的大图标
    static let iconLarge = Font.system(size: 64)
    
    /// 中等图标 - 用于卡片、预览的图标
    static let iconMedium = Font.system(size: 48)
    
    /// 标准图标 - 用于列表项、按钮的图标
    static let iconRegular = Font.system(size: 40)
    
    /// 小图标 - 用于内联图标
    static let iconSmall = Font.system(size: 16)
    
    /// 微小图标 - 用于装饰性小图标
    static let iconTiny = Font.system(size: 10, weight: .semibold)
    
    // MARK: - 特殊用途字体
    
    /// 文件名 - 用于文件列表中的文件名
    static let fileName = Font.system(size: 13)
    
    /// 文件详情 - 用于文件详细信息
    static let fileDetail = Font.system(size: 11)
    
    /// 文件预览名称 - 用于图标视图中的文件名
    static let filePreviewName = Font.system(size: 14, weight: .medium)
    
    /// 文件预览详情 - 用于图标视图中的详细信息
    static let filePreviewDetail = Font.system(size: 12, weight: .medium)
    
    /// 徽章 - 用于通知徽章
    static let badge = Font.caption2
}

// MARK: - View Extension

extension View {
    /// 应用语义化字体
    func semanticFont(_ font: Font) -> some View {
        self.font(font)
    }
}
