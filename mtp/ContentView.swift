//
//  ContentView.swift
//  mtp
//
//  Created by Li on 2026/4/18.
//

import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var viewModel = MTPViewModel()
    @StateObject private var commandCenter = AppCommandCenter.shared
    @StateObject private var settings = AppSettings.shared
    @State private var showingDualPane = false
    
    var body: some View {
        Group {
            if showingDualPane {
                DualPaneView(viewModel: viewModel)
            } else {
                NavigationSplitView {
                    DeviceListView(viewModel: viewModel)
                } detail: {
                    FileListView(viewModel: viewModel)
                }
            }
        }
        .navigationTitle("MTPMate")
        .frame(minWidth: showingDualPane ? 1000 : 900, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    commandCenter.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新")
                
                Button(action: {
                    showingDualPane.toggle()
                }) {
                    Label(
                        showingDualPane ? "单栏模式" : "双栏模式",
                        systemImage: showingDualPane ? "sidebar.left" : "rectangle.split.2x1"
                    )
                }
                .help(showingDualPane ? "切换到单栏模式" : "切换到双栏模式，方便与访达传输文件")
                
                Button {
                    commandCenter.toggleTransferQueue()
                } label: {
                    Label("传输队列", systemImage: "arrow.up.arrow.down.circle")
                }
                .help("显示或隐藏传输队列")
                
                Button {
                    commandCenter.showSettings()
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .help("打开设置")
            }
        }
        .inspector(isPresented: $commandCenter.isTransferQueueVisible) {
            TransferQueueView()
                .inspectorColumnWidth(min: 280, ideal: 340, max: 420)
        }
        .onAppear {
            commandCenter.register(viewModel: viewModel)
            commandCenter.isTransferQueueVisible = settings.showTransferQueue
        }
        .onChange(of: settings.showTransferQueue) { _, newValue in
            commandCenter.isTransferQueueVisible = newValue
        }
        .task {
            await viewModel.scanDevices()
        }
    }
}

#Preview {
    ContentView()
}