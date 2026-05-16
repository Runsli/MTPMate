//
//  FileNameValidator.swift
//  mtp
//
//  Created by Li on 2026/4/19.
//

import Foundation

/// 文件名验证和清理工具
struct FileNameValidator {
    
    /// 非法文件名字符集
    private static let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
    
    /// 保留的文件名（Windows）
    private static let reservedNames: Set<String> = [
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    ]
    
    /// 清理文件名，移除非法字符
    static func sanitize(_ name: String) -> String {
        var sanitized = name.components(separatedBy: invalidChars).joined()
        
        // 移除前后空格
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 移除前后的点（避免隐藏文件问题）
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        
        // 限制长度（大多数文件系统限制为255字节）
        if sanitized.utf8.count > 255 {
            let index = sanitized.index(sanitized.startIndex, offsetBy: 255)
            sanitized = String(sanitized[..<index])
        }
        
        return sanitized
    }
    
    /// 验证文件名是否有效
    static func isValid(_ name: String) -> Bool {
        // 检查是否为空
        guard !name.isEmpty else { return false }
        
        // 检查是否包含非法字符
        if name.rangeOfCharacter(from: invalidChars) != nil {
            return false
        }
        
        // 检查是否为保留名称
        let upperName = name.uppercased()
        if reservedNames.contains(upperName) {
            return false
        }
        
        // 检查长度
        if name.utf8.count > 255 {
            return false
        }
        
        return true
    }
    
    /// 生成唯一文件名（如果文件已存在）
    static func makeUnique(_ name: String, existingNames: Set<String>) -> String {
        guard existingNames.contains(name) else {
            return name
        }
        
        let nameWithoutExtension = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        
        var counter = 1
        var uniqueName: String
        
        repeat {
            if ext.isEmpty {
                uniqueName = "\(nameWithoutExtension) (\(counter))"
            } else {
                uniqueName = "\(nameWithoutExtension) (\(counter)).\(ext)"
            }
            counter += 1
        } while existingNames.contains(uniqueName)
        
        return uniqueName
    }
    
    /// 验证并清理文件名，返回结果
    static func validateAndSanitize(_ name: String) -> Result<String, ValidationError> {
        let sanitized = sanitize(name)
        
        if sanitized.isEmpty {
            return .failure(.emptyName)
        }
        
        if !isValid(sanitized) {
            return .failure(.invalidCharacters)
        }
        
        return .success(sanitized)
    }
    
    enum ValidationError: LocalizedError {
        case emptyName
        case invalidCharacters
        case tooLong
        case reservedName
        
        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "文件名不能为空"
            case .invalidCharacters:
                return "文件名包含非法字符"
            case .tooLong:
                return "文件名过长"
            case .reservedName:
                return "文件名为系统保留名称"
            }
        }
    }
}
