//
//  EnhancedFileListView.swift
//  mtp
//
//  增强的文件列表视图 - 集成拖拽预览和传输队列
//

import SwiftUI

struct EnhancedFileListView: View {
    @ObservedObject var viewModel: MTPViewModel
    @StateObject private var queueManager = TransferQueueManager.shared
    @State private var showTransferQueue = false
    
    var body: some View {
        HSplitView {
            // 主文件列表
            FileListView(viewModel: viewModel)
            
            // 传输队列侧边栏（可折叠）
            if showTransferQueue {
                TransferQueueView()
                    .frame(minWidth: 300, idealWidth: 350, maxWidth: 500)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation {
                        showTransferQueue.toggle()
                    }
                } label: {
                    Label(
                        "传输队列",
                        systemImage: showTransferQueue ? "sidebar.right" : "arrow.up.arrow.down.circle"
                    )
                }
                .help("显示/隐藏传输队列")
                .overlay(alignment: .topTrailing) {
                    if queueManager.transferringCount > 0 {
                        Text("\(queueManager.transferringCount)")
                            .font(SemanticFonts.badge)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Circle().fill(Color.red))
                            .offset(x: 8, y: -8)
                    }
                }
            }
        }
        .onAppear {
            // 如果有传输任务，自动显示队列
            if !queueManager.tasks.isEmpty {
                showTransferQueue = true
            }
        }
        .onChange(of: queueManager.tasks.count) { oldValue, newValue in
            // 新增任务时自动显示队列
            if newValue > oldValue && !showTransferQueue {
                withAnimation {
                    showTransferQueue = true
                }
            }
        }
    }
}

#Preview {
    EnhancedFileListView(viewModel: MTPViewModel())
        .frame(width: 1200, height: 700)
}
