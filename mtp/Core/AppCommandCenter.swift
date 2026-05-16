//
//  AppCommandCenter.swift
//  mtp
//
//  Centralizes menu, toolbar, and keyboard command routing.
//

import Foundation
import AppKit
import Combine

@MainActor
final class AppCommandCenter: ObservableObject {
    static let shared = AppCommandCenter()
    
    @Published var isTransferQueueVisible: Bool = AppSettings.shared.showTransferQueue
    
    private weak var viewModel: MTPViewModel?
    
    private init() {}
    
    func register(viewModel: MTPViewModel) {
        self.viewModel = viewModel
    }
    
    func toggleTransferQueue() {
        isTransferQueueVisible.toggle()
        AppSettings.shared.showTransferQueue = isTransferQueueVisible
    }
    
    func refresh() {
        Task {
            await viewModel?.refreshCurrentLocation()
        }
    }
    
    func upload() {
        viewModel?.uploadFiles()
    }
    
    func download() {
        viewModel?.downloadSelectedFiles()
    }
    
    func quickLook() {
        viewModel?.previewSelectedFiles()
    }
    
    func openSelected() {
        viewModel?.openSelectedFile()
    }
    
    func deleteSelected() {
        viewModel?.deleteSelectedFiles()
    }
    
    func selectAll() {
        viewModel?.selectAllFiles()
    }
    
    func showSettings() {
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
