//
//  FileDropDelegate.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct FileDropDelegate: DropDelegate {
    let viewModel: MTPViewModel
    @Binding var isTargeted: Bool
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.fileURL])
    }
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        
        guard viewModel.selectedDevice != nil else { return false }
        
        let providers = info.itemProviders(for: [.fileURL])
        var urls: [URL] = []
        
        let group = DispatchGroup()
        
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                
                urls.append(url)
            }
        }
        
        group.notify(queue: .main) {
            handleDroppedFiles(urls: urls)
        }
        
        return true
    }
    
    private func handleDroppedFiles(urls: [URL]) {
        guard let device = viewModel.selectedDevice else { return }
        let currentFolderId = viewModel.pathComponents.last?.folderId
        
        Task {
            for url in urls {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
                
                if isDirectory.boolValue {
                    // 简化：暂时跳过文件夹拖拽，只支持文件
                    print("⚠️ 跳过文件夹拖拽: \(url.lastPathComponent)")
                    continue
                } else {
                    // 直接上传文件
                    await uploadFile(deviceId: device.id, sourceURL: url, toParentId: currentFolderId)
                }
            }
            
            // 刷新文件列表
            await viewModel.loadFiles(folderId: currentFolderId)
        }
    }
    
    private func uploadFile(deviceId: String, sourceURL: URL, toParentId parentId: String?) async {
        do {
            print("📤 拖拽上传: \(sourceURL.lastPathComponent)")
            
            let fileManager = MTPFileManager.shared
            let newFileId = try await fileManager.uploadFile(
                deviceId: deviceId,
                sourceURL: sourceURL,
                toParentId: parentId,
                fileName: sourceURL.lastPathComponent,
                progress: { _ in } // 简化：不显示进度
            )
            
            print("✅ 拖拽上传完成: \(sourceURL.lastPathComponent) (新ID: \(newFileId))")
            
            // 发送系统通知
            let content = UNMutableNotificationContent()
            content.title = "上传完成"
            content.body = sourceURL.lastPathComponent
            content.sound = .default
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                print("发送通知失败: \(error.localizedDescription)")
            }
            
        } catch {
            print("❌ 拖拽上传失败: \(sourceURL.lastPathComponent) - \(error)")
            
            await MainActor.run {
                viewModel.errorMessage = "上传失败: \(error.localizedDescription)"
            }
        }
    }
}