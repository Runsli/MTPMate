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
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingDualPane.toggle()
                }) {
                    Label(
                        showingDualPane ? "单栏模式" : "双栏模式",
                        systemImage: showingDualPane ? "sidebar.left" : "rectangle.split.2x1"
                    )
                }
                .help(showingDualPane ? "切换到单栏模式" : "切换到双栏模式，方便与访达传输文件")
            }
        }
        .task {
            await viewModel.scanDevices()
        }
    }
}

#Preview {
    ContentView()
}