//
//  AudioQualityView.swift
//  VoiceTranslation
//
//  Created by Claude on 2025-08-12.
//

import SwiftUI
import Combine

struct AudioQualityView: View {
    @ObservedObject var audioQualityMonitor: AudioQualityMonitor
    @Binding var isPresented: Bool
    
    @State private var showDetailedReport = false
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题栏
            HStack {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                
                Text("音频质量监控")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("关闭") {
                    isPresented = false
                }
                .buttonStyle(.borderless)
            }
            
            if audioQualityMonitor.isMonitoring {
                // 实时监控视图
                VStack(spacing: 16) {
                    // 当前状态指示器
                    CurrentStatusIndicator(monitor: audioQualityMonitor)
                    
                    // 实时指标
                    RealTimeMetrics(monitor: audioQualityMonitor)
                    
                    // 问题检测
                    if !audioQualityMonitor.detectedIssues.isEmpty {
                        IssuesList(issues: audioQualityMonitor.detectedIssues)
                    }
                }
            } else {
                // 静态报告视图
                VStack(spacing: 16) {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)
                    
                    Text("音频质量监控已停止")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("开始录音时将自动启动监控")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 200)
            }
            
            // 控制按钮
            HStack(spacing: 12) {
                Button("重置数据") {
                    audioQualityMonitor.resetData()
                }
                .buttonStyle(.bordered)
                .disabled(audioQualityMonitor.isMonitoring)
                
                Button("详细报告") {
                    showDetailedReport.toggle()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if audioQualityMonitor.isMonitoring {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("监控中")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 500, height: showDetailedReport ? 600 : 400)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .sheet(isPresented: $showDetailedReport) {
            DetailedReportView(audioQualityMonitor: audioQualityMonitor)
        }
    }
}

struct CurrentStatusIndicator: View {
    @ObservedObject var monitor: AudioQualityMonitor
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("音频状态")
                    .font(.headline)
                
                Spacer()
                
                HStack {
                    Text(monitor.currentStatus.emoji)
                        .font(.title2)
                    
                    Text(monitor.currentStatus.description)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                }
            }
            
            ProgressView(value: monitor.currentStatus.percentage)
                .progressViewStyle(LinearProgressViewStyle(tint: statusColor))
        }
        .padding()
        .background(statusColor.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch monitor.currentStatus {
        case .excellent, .good:
            return .green
        case .fair:
            return .orange
        case .poor:
            return .red
        case .silent:
            return .gray
        case .error:
            return .red
        }
    }
}

struct RealTimeMetrics: View {
    @ObservedObject var monitor: AudioQualityMonitor
    
    var body: some View {
        VStack(spacing: 12) {
            Text("实时指标")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    title: "音量",
                    value: String(format: "%.1f%%", (monitor.currentMetrics?.volume ?? 0) * 100),
                    icon: "speaker.wave.3.fill",
                    color: .blue
                )
                
                MetricCard(
                    title: "峰值",
                    value: String(format: "%.1f%%", (monitor.currentMetrics?.peak ?? 0) * 100),
                    icon: "waveform",
                    color: .green
                )
                
                MetricCard(
                    title: "有效值",
                    value: String(format: "%.1f%%", (monitor.currentMetrics?.rms ?? 0) * 100),
                    icon: "chart.bar.fill",
                    color: .orange
                )
                
                MetricCard(
                    title: "静音比例",
                    value: String(format: "%.1f%%", (monitor.currentMetrics?.silenceRatio ?? 0) * 100),
                    icon: "speaker.slash.fill",
                    color: .gray
                )
            }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            HStack {
                Text(value)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
            }
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

struct IssuesList: View {
    let issues: [AudioIssue]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("检测到的问题")
                .font(.headline)
                .foregroundColor(.red)
            
