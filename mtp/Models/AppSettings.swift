//
//  AppSettings.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import Foundation
import SwiftUI
import Combine

enum FileViewMode: String, CaseIterable {
    case icons = "图标"
    case list = "列表"
    case columns = "分栏"
    
    var icon: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @AppStorage("playSoundOnComplete") var playSoundOnComplete: Bool = true
    @AppStorage("showNotificationOnComplete") var showNotificationOnComplete: Bool = true
    @AppStorage("fileViewMode") var fileViewModeRaw: String = FileViewMode.list.rawValue
    @AppStorage("showStatusBar") var showStatusBar: Bool = true  // 显示状态栏
    @AppStorage("showTransferQueue") var showTransferQueue: Bool = false
    @AppStorage("showHiddenFiles") var showHiddenFiles: Bool = false
    @AppStorage("useDefaultDownloadDirectory") var useDefaultDownloadDirectory: Bool = false
    @AppStorage("defaultDownloadDirectoryPath") var defaultDownloadDirectoryPath: String = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
    @AppStorage("conflictResolution") var conflictResolutionRaw: String = ConflictResolution.ask.rawValue
    
    var fileViewMode: FileViewMode {
        get { FileViewMode(rawValue: fileViewModeRaw) ?? .list }
        set { fileViewModeRaw = newValue.rawValue }
    }
    
    var conflictResolution: ConflictResolution {
        get { ConflictResolution(rawValue: conflictResolutionRaw) ?? .ask }
        set { conflictResolutionRaw = newValue.rawValue }
    }
    
    var defaultDownloadDirectoryURL: URL? {
        guard !defaultDownloadDirectoryPath.isEmpty else { return nil }
        return URL(fileURLWithPath: defaultDownloadDirectoryPath, isDirectory: true)
    }
    
    private init() {}
}