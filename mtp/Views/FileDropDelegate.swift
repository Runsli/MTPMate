//
//  FileDropDelegate.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI
import UniformTypeIdentifiers

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
        guard viewModel.selectedDevice != nil else { return }
        
        Task {
            let uploadableURLs = urls.filter { url in
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                    return false
                }
                
                if isDirectory.boolValue {
                    Logger.warning("跳过文件夹拖拽: \(url.lastPathComponent)")
                    return false
                }
                
                return true
            }
            
            if !uploadableURLs.isEmpty {
                await viewModel.uploadFiles(uploadableURLs)
            }
        }
    }
}