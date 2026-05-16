//
//  DeviceListView.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI
import Combine

struct DeviceListView: View {
    @ObservedObject var viewModel: MTPViewModel
    @State private var showingPermissionHelp = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 错误消息
            if let errorMessage = viewModel.errorMessage {
                MTPEmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "无法连接设备",
                    message: errorMessage,
                    actionTitle: "重新扫描",
                    action: {
                        Task { await viewModel.scanDevices() }
                    }
                )
            }
            
            // 设备列表
            if viewModel.errorMessage != nil {
                EmptyView()
            } else if viewModel.devices.isEmpty && !viewModel.isScanning {
                MTPEmptyStateView(
                    systemImage: "iphone.slash",
                    title: "未检测到设备",
                    message: "连接 Android 设备，解锁手机，并在 USB 通知中选择文件传输或 MTP 模式。",
                    actionTitle: "扫描设备",
                    action: {
                        Task { await viewModel.scanDevices() }
                    }
                )
            } else if viewModel.isScanning {
                MTPEmptyStateView(
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
                    title: "正在扫描设备",
                    message: "MTPMate 正在查找可用的 Android/MTP 设备，请保持设备已解锁。"
                )
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.devices) { device in
                            DeviceCard(
                                device: device,
                                isSelected: viewModel.selectedDevice?.id == device.id,
                                onSelect: { 
                                    Task {
                                        await viewModel.connectDevice(device)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 250, idealWidth: 280)
        .navigationTitle("设备")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: showPermissionHelp) {
                    Image(systemName: "questionmark.circle")
                }
                .help("权限设置帮助")
            }
        }
        .sheet(isPresented: $showingPermissionHelp) {
            PermissionHelpView()
        }
    }
    
    private func showPermissionHelp() {
        showingPermissionHelp = true
    }
}

struct DeviceCard: View {
    let device: MTPDevice
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "iphone")
                        .font(SemanticFonts.title2)
                        .foregroundColor(device.isConnected ? .blue : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(SemanticFonts.headline)
                            .foregroundColor(.primary)
                        if let usbSpeed = device.usbSpeed {
                            Text(usbSpeed)
                                .font(SemanticFonts.caption1)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if let battery = device.batteryLevel {
                        HStack(spacing: 4) {
                            Image(systemName: batteryIcon(for: battery))
                                .foregroundColor(batteryColor(for: battery))
                            Text("\(battery)%")
                                .font(SemanticFonts.caption1)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let storage = device.storageInfo {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("存储空间")
                                .font(SemanticFonts.caption1)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(formatBytes(storage.freeSpace)) 可用")
                                .font(SemanticFonts.caption1)
                                .foregroundColor(.secondary)
                        }
                        
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.secondary.opacity(0.2))
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(storageColor(for: storage.usedPercentage))
                                    .frame(width: geometry.size.width * storage.usedPercentage)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func batteryIcon(for level: Int) -> String {
        switch level {
        case 0...20: return "battery.0"
        case 21...50: return "battery.25"
        case 51...75: return "battery.50"
        case 76...95: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private func batteryColor(for level: Int) -> Color {
        level <= 20 ? .red : .green
    }
    
    private func storageColor(for percentage: Double) -> Color {
        if percentage > 0.9 {
            return .red
        } else if percentage > 0.7 {
            return .orange
        } else {
            return .blue
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    DeviceListView(viewModel: MTPViewModel())
        .frame(width: 280, height: 600)
}

struct PermissionHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.orange)
                    .font(SemanticFonts.title2)
                Text("设备检测问题解决方案")
                    .font(SemanticFonts.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("关闭") {
                    dismiss()
                }
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Group {
                        Text("📱 手机端设置")
                            .font(SemanticFonts.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. 确保手机已解锁")
                            Text("2. 连接USB后，在通知栏选择「文件传输(MTP)」模式")
                            Text("3. 如果弹出「是否信任此计算机」，选择「信任」")
                            Text("4. 启用开发者选项中的「USB调试」（可选）")
                        }
                        .font(SemanticFonts.body)
                        .padding(.leading)
                    }
                    
                    Group {
                        Text("💻 Mac端权限")
                            .font(SemanticFonts.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("如果仍无法检测到设备，可能是权限问题：")
                            Text("• 在终端运行：mtp-detect")
                            Text("• 如果显示权限错误，请检查 USB 权限和设备信任状态")
                            Text("• 重新插拔 USB 连接后再次扫描设备")
                        }
                        .font(SemanticFonts.body)
                        .padding(.leading)
                    }
                    
                    Group {
                        Text("🔧 常见问题")
                            .font(SemanticFonts.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• 重新插拔USB线")
                            Text("• 尝试不同的USB端口")
                            Text("• 重启手机和Mac")
                            Text("• 检查USB线是否支持数据传输")
                        }
                        .font(SemanticFonts.body)
                        .padding(.leading)
                    }
                    
                    Group {
                        Text("📋 测试步骤")
                            .font(SemanticFonts.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. 打开终端应用")
                            Text("2. 输入：mtp-detect")
                            Text("3. 查看输出结果")
                            Text("4. 如果看到设备但有权限错误，说明检测正常")
                        }
                        .font(SemanticFonts.body)
                        .padding(.leading)
                    }
                }
            }
            
            HStack {
                Button("打开终端") {
                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}
