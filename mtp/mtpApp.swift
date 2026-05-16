//
//  mtpApp.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI

@main
struct MTPApp: App {
    @StateObject private var commandCenter = AppCommandCenter.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // 移除"新建"菜单项（对文件管理器来说不太适用）
            CommandGroup(replacing: .newItem) {
                EmptyView()
            }
            
            CommandMenu("操作") {
                Button("刷新") {
                    commandCenter.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("上传...") {
                    commandCenter.upload()
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                
                Button("下载") {
                    commandCenter.download()
                }
                .keyboardShortcut("d", modifiers: .command)
                
                Divider()
                
                Button("打开") {
                    commandCenter.openSelected()
                }
                .keyboardShortcut(.return, modifiers: [])
                
                Button("快速查看") {
                    commandCenter.quickLook()
                }
                .keyboardShortcut(.space, modifiers: [])
                
                Button("全选") {
                    commandCenter.selectAll()
                }
                .keyboardShortcut("a", modifiers: .command)
                
                Button("删除") {
                    commandCenter.deleteSelected()
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            
            // 自定义应用菜单（只保留一个"关于"）
            CommandGroup(replacing: .appInfo) {
                Button("关于 MTPMate") {
                    showAboutPanel()
                }
                
                Divider()
                
                Button("偏好设置...") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            // 移除帮助菜单中的重复"关于"
            CommandGroup(replacing: .help) {
                Link("使用文档", destination: URL(string: "https://github.com/runsli/MTPMate")!)
                Link("报告问题", destination: URL(string: "https://github.com/runsli/MTPMate/issues")!)
            }
        }
        
        Settings {
            SettingsView()
        }
    }
    
    private func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "MTPMate"
        alert.informativeText = "版本 \(appVersionText)\n\n适用于 macOS 的 Android 设备文件传输工具"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        
        if let build, !build.isEmpty, build != version {
            return "\(version) (\(build))"
        }
        
        return version
    }
    
    private func openSettings() {
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
