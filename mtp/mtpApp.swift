//
//  mtpApp.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI

@main
struct MTPApp: App {
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
            
            // 自定义应用菜单（只保留一个"关于"）
            CommandGroup(replacing: .appInfo) {
                Button("关于 MTP 文件管理器") {
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
                Link("使用文档", destination: URL(string: "https://github.com/runsli/mtp")!)
                Link("报告问题", destination: URL(string: "https://github.com/runsli/mtp/issues")!)
            }
        }
        
        Settings {
            SettingsView()
        }
    }
    
    private func showAboutPanel() {
        let alert = NSAlert()
        alert.messageText = "MTP 文件管理器"
        alert.informativeText = "版本 1.0.0\n\n适用于 macOS 的 Android 设备文件传输工具"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    private func openSettings() {
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
