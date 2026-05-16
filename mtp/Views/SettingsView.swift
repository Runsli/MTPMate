//
//  SettingsView.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI
import Combine

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("设置")
                .font(SemanticFonts.title2)
                .fontWeight(.semibold)
            
            Form {
                Section("显示设置") {
                    Toggle(isOn: $settings.showStatusBar) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("显示状态栏")
                            Text("在窗口底部显示项目数量和选择信息")
                                .font(SemanticFonts.caption1)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("通知设置") {
                    Toggle(isOn: $settings.showNotificationOnComplete) {
                        Text("操作完成时显示通知")
                    }
                    
                    Toggle(isOn: $settings.playSoundOnComplete) {
                        Text("操作完成时播放声音")
                    }
                }
            }
            .formStyle(.grouped)
            
            Spacer()
            
            HStack {
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 450, height: 350)
    }
}

#Preview {
    SettingsView()
}