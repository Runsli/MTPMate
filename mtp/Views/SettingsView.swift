//
//  SettingsView.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI
import Combine
import AppKit

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section("外观") {
                Picker("默认视图", selection: $settings.fileViewModeRaw) {
                    ForEach(FileViewMode.allCases, id: \.rawValue) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode.rawValue)
                    }
                }
                
                Toggle("显示状态栏", isOn: $settings.showStatusBar)
                Toggle("显示隐藏文件", isOn: $settings.showHiddenFiles)
                Toggle("启动时显示传输队列", isOn: $settings.showTransferQueue)
            }
            
            Section("传输") {
                Picker("文件冲突", selection: $settings.conflictResolutionRaw) {
                    ForEach(ConflictResolution.allCases) { resolution in
                        Text(resolution.title).tag(resolution.rawValue)
                    }
                }
                
                Toggle("使用默认下载位置", isOn: $settings.useDefaultDownloadDirectory)
                
                HStack {
                    Text("下载位置")
                    Spacer()
                    Text(defaultDownloadDirectoryLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("选择...") {
                        chooseDefaultDownloadDirectory()
                    }
                }
                .disabled(!settings.useDefaultDownloadDirectory)
            }
            
            Section("通知") {
                Toggle("操作完成时显示通知", isOn: $settings.showNotificationOnComplete)
                Toggle("操作完成时播放声音", isOn: $settings.playSoundOnComplete)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 500, height: 420)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
    
    private var defaultDownloadDirectoryLabel: String {
        if settings.defaultDownloadDirectoryPath.isEmpty {
            return "未设置"
        }
        
        return URL(fileURLWithPath: settings.defaultDownloadDirectoryPath).lastPathComponent
    }
    
    private func chooseDefaultDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        
        if let currentURL = settings.defaultDownloadDirectoryURL {
            panel.directoryURL = currentURL
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            settings.defaultDownloadDirectoryPath = url.path
        }
    }
}

#Preview {
    SettingsView()
}