            ScrollView(.vertical) {
                LazyVStack(spacing: 4) {
                    ForEach(Array(issues.suffix(5).enumerated()), id: \.offset) { index, issue in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            
                            Text(issue.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }
            .frame(maxHeight: 120)
        }
    }
}

struct DetailedReportView: View {
    @ObservedObject var audioQualityMonitor: AudioQualityMonitor
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("详细音频质量报告")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("关闭") {
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 统计摘要
                    StatisticsSummary(monitor: audioQualityMonitor)
                    
                    // 历史趋势
                    if !audioQualityMonitor.recentMetrics.isEmpty {
                        HistoricalTrend(metrics: audioQualityMonitor.recentMetrics)
                    }
                    
                    // 问题历史
                    if !audioQualityMonitor.detectedIssues.isEmpty {
                        IssueHistory(issues: audioQualityMonitor.detectedIssues)
                    }
                    
                    // 原始报告文本
                    RawReportText(report: audioQualityMonitor.getQualityReport())
                }
            }
            
            Button("导出报告") {
                exportReport()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 600, height: 500)
    }
    
    private func exportReport() {
        let report = audioQualityMonitor.getQualityReport()
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "audio_quality_report.txt"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? report.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

struct StatisticsSummary: View {
    @ObservedObject var monitor: AudioQualityMonitor
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("统计摘要")
                .font(.headline)
            
            if !monitor.recentMetrics.isEmpty {
                let avgVolume = monitor.recentMetrics.map { $0.volume }.reduce(0, +) / Float(monitor.recentMetrics.count)
                let avgRMS = monitor.recentMetrics.map { $0.rms }.reduce(0, +) / Float(monitor.recentMetrics.count)
                let totalClips = monitor.recentMetrics.map { $0.clipCount }.reduce(0, +)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatCard(title: "平均音量", value: "\(String(format: "%.1f", avgVolume * 100))%", color: .blue)
                    StatCard(title: "平均有效值", value: "\(String(format: "%.1f", avgRMS * 100))%", color: .green)
                    StatCard(title: "削波次数", value: "\(totalClips)", color: .red)
                    
                    StatCard(title: "样本数量", value: "\(monitor.recentMetrics.count)", color: .gray)
                    StatCard(title: "静音时长", value: "\(String(format: "%.1f", monitor.silentPeriodDuration))s", color: .orange)
                    StatCard(title: "问题数量", value: "\(monitor.detectedIssues.count)", color: .red)
                }
            } else {
                Text("暂无统计数据")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct HistoricalTrend: View {
    let metrics: [AudioQualityMetrics]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("历史趋势")
                .font(.headline)
            
            // 简单的趋势显示
            HStack(spacing: 2) {
                ForEach(Array(metrics.suffix(30).enumerated()), id: \.offset) { index, metric in
                    Rectangle()
                        .fill(colorForStatus(metric.status))
                        .frame(width: 8, height: CGFloat(metric.volume * 50 + 10))
                }
            }
            .frame(height: 60)
            
            HStack {
                ForEach(AudioQualityStatus.allCases, id: \.self) { status in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(colorForStatus(status))
                            .frame(width: 8, height: 8)
                        
                        Text(status.description)
                            .font(.caption)
                    }
                }
            }
        }
    }
    
    private func colorForStatus(_ status: AudioQualityStatus) -> Color {
        switch status {
        case .excellent:
            return .green
        case .good:
            return .yellow
        case .fair:
            return .orange
        case .poor:
            return .red
        case .silent:
            return .gray
        case .error:
            return .purple
        }
    }
}

extension AudioQualityStatus: CaseIterable {
    public static var allCases: [AudioQualityStatus] = [
        .excellent, .good, .fair, .poor, .silent, .error
    ]
}

struct IssueHistory: View {
    let issues: [AudioIssue]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("问题历史")
                .font(.headline)
            
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { index, issue in
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            
                            Text(issue.description)
                                .font(.caption)
                            
                            Spacer()
                            
                            Text("#\(index + 1)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }
}

struct RawReportText: View {
    let report: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("原始报告")
                .font(.headline)
            
            ScrollView {
                Text(report)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(8)
            }
            .frame(maxHeight: 200)
        }
    }
}

#Preview {
    AudioQualityView(
        audioQualityMonitor: AudioQualityMonitor(),
        isPresented: .constant(true)
    )
}