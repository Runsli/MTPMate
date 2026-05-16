//
//  SettingsView.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                generalSettings
                transferSettings
                notificationSettings
            }
            .padding(22)
            .frame(maxWidth: 520, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(width: 560, height: 480)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置")
                .font(.title2.weight(.semibold))

            Text("调整浏览、传输和通知偏好。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }
    
    private var generalSettings: some View {
        SettingsSectionCard(title: "通用") {
            SettingRow(title: "默认视图", description: "打开设备目录时使用的浏览方式。") {
                Picker("默认视图", selection: $settings.fileViewModeRaw) {
                    ForEach(FileViewMode.allCases, id: \.rawValue) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            
            SettingToggle(
                title: "显示状态栏",
                description: "显示文件数量、选中数量和设备状态。",
                isOn: $settings.showStatusBar
            )
            
            SettingToggle(
                title: "显示隐藏文件",
                description: "显示以点号开头的文件和文件夹。",
                isOn: $settings.showHiddenFiles
            )
        }
    }
    
    private var transferSettings: some View {
        SettingsSectionCard(title: "传输") {
            SettingRow(title: "文件冲突", description: "目标位置已有同名文件时的默认处理方式。") {
                Picker("文件冲突", selection: $settings.conflictResolutionRaw) {
                    ForEach(ConflictResolution.allCases) { resolution in
                        Text(resolution.title).tag(resolution.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            
            SettingToggle(
                title: "使用默认下载位置",
                description: "下载时直接保存到指定文件夹。",
                isOn: $settings.useDefaultDownloadDirectory
            )
            
            SettingRow(title: "下载位置", description: "用于批量下载和快速下载。") {
                HStack(spacing: 8) {
                    Text(defaultDownloadDirectoryLabel)
                    .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 120, alignment: .trailing)
                    
                    Button("选择...") {
                        chooseDefaultDownloadDirectory()
                    }
                    .disabled(!settings.useDefaultDownloadDirectory)
                }
            }
        }
    }
    
    private var notificationSettings: some View {
        SettingsSectionCard(title: "通知") {
            SettingToggle(
                title: "操作完成时显示通知",
                description: "上传、下载等操作完成后显示系统通知。",
                isOn: $settings.showNotificationOnComplete
            )
            
            SettingToggle(
                title: "操作完成时播放声音",
                description: "完成通知出现时播放系统提示音。",
                isOn: $settings.playSoundOnComplete
            )
            .disabled(!settings.showNotificationOnComplete)
        }
    }
    
    private struct SettingsSectionCard<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content
        
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 1)
                
                content
            }
            .padding(.bottom, 4)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            }
        }
    }
    
    private struct SettingRow<Content: View>: View {
        let title: String
        let description: String
        @ViewBuilder let content: Content
        
        var body: some View {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer(minLength: 16)
                
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    private struct SettingToggle: View {
        let title: String
        let description: String
        @Binding var isOn: Bool
        
        var body: some View {
            SettingRow(title: title, description: description) {
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
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