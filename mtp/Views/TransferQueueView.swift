//
//  TransferQueueView.swift
//  mtp
//
//  传输队列视图
//

import SwiftUI

struct TransferQueueView: View {
    @ObservedObject var queueManager = TransferQueueManager.shared
    @State private var showConflictDialog: TransferTask?
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部统计
            transferHeader
            
            Divider()
            
            // 任务列表
            if queueManager.tasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .sheet(item: $showConflictDialog) { task in
            ConflictResolutionDialog(task: task)
        }
    }
    
    // MARK: - 头部统计
    
    private var transferHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("传输队列")
                    .font(SemanticFonts.headline)
                
                Spacer()
                
                // 统计信息
                HStack(spacing: 16) {
                    Label("\(queueManager.transferringCount)", systemImage: "arrow.up.arrow.down.circle.fill")
                        .foregroundColor(SystemColors.info)
                    Label("\(queueManager.completedCount)", systemImage: "checkmark.circle.fill")
                        .foregroundColor(SystemColors.success)
                    if queueManager.failedCount > 0 {
                        Label("\(queueManager.failedCount)", systemImage: "xmark.circle.fill")
                            .foregroundColor(SystemColors.error)
                    }
                }
                .font(SemanticFonts.caption1)
                
                // 操作按钮
                Menu {
                    Button("清除已完成") {
                        queueManager.clearCompletedTasks()
                    }
                    .disabled(queueManager.completedCount == 0)
                    
                    Button("清除全部", role: .destructive) {
                        queueManager.clearAllTasks()
                    }
                    .disabled(queueManager.tasks.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            
            // 总体进度条
            if queueManager.isProcessing {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: queueManager.totalProgress)
                        .progressViewStyle(.linear)
                    
                    Text("总进度: \(Int(queueManager.totalProgress * 100))%")
                        .font(SemanticFonts.caption1)
                        .foregroundColor(SystemColors.secondaryText)
                }
            }
        }
        .padding()
    }
    
    // MARK: - 空状态
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(SemanticFonts.iconMedium)
                .foregroundColor(SystemColors.secondaryText)
            
            Text("暂无传输任务")
                .font(SemanticFonts.headline)
                .foregroundColor(SystemColors.secondaryText)
            
            Text("拖拽文件开始传输")
                .font(SemanticFonts.caption1)
                .foregroundColor(SystemColors.secondaryText)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 任务列表
    
    private var taskList: some View {
        List {
            ForEach(queueManager.tasks) { task in
                TransferTaskRow(task: task, onConflict: {
                    showConflictDialog = task
                })
            }
            .onMove { source, destination in
                queueManager.moveTask(from: source, to: destination)
            }
        }
    }
}

// MARK: - 任务行视图

struct TransferTaskRow: View {
    @ObservedObject var task: TransferTask
    let onConflict: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 文件名和状态
            HStack {
                // 方向图标
                Image(systemName: task.direction == .upload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundColor(task.direction == .upload ? .blue : .green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.fileName)
                        .font(SemanticFonts.body)
                        .lineLimit(1)
                    
                    Text(task.formattedSize)
                        .font(SemanticFonts.caption1)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // 状态图标
                statusIcon
                
                // 操作按钮
                taskControls
            }
            
            // 进度条（传输中时显示）
            if task.status == .transferring {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: task.progress)
                        .progressViewStyle(.linear)
                    
                    HStack {
                        Text("\(Int(task.progress * 100))%")
                        Spacer()
                        Text(task.formattedSpeed)
                        Text("·")
                        Text(task.formattedTimeRemaining)
                    }
                    .font(SemanticFonts.caption1)
                    .foregroundColor(.secondary)
                }
            }
            
            // 错误信息
            if case .failed(let error) = task.status {
                Text(error.localizedDescription)
                    .font(SemanticFonts.caption1)
                    .foregroundColor(.red)
            }
            
            // 冲突提示
            if task.status == .paused && task.conflictResolution == .ask {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("文件名冲突，需要处理")
                        .font(SemanticFonts.caption1)
                    Spacer()
                    Button("处理") {
                        onConflict()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch task.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .transferring:
            ProgressView()
                .scaleEffect(0.7)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .foregroundColor(.orange)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var taskControls: some View {
        HStack(spacing: 8) {
            switch task.status {
            case .pending, .transferring:
                Button {
                    TransferQueueManager.shared.pauseTask(task)
                } label: {
                    Image(systemName: "pause.fill")
                }
                .buttonStyle(.borderless)
                
                Button {
                    TransferQueueManager.shared.cancelTask(task)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                
            case .paused:
                Button {
                    TransferQueueManager.shared.resumeTask(task)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                
                Button {
                    TransferQueueManager.shared.cancelTask(task)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                
            case .failed:
                Button {
                    TransferQueueManager.shared.retryTask(task)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - 冲突解决对话框

struct ConflictResolutionDialog: View {
    @ObservedObject var task: TransferTask
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(SemanticFonts.title1)
                    .foregroundColor(.orange)
                
                Text("文件名冲突")
                    .font(SemanticFonts.title2)
                    .fontWeight(.bold)
            }
            
            // 说明
            VStack(alignment: .leading, spacing: 8) {
                Text("文件已存在:")
                    .font(SemanticFonts.headline)
                Text(task.fileName)
                    .font(SemanticFonts.body)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            
            // 选项
            VStack(spacing: 12) {
                conflictButton(
                    title: "重命名",
                    description: "自动生成新文件名",
                    icon: "doc.badge.plus",
                    resolution: .rename
                )
                
                conflictButton(
                    title: "覆盖",
                    description: "替换现有文件",
                    icon: "arrow.triangle.2.circlepath",
                    resolution: .overwrite
                )
                
                conflictButton(
                    title: "跳过",
                    description: "取消此文件传输",
                    icon: "forward.fill",
                    resolution: .skip
                )
            }
            
            // 取消按钮
            Button("取消") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(width: 400)
    }
    
    private func conflictButton(
        title: String,
        description: String,
        icon: String,
        resolution: ConflictResolution
    ) -> some View {
        Button {
            task.conflictResolution = resolution
            TransferQueueManager.shared.resumeTask(task)
            dismiss()
        } label: {
            HStack {
                Image(systemName: icon)
                    .font(SemanticFonts.title3)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SemanticFonts.headline)
                    Text(description)
                        .font(SemanticFonts.caption1)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TransferQueueView()
}
